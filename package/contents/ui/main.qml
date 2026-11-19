// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// AMD GPU 监视器 —— 主入口。
//
// 数据通路：
//   守护进程(amdgpu-topd.py) --常驻--> amdgpu_top -J
//        └─ 每秒原子写入 snapshot.json
//   QML --executable 数据引擎--> `cat snapshot.json` --> 解析 --> 面板 / 弹窗
//
// Plasma 的 executable 引擎会缓冲子进程输出直到进程结束，所以这里让它每秒
// 跑一个 `cat`：进程极短命，输出即完整一帧，天然没有"读半截"的问题。

import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.DefaultBackground

    // ---------------------------------------------------------------- 后端通道
    readonly property string scriptPath: {
        const url = String(Qt.resolvedUrl("../scripts/amdgpu-topd.py"));
        return url.replace(/^file:\/\//, "");
    }
    readonly property int sampleInterval: Math.max(1, Number(plasmoid.configuration.sampleInterval) || 1)
    readonly property string ensureCommand: "python3 " + root.quote(root.scriptPath)
        + " --ensure"
        + " --interval " + root.sampleInterval
        + " --gpu-index " + (Number(plasmoid.configuration.gpuIndex) || 0)
        + (plasmoid.configuration.usePerfCounters ? " --pc" : "")
    // 比采样快一点读，肉眼不易察觉到延迟；重复的快照会被时间戳过滤掉
    readonly property int pollInterval: Math.max(400, Math.round(root.sampleInterval * 500))

    property string snapshotPath: ""
    property var snapshot: null
    property bool stalled: false

    readonly property bool ready: snapshot !== null && snapshot.ok === true
    readonly property real gfxLoad: ready ? snapshot.load.gfx : 0
    readonly property real vramPercent: ready && snapshot.vram.total > 0
                                       ? snapshot.vram.used / snapshot.vram.total * 100 : 0
    readonly property string vramShort: ready
                                       ? (snapshot.vram.used / 1024).toFixed(1) + " G"
                                       : "—"

    function quote(value) {
        return "'" + String(value).replace(/'/g, "'\\''") + "'";
    }

    function consume(payload) {
        if (!payload) {
            return;
        }
        let parsed = null;
        try {
            parsed = JSON.parse(payload);
        } catch (error) {
            return;
        }
        if (parsed === null || typeof parsed !== "object") {
            return;
        }
        if (root.snapshot !== null && parsed.ts === root.snapshot.ts) {
            return;                       // 同一帧，别白白刷新一遍界面
        }
        root.snapshot = parsed;
        root.stalled = false;
    }

    function kickLauncher() {
        launcher.connectedSources = [];
        relaunch.restart();
    }

    // 启动采集进程（幂等），顺带每 15 秒当一次保活；
    // stdout 就是快照文件路径，拿到后 reader 才真正开始读。
    P5Support.DataSource {
        id: launcher
        engine: "executable"
        interval: 15000
        connectedSources: [root.ensureCommand]
        onNewData: (source, data) => {
            if (data["exit code"] !== 0) {
                console.warn("amdgpu-topd ensure 失败：", data.stderr);
                return;
            }
            const lines = String(data.stdout).trim().split("\n");
            const path = lines[lines.length - 1];
            if (path && path.charAt(0) === "/" && path !== root.snapshotPath) {
                root.snapshotPath = path;
            }
        }
    }

    P5Support.DataSource {
        id: reader
        engine: "executable"
        interval: root.pollInterval
        connectedSources: root.snapshotPath !== "" ? ["cat " + root.quote(root.snapshotPath)] : []
        onNewData: (source, data) => {
            if (data["exit code"] !== 0) {
                root.stalled = true;
                return;
            }
            root.consume(data.stdout);
        }
    }

    Timer {
        id: relaunch
        interval: 60
        repeat: false
        onTriggered: launcher.connectedSources = [root.ensureCommand]
    }

    // 卡住时的兜底：重新 ensure 一次（守护进程可能已经死掉）
    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (root.snapshotPath === "") {
                return;                   // launcher 自己会重试
            }
            const age = root.snapshot !== null ? Date.now() / 1000 - root.snapshot.ts : 999;
            root.stalled = age > Math.max(6, root.sampleInterval * 3);
            if (root.stalled) {
                root.kickLauncher();
            }
        }
    }

    // 首次启动如果 4 秒还没拿到路径，主动催一次
    Timer {
        interval: 4000
        repeat: false
        running: true
        onTriggered: {
            if (root.snapshotPath === "") {
                root.kickLauncher();
            }
        }
    }

    // 一直没有数据就不要再显示"正在启动"了，给一句能照着做的提示
    Timer {
        interval: 12000
        repeat: false
        running: true
        onTriggered: {
            if (root.snapshot === null) {
                root.snapshot = {
                    ok: false,
                    ts: Date.now() / 1000,
                    error: qsTr("采集进程没有响应"),
                    hint: qsTr("用以下命令排障：python3 ") + root.scriptPath + " --status"
                };
            }
        }
    }

    // ---------------------------------------------------------------- 提示气泡
    toolTipMainText: root.ready ? root.snapshot.name : i18n("AMD GPU 监视器")
    toolTipSubText: {
        if (!root.ready) {
            return root.snapshot !== null && root.snapshot.error
                   ? root.snapshot.error : i18n("正在读取 amdgpu_top 数据…");
        }
        const gpu = i18n("负载 %1%", Math.round(root.snapshot.load.gfx));
        const mem = i18n("显存 %1 / %2 GiB",
                         (root.snapshot.vram.used / 1024).toFixed(1),
                         (root.snapshot.vram.total / 1024).toFixed(1));
        const lines = [gpu + "   ·   " + mem];
        const extra = [];
        if (root.snapshot.temp.edge !== null && root.snapshot.temp.edge !== undefined) {
            extra.push(Math.round(root.snapshot.temp.edge) + " °C");
        }
        if (root.snapshot.power.avg !== null && root.snapshot.power.avg !== undefined) {
            extra.push(Math.round(root.snapshot.power.avg) + " W");
        }
        if (root.snapshot.clk.sclk !== null && root.snapshot.clk.sclk !== undefined) {
            extra.push(Math.round(root.snapshot.clk.sclk) + " MHz");
        }
        if (extra.length > 0) {
            lines.push(extra.join("   ·   "));
        }
        if (root.snapshot.tool) {
            lines.push("amdgpu_top " + root.snapshot.tool);
        }
        return lines.join("\n");
    }

    // ---------------------------------------------------------------- 表示层
    compactRepresentation: CompactRepresentation {
        gfxLoad: root.gfxLoad
        vramPercent: root.vramPercent
        vramText: plasmoid.configuration.vramUnit === "absolute"
                  ? root.vramShort
                  : (root.ready ? Math.round(root.vramPercent) + "%" : "—")
        ready: root.ready
        showIcon: plasmoid.configuration.showIcon
        showLoad: plasmoid.configuration.showLoad
        showVram: plasmoid.configuration.showVram
        showLabels: plasmoid.configuration.showLabels
        vertical: plasmoid.formFactor === PlasmaCore.Types.Vertical
    }

    fullRepresentation: FullRepresentation {
        snap: root.snapshot
        maxProcs: plasmoid.configuration.maxProcesses
        preferredSort: plasmoid.configuration.sortKey
        active: plasmoid.expanded
    }
}
