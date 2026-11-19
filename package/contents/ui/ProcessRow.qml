// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 进程列表的一行：名称 / PID / GPU 占用 / 显存占用，
// 点击展开完整命令行与 PPID、GTT 等附加信息。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: row

    property string name: ""
    property int pid: 0
    property string cmd: ""
    property int ppid: 0
    property real vram: 0
    property real gtt: 0
    property real gfx: 0
    property real media: 0
    property real share: 0            // 占整卡显存的百分比 0..100
    property bool expanded: false
    property color textColor: Kirigami.Theme.textColor
    property color accentColor: Kirigami.Theme.highlightColor

    signal toggled()

    readonly property real pidWidth: Math.round(Kirigami.Units.gridUnit * 2.9)
    readonly property real gfxWidth: Math.round(Kirigami.Units.gridUnit * 2.4)
    readonly property real vramWidth: Math.round(Kirigami.Units.gridUnit * 4.2)
    readonly property real dimAlpha: 0.55

    implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 1.2

    function formatMemory(mib) {
        if (!mib || mib <= 0) {
            return "0";
        }
        if (mib >= 1024) {
            return (mib / 1024).toFixed(1) + " G";
        }
        return Math.round(mib) + " M";
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing
        color: row.expanded || hover.hovered
               ? Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, row.expanded ? 0.09 : 0.05)
               : "transparent"
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Kirigami.Units.smallSpacing
        spacing: Math.round(Kirigami.Units.smallSpacing * 0.5)

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Text {
                Layout.fillWidth: true
                text: row.name
                color: row.textColor
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.64)
                elide: Text.ElideRight
            }

            Text {
                Layout.preferredWidth: row.pidWidth
                horizontalAlignment: Text.AlignRight
                text: row.pid
                color: Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, 0.42)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6)
            }

            Text {
                Layout.preferredWidth: row.gfxWidth
                horizontalAlignment: Text.AlignRight
                text: Math.round(row.gfx) + "%"
                color: row.gfx >= 1 ? row.textColor
                                    : Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, 0.4)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6)
                font.bold: row.gfx >= 1
            }

            Text {
                Layout.preferredWidth: row.vramWidth
                horizontalAlignment: Text.AlignRight
                text: row.formatMemory(row.vram)
                color: row.vram > 0 ? row.textColor
                                    : Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, 0.4)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: row.expanded
            spacing: 2

            Text {
                Layout.fillWidth: true
                text: row.cmd.length > 0 ? row.cmd : qsTr("命令行不可读（进程可能已退出）")
                color: Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, 0.72)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.56)
                font.family: "monospace"
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: "PPID " + row.ppid
                      + "   ·   GTT " + row.formatMemory(row.gtt)
                      + "   ·   " + qsTr("媒体引擎 ") + Math.round(row.media) + "%"
                      + "   ·   " + row.share.toFixed(1) + "% " + qsTr("显存")
                color: Qt.rgba(row.textColor.r, row.textColor.g, row.textColor.b, 0.45)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
                wrapMode: Text.WrapAnywhere
            }
        }

    }

    HoverHandler { id: hover }
    TapHandler { onTapped: row.toggled() }
}
