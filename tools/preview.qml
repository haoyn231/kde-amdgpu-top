// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 离屏渲染工具：不启动 plasmashell，直接把真实的弹窗 QML 渲染成 PNG，
// 方便在没有面板的环境里检查排版、配色与数据绑定。
//
// 路径固定为 /tmp，由 tools/render-preview.sh 准备：
//   /tmp/gpu-preview.json        快照数据（可以直接 cp 守护进程写出的那份）
//   /tmp/gpu-preview-mode.txt    内容为 error 时渲染错误态
//   /tmp/preview-full.png        输出

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import "../package/contents/ui"

Window {
    id: win

    readonly property string sourcePath: "/tmp/gpu-preview.json"
    readonly property string outputPath: "/tmp/preview-full.png"

    property var snapshot: null
    property bool errorMode: false

    width: Kirigami.Units.gridUnit * 25
    height: Kirigami.Units.gridUnit * 30
    visible: true
    color: Kirigami.Theme.backgroundColor

    function readText(path) {
        try {
            const xhr = new XMLHttpRequest();
            xhr.open("GET", "file://" + path, false);
            xhr.send(null);
            return xhr.responseText || "";
        } catch (error) {
            return "";
        }
    }

    function load() {
        errorMode = readText("/tmp/gpu-preview-mode.txt").trim() === "error";
        if (errorMode) {
            snapshot = {
                ok: false,
                ts: Date.now() / 1000,
                error: "未找到 amdgpu_top",
                hint: "安装：sudo pacman -S amdgpu_top",
                gpus: []
            };
            return;
        }
        const text = readText(sourcePath);
        try {
            snapshot = JSON.parse(text);
            console.log("预览数据：", snapshot.name, "负载", snapshot.load.gfx,
                        "进程", snapshot.procs.length,
                        "历史", snapshot.hist ? snapshot.hist.gfx.length : 0);
        } catch (error) {
            console.warn("读取快照失败：", error, text.slice(0, 120));
            snapshot = { ok: false, ts: Date.now() / 1000, error: "快照读取失败", hint: sourcePath };
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
    }

    FullRepresentation {
        anchors.fill: parent
        snap: win.snapshot
        maxProcs: 12
        preferredSort: "vram"
        active: true
    }

    Component.onCompleted: load()

    Timer {
        interval: 900
        running: true
        repeat: false
        onTriggered: {
            win.contentItem.grabToImage(function (result) {
                console.log("已保存：", win.outputPath, result.saveToFile(win.outputPath));
                Qt.quit();
            }, Qt.size(win.width, win.height));
        }
    }
}
