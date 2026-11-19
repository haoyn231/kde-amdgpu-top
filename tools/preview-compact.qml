// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 面板条状显示的离屏渲染：模拟一条深色面板，把紧凑表示放进去。

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami
import "../package/contents/ui"

Window {
    id: win

    property var snapshot: null

    width: 360
    height: 44
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

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor

        Row {
            anchors.centerIn: parent
            spacing: 24

            CompactRepresentation {
                width: implicitWidth
                height: implicitHeight
                gfxLoad: win.snapshot ? win.snapshot.load.gfx : 0
                vramPercent: win.snapshot && win.snapshot.vram.total > 0
                             ? win.snapshot.vram.used / win.snapshot.vram.total * 100 : 0
                vramText: win.snapshot && win.snapshot.vram.total > 0
                          ? Math.round(win.snapshot.vram.used / win.snapshot.vram.total * 100) + "%" : "—"
                ready: win.snapshot !== null && win.snapshot.ok === true
                showIcon: true
                showLoad: true
                showVram: true
                vertical: false
            }

            CompactRepresentation {
                width: implicitWidth
                height: implicitHeight
                showIcon: false
                showLoad: true
                showVram: false
                ready: true
                gfxLoad: 73
                vramPercent: 40
                vramText: "4.0 G"
            }
        }
    }

    Component.onCompleted: {
        try {
            snapshot = JSON.parse(readText("/tmp/gpu-preview.json"));
        } catch (error) {
            console.warn("读取快照失败", error);
        }
    }

    Timer {
        interval: 700
        running: true
        repeat: false
        onTriggered: {
            win.contentItem.grabToImage(function (result) {
                console.log("已保存：", "/tmp/preview-compact.png", result.saveToFile("/tmp/preview-compact.png"));
                Qt.quit();
            }, Qt.size(win.width, win.height));
        }
    }
}
