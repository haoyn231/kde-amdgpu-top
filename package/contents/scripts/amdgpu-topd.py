#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 haoyn231
# SPDX-License-Identifier: MIT
"""amdgpu-topd —— 为 KDE Plasma 小程序供给 AMD GPU 数据的采集守护进程。

为什么需要它
    Plasma 的 executable 数据引擎会一直缓冲子进程的标准输出，直到子进程结束才
    一次性交付，所以没法直接读 `amdgpu_top -J` 的实时流。这里改成"常驻进程 +
    快照文件"：守护进程只启动一次 amdgpu_top，逐帧压缩数据，用原子替换写入
    snapshot.json；小程序那边用 `cat` 轮询该文件即可，读到的永远是完整的一帧。

行为约定
    --ensure      幂等启动。参数没变就只打印快照路径；参数变了会重启旧实例。
    --foreground  前台运行采集循环（一般由 --ensure 拉起）。
    --stop        停止正在运行的实例。
    --status      打印实例状态，便于排障。
    --once        采集一帧写到标准输出，不落盘，方便手工验证。

资源占用
    整个守护进程只托着一个 amdgpu_top 子进程，另外每秒做一次 JSON 解析与一次
    原子写入；默认带 --no-pc，不读性能计数器，因此不会干扰 GPU 的省电策略。

SPDX-License-Identifier: MIT
"""

from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
import queue
import signal
import subprocess
import sys
import threading
import time
from collections import deque

APP_NAME = "kde-amdgpu-top"
HISTORY_LEN = 60          # 保留最近 60 帧，供弹窗里的迷你曲线使用
MAX_PROCESSES = 64        # 快照里最多保留多少个进程（按显存排序）
STALE_AFTER = 5.0         # 多久没有新帧就认为采集卡住了
GUARD_INTERVAL = 5.0      # 检查 plasmashell / 心跳的间隔
HEARTBEAT_TIMEOUT = 90.0  # 小程序多久没来 --ensure 就认为它已被移除


# --------------------------------------------------------------------------- #
# 路径与文件工具
# --------------------------------------------------------------------------- #
def base_dir() -> str:
    """快照/锁文件所在目录。优先用 XDG_RUNTIME_DIR，退出登录即自动清理。"""
    runtime = os.environ.get("XDG_RUNTIME_DIR", "")
    if runtime and os.path.isdir(runtime) and os.access(runtime, os.W_OK):
        return os.path.join(runtime, APP_NAME)
    return os.path.join("/tmp", "%s-%d" % (APP_NAME, os.getuid()))


def cache_dir() -> str:
    cache = os.environ.get("XDG_CACHE_HOME", "") or os.path.join(
        os.path.expanduser("~"), ".cache"
    )
    return os.path.join(cache, APP_NAME)


def snapshot_path() -> str:
    return os.path.join(base_dir(), "snapshot.json")


def pid_path() -> str:
    return os.path.join(base_dir(), "daemon.pid")


def lock_path() -> str:
    return os.path.join(base_dir(), "daemon.lock")


def args_path() -> str:
    return os.path.join(base_dir(), "daemon.args")


def heartbeat_path() -> str:
    return os.path.join(base_dir(), "daemon.hb")


def log_path() -> str:
    return os.path.join(cache_dir(), "daemon.log")


def touch_heartbeat() -> None:
    """小程序每 15 秒会 --ensure 一次，这个文件就是"我还活着"的证据。"""
    try:
        path = heartbeat_path()
        ensure_dir(os.path.dirname(path))
        with open(path, "a", encoding="utf-8"):
            pass
        os.utime(path, None)
    except OSError:
        pass


def heartbeat_age() -> float:
    try:
        return time.time() - os.path.getmtime(heartbeat_path())
    except OSError:
        return float("inf")


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def write_json_atomic(path: str, payload: dict) -> None:
    """先写同目录临时文件再 os.replace，读取端不会看到半截 JSON。"""
    directory = os.path.dirname(path)
    ensure_dir(directory)
    tmp = os.path.join(directory, ".%s.%d.tmp" % (os.path.basename(path), os.getpid()))
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, path)


def read_json(path: str, default=None):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except OSError as exc:
        return exc.errno == errno.EPERM
    return True


def read_cmdline(pid: int) -> str:
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as handle:
            return handle.read(4096).replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def plasmashell_running() -> bool:
    """扫一遍 /proc 找 comm == plasmashell，比 fork pgrep 便宜。"""
    try:
        entries = os.listdir("/proc")
    except OSError:
        return True
    for entry in entries:
        if not entry.isdigit():
            continue
        try:
            with open("/proc/%s/comm" % entry, "rb") as handle:
                if handle.read(32).strip() == b"plasmashell":
                    return True
        except OSError:
            continue
    return False


# --------------------------------------------------------------------------- #
# 帧解析：把 amdgpu_top 的巨型 JSON 压成小程序要的那点字段
# --------------------------------------------------------------------------- #
def num(entry, default=0.0) -> float:
    """amdgpu_top 的数值字段统一是 {"unit": "W", "value": 28} 或 null。"""
    if isinstance(entry, dict):
        value = entry.get("value")
        if isinstance(value, bool):
            return default
        if isinstance(value, (int, float)):
            return float(value)
    if isinstance(entry, (int, float)) and not isinstance(entry, bool):
        return float(entry)
    return default


def round_or_none(value, digits=1):
    if value is None:
        return None
    return round(float(value), digits)


def proc_meta(pid: int):
    """读 /proc/<pid> 拿完整命令行与父进程号；进程消失就返回空。"""
    cmdline = ""
    ppid = 0
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as handle:
            cmdline = handle.read(600).replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        pass
    try:
        with open("/proc/%d/stat" % pid, "rb") as handle:
            raw = handle.read(2048)
        # comm 字段可能带空格和括号，从最后一个 ')' 之后开始数：
        # 之后依次是 state(3) ppid(4)
        ppid = int(raw[raw.rindex(b")") + 2:].split()[1])
    except (OSError, ValueError, IndexError):
        ppid = 0
    if len(cmdline) > 400:
        cmdline = cmdline[:399] + "…"
    return cmdline, ppid


def tool_version(frame: dict) -> str:
    version = frame.get("amdgpu_top_version") or {}
    if not isinstance(version, dict):
        return ""
    parts = [version.get("major"), version.get("minor"), version.get("patch")]
    if any(part is None for part in parts):
        return ""
    return ".".join(str(int(part)) for part in parts)


def build_snapshot(frame: dict, gpu_index: int = 0, max_procs: int = MAX_PROCESSES) -> dict:
    """把一帧 amdgpu_top JSON 转成快照字典（纯函数，方便单测）。"""
    now = time.time()
    version = tool_version(frame)
    devices = frame.get("devices") or []

    names = []
    for device in devices:
        info = device.get("Info") or {}
        names.append(str(info.get("DeviceName") or "AMD GPU"))

    if not devices:
        return {
            "ok": False,
            "ts": now,
            "tool": version,
            "gpus": names,
            "error": "没有检测到 AMD GPU",
            "hint": "确认 amdgpu 内核模块已加载：lsmod | grep amdgpu",
        }

    index = min(max(gpu_index, 0), len(devices) - 1)
    device = devices[index]
    info = device.get("Info") or {}
    sensors = device.get("Sensors") or {}
    activity = device.get("gpu_activity") or {}
    vram = device.get("VRAM") or {}
    totals = device.get("Total fdinfo") or {}
    device_path = info.get("DevicePath") or {}
    clocks = info.get("GPU Clock") or {}

    pcie = sensors.get("PCIe Link Speed") or {}
    pcie_text = ""
    if isinstance(pcie, dict) and pcie.get("gen"):
        pcie_text = "PCIe %s.0 ×%s" % (pcie.get("gen"), pcie.get("width", "?"))

    processes = []
    fdinfo = device.get("fdinfo") or {}
    if isinstance(fdinfo, dict):
        for pid_key, entry in fdinfo.items():
            try:
                pid = int(pid_key)
            except (TypeError, ValueError):
                continue
            if not isinstance(entry, dict):
                continue
            # 不同版本嵌套层次不同：既可能是 {name, usage:{usage:{...}}}，
            # 也可能直接给 usage 字典。
            inner = entry.get("usage")
            if isinstance(inner, dict) and isinstance(inner.get("usage"), dict):
                usage = inner["usage"]
            elif isinstance(inner, dict):
                usage = inner
            else:
                usage = {}
            vram_mib = num(usage.get("VRAM"))
            gtt_mib = num(usage.get("GTT"))
            gfx = num(usage.get("GFX"))
            media = num(usage.get("Media"))
            encode = num(usage.get("Encode"))
            decode = num(usage.get("Decode"))
            cmdline, ppid = proc_meta(pid)
            name = str(entry.get("name") or "").strip()
            if not name:
                name = os.path.basename(cmdline.split(" ")[0]) if cmdline else str(pid)
            processes.append(
                {
                    "pid": pid,
                    "name": name,
                    "cmd": cmdline,
                    "ppid": ppid,
                    "vram": round(vram_mib, 1),
                    "gtt": round(gtt_mib, 1),
                    "gfx": round(gfx, 1),
                    "media": round(media, 1),
                    "enc": round(encode, 1),
                    "dec": round(decode, 1),
                }
            )
    processes.sort(key=lambda item: (-item["vram"], -item["gfx"], item["pid"]))

    total_vram = num(vram.get("Total VRAM"))
    used_vram = num(vram.get("Total VRAM Usage"))
    total_gtt = num(vram.get("Total GTT"))
    used_gtt = num(vram.get("Total GTT Usage"))

    snapshot = {
        "ok": True,
        "ts": now,
        "tool": version,
        "gpus": names,
        "gpu_index": index,
        "name": str(info.get("DeviceName") or names[index]),
        "chip": str(info.get("Chip Class") or ""),
        "asic": str(info.get("ASIC Name") or ""),
        "type": str(info.get("GPU Type") or ""),
        "pci": str(device_path.get("pci") or ""),
        "card": str(device_path.get("card") or ""),
        "pcie": pcie_text,
        "load": {
            "gfx": round(num(activity.get("GFX")), 1),
            "mem": round(num(activity.get("Memory")), 1),
            "media": round(num(activity.get("MediaEngine")), 1),
        },
        "vram": {
            "used": round(used_vram, 1),
            "total": round(total_vram, 1),
            "gtt_used": round(used_gtt, 1),
            "gtt_total": round(total_gtt, 1),
        },
        "temp": {
            "edge": round_or_none(num(sensors.get("Edge Temperature"), None)),
            "junction": round_or_none(num(sensors.get("Junction Temperature"), None)),
            "mem": round_or_none(num(sensors.get("Memory Temperature"), None)),
            "critical": round_or_none(num(sensors.get("Edge Critical Temperature"), None)),
        },
        "power": {
            "avg": round_or_none(num(sensors.get("Average Power"), None)),
            "gfx": round_or_none(num(sensors.get("GFX Power"), None)),
        },
        "fan": {
            "rpm": round_or_none(num(sensors.get("Fan"), None)),
            "max": round_or_none(num(sensors.get("Fan Max"), None)),
        },
        "clk": {
            "sclk": round_or_none(num(sensors.get("GFX_SCLK"), None)),
            "mclk": round_or_none(num(sensors.get("GFX_MCLK"), None)),
            "fclk": round_or_none(num(sensors.get("FCLK"), None)),
            "max": round_or_none(num(clocks.get("max"), None)),
        },
        "volt": round_or_none(num(sensors.get("VDDGFX"), None)),
        "power_state": str(sensors.get("PCI Power State") or ""),
        "profile": str(sensors.get("Power Profile") or ""),
        "totals": {
            "vram": round(num(totals.get("VRAM")), 1),
            "gtt": round(num(totals.get("GTT")), 1),
            "gfx": round(num(totals.get("GFX")), 1),
        },
        "procs": processes[:max_procs],
        "proc_count": len(processes),
    }
    return snapshot


def error_snapshot(message: str, hint: str = "", tool: str = "") -> dict:
    return {
        "ok": False,
        "ts": time.time(),
        "tool": tool,
        "gpus": [],
        "error": message,
        "hint": hint,
    }


# --------------------------------------------------------------------------- #
# 采集循环
# --------------------------------------------------------------------------- #
class Collector:
    """托住 amdgpu_top 子进程，按需压缩并落盘。"""

    def __init__(self, options):
        self.options = options
        self.stop = threading.Event()
        self.process = None
        self.stderr_tail = deque(maxlen=40)
        self.gfx_history = deque(maxlen=HISTORY_LEN)
        self.vram_history = deque(maxlen=HISTORY_LEN)
        self.frames = 0
        self.next_guard = time.monotonic() + GUARD_INTERVAL

    # -- 子进程 ------------------------------------------------------------ #
    def _spawn(self):
        command = [self.options.tool, "-J"]
        if not self.options.pc:
            command.append("--no-pc")
        self.log("spawn: %s" % " ".join(command))
        return subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )

    def _pump(self, stream, target_queue):
        try:
            for raw in iter(stream.readline, b""):
                target_queue.put(raw)
        except (ValueError, OSError):
            pass
        finally:
            target_queue.put(None)

    # -- 落盘 -------------------------------------------------------------- #
    def _store(self, snapshot: dict) -> None:
        if snapshot.get("ok"):
            self.gfx_history.append(snapshot["load"]["gfx"])
            self.vram_history.append(
                round(snapshot["vram"]["used"] / snapshot["vram"]["total"] * 100.0, 1)
                if snapshot["vram"]["total"]
                else 0.0
            )
            snapshot["hist"] = {
                "gfx": list(self.gfx_history),
                "vram": list(self.vram_history),
            }
            snapshot["interval"] = self.options.interval
        write_json_atomic(self.options.out, snapshot)

    def log(self, message: str) -> None:
        if self.options.verbose:
            sys.stderr.write("[%s] %s\n" % (time.strftime("%H:%M:%S"), message))
            sys.stderr.flush()

    # -- 主循环 ------------------------------------------------------------ #
    def run(self) -> int:
        ensure_dir(os.path.dirname(self.options.out))

        ensure_dir(base_dir())
        ensure_dir(cache_dir())
        lock_handle = open(lock_path(), "a+")
        try:
            fcntl.flock(lock_handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.log("另一个实例已持有锁，退出")
            return 1
        self.lock_handle = lock_handle  # 持有到进程退出，起到单例作用

        with open(pid_path(), "w", encoding="utf-8") as handle:
            handle.write(str(os.getpid()))

        for sig in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            try:
                signal.signal(sig, self._on_signal)
            except (ValueError, OSError):
                pass

        exit_code = 0
        last_write = 0.0
        try:
            while not self.stop.is_set():
                exit_code = self._session()
                if self.stop.is_set():
                    break
                self.stop.wait(5.0)
        finally:
            self._terminate_child()
            try:
                os.unlink(pid_path())
            except OSError:
                pass
        return exit_code

    def _session(self) -> int:
        """启动一次 amdgpu_top 并读完它的一生；返回退出码语义。"""
        if self.options.guard and not plasmashell_running():
            self.log("plasmashell 不在运行，守护进程退出")
            self.stop.set()
            return 0

        try:
            self.process = self._spawn()
        except FileNotFoundError:
            self.log("找不到 %s" % self.options.tool)
            self._store(
                error_snapshot(
                    "未找到 %s" % self.options.tool,
                    "安装：sudo pacman -S amdgpu_top",
                )
            )
            return 127
        except OSError as exc:
            self._store(error_snapshot("启动 %s 失败：%s" % (self.options.tool, exc)))
            return 1

        frames = queue.Queue()
        errors = queue.Queue()
        threading.Thread(target=self._pump, args=(self.process.stdout, frames), daemon=True).start()
        threading.Thread(target=self._pump, args=(self.process.stderr, errors), daemon=True).start()

        last_frame = time.monotonic()
        last_write = 0.0
        announced_stale = False
        while not self.stop.is_set():
            # 消费错误输出（只留尾巴，出错时给用户看）
            while True:
                try:
                    line = errors.get_nowait()
                except queue.Empty:
                    break
                if line:
                    self.stderr_tail.append(line.decode("utf-8", "replace").rstrip())

            try:
                line = frames.get(timeout=0.4)
            except queue.Empty:
                line = b""

            if line is None:  # amdgpu_top 退出了
                break

            if line:
                last_frame = time.monotonic()
                announced_stale = False
                try:
                    frame = json.loads(line)
                except ValueError:
                    continue
                snapshot = build_snapshot(
                    frame, self.options.gpu_index, self.options.max_processes
                )
                now = time.monotonic()
                if now - last_write >= self.options.interval * 0.85:
                    self._store(snapshot)
                    last_write = now
                    self.frames += 1
                    if self.options.frames and self.frames >= self.options.frames:
                        self.stop.set()
                        break

            if time.monotonic() - last_frame > STALE_AFTER and not announced_stale:
                announced_stale = True
                self._store(
                    error_snapshot(
                        "等待 %s 返回数据…" % self.options.tool,
                        "GPU 可能在挂起状态，或 amdgpu_top 卡住了",
                    )
                )

            if time.monotonic() >= self.next_guard:
                self.next_guard = time.monotonic() + GUARD_INTERVAL
                if self.options.guard and not plasmashell_running():
                    self.log("plasmashell 已退出，守护进程退出")
                    self.stop.set()
                    break
                # 小组件被移除后没人再 --ensure，心跳就会停，这里自己收摊
                if self.options.guard and heartbeat_age() > HEARTBEAT_TIMEOUT:
                    self.log("超过 %.0f 秒没有心跳，小组件可能已被移除，退出" % HEARTBEAT_TIMEOUT)
                    self.stop.set()
                    break

            # 子进程自行退出但队列还没送 None
            if self.process.poll() is not None and not line:
                break

        self._terminate_child()

        if self.stop.is_set():
            return 0

        detail = "\n".join(list(self.stderr_tail)[-3:]).strip()
        message = "%s 意外退出（退出码 %s）" % (self.options.tool, self.process.returncode)
        if detail:
            message += "：" + detail
        self._store(error_snapshot(message, "守护进程 5 秒后重试"))
        return 0

    def _terminate_child(self) -> None:
        process = self.process
        if process is None or process.poll() is not None:
            return
        try:
            process.terminate()
            process.wait(timeout=2)
        except (OSError, subprocess.TimeoutExpired):
            try:
                process.kill()
            except OSError:
                pass

    def _on_signal(self, signum, _frame) -> None:
        self.log("收到信号 %s，准备退出" % signum)
        self.stop.set()


# --------------------------------------------------------------------------- #
# 实例管理
# --------------------------------------------------------------------------- #
def child_arguments(options) -> list:
    argv = [
        "--foreground",
        "--out", options.out,
        "--interval", str(options.interval),
        "--gpu-index", str(options.gpu_index),
        "--max-processes", str(options.max_processes),
        "--tool", options.tool,
    ]
    if options.pc:
        argv.append("--pc")
    if options.guard:
        argv.append("--guard")
    if options.verbose:
        argv.append("--verbose")
    return argv


def daemon_signature(script: str, argv: list) -> str:
    return json.dumps({"script": script, "argv": argv}, sort_keys=True)


def is_our_daemon(pid: int) -> bool:
    if not pid_alive(pid):
        return False
    cmdline = read_cmdline(pid)
    return "amdgpu-topd.py" in cmdline and "--foreground" in cmdline


def running_daemon():
    state = read_json(args_path(), {}) or {}
    pid = int(state.get("pid") or 0)
    if is_our_daemon(pid):
        return pid, state.get("sig", "")
    return 0, ""


def stop_daemon(timeout: float = 3.0) -> bool:
    pid, _ = running_daemon()
    if not pid:
        return False
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        return False
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not pid_alive(pid):
            return True
        time.sleep(0.05)
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
    return True


def ensure_daemon(options) -> int:
    ensure_dir(base_dir())
    touch_heartbeat()
    script = os.path.realpath(__file__)
    argv = child_arguments(options)
    signature = daemon_signature(script, argv)

    pid, current_signature = running_daemon()
    if pid and current_signature == signature:
        print(options.out)
        return 0
    if pid:
        if options.verbose:
            sys.stderr.write("参数变化，重启守护进程 %d\n" % pid)
        stop_daemon()

    # 参数完全相同的实例可能还在启动中（锁还没抢到），给它一点时间
    ensure_dir(cache_dir())
    log = open(log_path(), "ab")
    try:
        process = subprocess.Popen(
            [sys.executable, script] + argv,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            start_new_session=True,
            close_fds=True,
            cwd=os.path.expanduser("~"),
        )
    finally:
        log.close()

    write_json_atomic(args_path(), {"pid": process.pid, "sig": signature})
    print(options.out)
    return 0


def print_status(options) -> int:
    pid, signature = running_daemon()
    snapshot = read_json(options.out, {}) or {}
    age = ""
    if snapshot.get("ts"):
        age = "%.1fs 前" % max(0.0, time.time() - snapshot["ts"])
    print("脚本      : %s" % os.path.realpath(__file__))
    print("快照文件  : %s" % options.out)
    print("守护进程  : %s" % ("运行中 pid=%d" % pid if pid else "未运行"))
    print("参数      : %s" % (signature or "-"))
    print("最近一帧  : %s" % (age or "-"))
    if snapshot:
        print("状态      : %s" % ("ok" if snapshot.get("ok") else snapshot.get("error", "?")))
        if snapshot.get("ok"):
            print(
                "GPU       : %s | 负载 %s%% | 显存 %s/%s MiB"
                % (
                    snapshot.get("name"),
                    snapshot["load"]["gfx"],
                    snapshot["vram"]["used"],
                    snapshot["vram"]["total"],
                )
            )
    return 0


def collect_once(options) -> int:
    """调试用：跑一帧，打印快照到 stdout。"""
    try:
        process = subprocess.Popen(
            [options.tool, "-J"] + ([] if options.pc else ["--no-pc"]),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except FileNotFoundError:
        json.dump(error_snapshot("未找到 %s" % options.tool), sys.stdout, ensure_ascii=False)
        print()
        return 127
    try:
        line = process.stdout.readline()
    finally:
        process.kill()
    if not line:
        json.dump(error_snapshot("%s 没有输出" % options.tool), sys.stdout, ensure_ascii=False)
        print()
        return 1
    snapshot = build_snapshot(json.loads(line), options.gpu_index, options.max_processes)
    json.dump(snapshot, sys.stdout, ensure_ascii=False, indent=2)
    print()
    return 0


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="为 KDE Plasma AMD GPU 小程序采集 amdgpu_top 数据",
    )
    parser.add_argument("--ensure", action="store_true", help="确保守护进程在运行（幂等）")
    parser.add_argument("--foreground", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--stop", action="store_true", help="停止守护进程")
    parser.add_argument("--status", action="store_true", help="打印守护进程状态")
    parser.add_argument("--once", action="store_true", help="采集一帧并打印，不落盘")
    parser.add_argument("--interval", type=float, default=1.0, help="快照写入间隔（秒）")
    parser.add_argument("--gpu-index", type=int, default=0, help="多 AMD GPU 时选第几个（从 0 开始）")
    parser.add_argument("--max-processes", type=int, default=MAX_PROCESSES, help="快照保留的进程数上限")
    parser.add_argument("--out", default=snapshot_path(), help="快照文件路径")
    parser.add_argument("--tool", default="amdgpu_top", help="amdgpu_top 可执行文件路径")
    parser.add_argument("--pc", action="store_true", help="读取性能计数器（默认关闭，省电）")
    parser.add_argument("--guard", action="store_true", help="plasmashell 退出后自动结束")
    parser.add_argument("--frames", type=int, default=0, help="采集 N 帧后退出（调试）")
    parser.add_argument("--verbose", action="store_true", help="输出调试日志到 stderr")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    options = parse_args(argv)
    if options.interval <= 0:
        options.interval = 1.0

    if options.stop:
        stopped = stop_daemon()
        print("已停止" if stopped else "没有运行中的实例")
        return 0
    if options.status:
        return print_status(options)
    if options.ensure:
        return ensure_daemon(options)
    if options.once:
        return collect_once(options)
    return Collector(options).run()


if __name__ == "__main__":
    sys.exit(main())
