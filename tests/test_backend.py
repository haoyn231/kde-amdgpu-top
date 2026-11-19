#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 haoyn231
# SPDX-License-Identifier: MIT
"""amdgpu-topd 的单元测试（不需要显卡，也不需要 amdgpu_top）。

    python3 tests/test_backend.py
"""

import importlib.util
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "package", "contents", "scripts", "amdgpu-topd.py")

spec = importlib.util.spec_from_file_location("amdgpu_topd", SCRIPT)
backend = importlib.util.module_from_spec(spec)
sys.modules["amdgpu_topd"] = backend
spec.loader.exec_module(backend)


def value(number, unit):
    return {"unit": unit, "value": number}


def make_frame(processes=None):
    """构造一帧和 amdgpu_top 0.11.x 结构一致的 JSON。"""
    processes = processes if processes is not None else {
        "100": {
            "name": "game",
            "usage": {
                "name": "game",
                "usage": {
                    "VRAM": value(2048, "MiB"),
                    "GTT": value(32, "MiB"),
                    "GFX": value(63.5, "%"),
                    "Media": value(0, "%"),
                    "Encode": None,
                    "Decode": None,
                },
            },
        },
        "200": {
            "name": "plasmashell",
            "usage": {
                "name": "plasmashell",
                "usage": {
                    "VRAM": value(320, "MiB"),
                    "GTT": value(24, "MiB"),
                    "GFX": value(1, "%"),
                    "Media": None,
                },
            },
        },
    }

    return {
        "amdgpu_top_version": {"major": 0, "minor": 11, "patch": 5},
        "devices": [
            {
                "Info": {
                    "DeviceName": "AMD Radeon RX 9070 GRE",
                    "Chip Class": "GFX12",
                    "ASIC Name": "GFX1201",
                    "GPU Type": "dGPU",
                    "DevicePath": {"pci": "0000:04:00.0", "card": "/dev/dri/card2"},
                    "GPU Clock": {"min": 500, "max": 2340},
                },
                "Sensors": {
                    "Average Power": value(28, "W"),
                    "GFX Power": value(28, "W"),
                    "Edge Temperature": value(45, "C"),
                    "Junction Temperature": value(48, "C"),
                    "Memory Temperature": None,
                    "Edge Critical Temperature": value(110, "C"),
                    "Fan": value(0, "RPM"),
                    "Fan Max": value(3200, "RPM"),
                    "GFX_SCLK": value(1601, "MHz"),
                    "GFX_MCLK": value(456, "MHz"),
                    "FCLK": value(1909, "MHz"),
                    "VDDGFX": value(703, "mV"),
                    "PCIe Link Speed": {"gen": 5, "width": 16},
                    "PCI Power State": "D0",
                    "Power Profile": "BOOTUP_DEFAULT",
                },
                "gpu_activity": {
                    "GFX": value(13, "%"),
                    "Memory": value(2, "%"),
                    "MediaEngine": value(0, "%"),
                },
                "VRAM": {
                    "Total VRAM": value(12224, "MiB"),
                    "Total VRAM Usage": value(3977, "MiB"),
                    "Total GTT": value(15726, "MiB"),
                    "Total GTT Usage": value(420, "MiB"),
                },
                "Total fdinfo": {
                    "VRAM": value(2368, "MiB"),
                    "GTT": value(56, "MiB"),
                    "GFX": value(64, "%"),
                },
                "fdinfo": processes,
            }
        ],
    }


class SnapshotTests(unittest.TestCase):
    def test_basic_fields(self):
        snapshot = backend.build_snapshot(make_frame())
        self.assertTrue(snapshot["ok"])
        self.assertEqual(snapshot["name"], "AMD Radeon RX 9070 GRE")
        self.assertEqual(snapshot["chip"], "GFX12")
        self.assertEqual(snapshot["pci"], "0000:04:00.0")
        self.assertEqual(snapshot["pcie"], "PCIe 5.0 ×16")
        self.assertEqual(snapshot["tool"], "0.11.5")
        self.assertEqual(snapshot["load"]["gfx"], 13)
        self.assertEqual(snapshot["vram"]["total"], 12224)
        self.assertEqual(snapshot["vram"]["used"], 3977)
        self.assertEqual(snapshot["temp"]["edge"], 45)
        self.assertIsNone(snapshot["temp"]["mem"])          # 传感器缺失要是 None 而不是 0
        self.assertEqual(snapshot["clk"]["max"], 2340)
        self.assertEqual(snapshot["volt"], 703)

    def test_processes_sorted_by_vram(self):
        snapshot = backend.build_snapshot(make_frame())
        pids = [item["pid"] for item in snapshot["procs"]]
        self.assertEqual(pids, [100, 200])                  # 2 GiB 排在 320 MiB 前面
        self.assertEqual(snapshot["proc_count"], 2)
        game = snapshot["procs"][0]
        self.assertEqual(game["name"], "game")
        self.assertEqual(game["vram"], 2048)
        self.assertEqual(game["gfx"], 63.5)
        self.assertEqual(game["enc"], 0)                    # null 归一成 0
        self.assertIsInstance(game["ppid"], int)            # 进程可能已退出，ppid 兜底为 0
        self.assertIsInstance(game["cmd"], str)

    def test_flat_usage_shape_is_supported(self):
        frame = make_frame({"321": {"name": "flat", "usage": {"VRAM": value(64, "MiB"), "GFX": value(5, "%")}}})
        snapshot = backend.build_snapshot(frame)
        self.assertEqual(len(snapshot["procs"]), 1)
        self.assertEqual(snapshot["procs"][0]["vram"], 64)
        self.assertEqual(snapshot["procs"][0]["gfx"], 5)

    def test_max_processes_limits_snapshot(self):
        processes = {
            str(1000 + i): {"name": "p%d" % i, "usage": {"usage": {"VRAM": value(i, "MiB")}}}
            for i in range(20)
        }
        snapshot = backend.build_snapshot(make_frame(processes), max_procs=5)
        self.assertEqual(len(snapshot["procs"]), 5)
        self.assertEqual(snapshot["proc_count"], 20)
        self.assertEqual(snapshot["procs"][0]["vram"], 19)   # 仍然按显存降序

    def test_gpu_index_is_clamped(self):
        frame = make_frame()
        frame["devices"].append({"Info": {"DeviceName": "AMD Radeon 780M"}, "Sensors": {}, "gpu_activity": {}, "VRAM": {}})
        second = backend.build_snapshot(frame, gpu_index=1)
        self.assertEqual(second["name"], "AMD Radeon 780M")
        clamped = backend.build_snapshot(frame, gpu_index=99)
        self.assertEqual(clamped["name"], "AMD Radeon 780M")
        self.assertEqual(len(clamped["gpus"]), 2)

    def test_no_devices(self):
        snapshot = backend.build_snapshot({"devices": []})
        self.assertFalse(snapshot["ok"])
        self.assertIn("AMD GPU", snapshot["error"])

    def test_missing_optional_sections(self):
        frame = {"devices": [{"Info": {"DeviceName": "AMD GPU"}}]}
        snapshot = backend.build_snapshot(frame)
        self.assertTrue(snapshot["ok"])
        self.assertEqual(snapshot["load"]["gfx"], 0)
        self.assertEqual(snapshot["vram"]["total"], 0)
        self.assertEqual(snapshot["procs"], [])
        self.assertIsNone(snapshot["temp"]["edge"])

    def test_num_helper(self):
        self.assertEqual(backend.num(value(3, "W")), 3)
        self.assertEqual(backend.num(None), 0)
        self.assertEqual(backend.num({}), 0)
        self.assertEqual(backend.num(value(True, "x")), 0)   # 布尔值不算数字
        self.assertEqual(backend.num(value(5, "W"), None), 5)

    def test_proc_meta_of_self(self):
        cmdline, ppid = backend.proc_meta(os.getpid())
        self.assertIn("python", cmdline.lower())
        self.assertGreater(ppid, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
