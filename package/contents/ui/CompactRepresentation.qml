// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 面板上的紧凑显示：图标 + GPU 负载 + 显存占用。
// 数字用等宽数字（tabular figures），避免每秒刷新时整行左右跳动。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: rep

    property real gfxLoad: 0
    property real vramPercent: 0
    property string vramText: ""
    property bool ready: false
    property bool showIcon: true
    property bool showLoad: true
    property bool showVram: true
    property bool showLabels: true
    property bool vertical: false

    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color dimColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
    readonly property color loadColor: gfxLoad >= 90 ? Kirigami.Theme.negativeTextColor
                                     : (gfxLoad >= 70 ? Kirigami.Theme.neutralTextColor : textColor)
    readonly property color vramColor: vramPercent >= 90 ? Kirigami.Theme.negativeTextColor
                                     : (vramPercent >= 75 ? Kirigami.Theme.neutralTextColor : textColor)

    implicitWidth: content.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: content.implicitHeight + Math.round(Kirigami.Units.smallSpacing * 0.6)

    GridLayout {
        id: content
        anchors.centerIn: parent
        columns: rep.vertical ? 1 : 32
        columnSpacing: Math.round(Kirigami.Units.smallSpacing * 1.6)
        rowSpacing: Math.round(Kirigami.Units.smallSpacing * 0.4)

        Kirigami.Icon {
            visible: rep.showIcon
            source: "computer-symbolic"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: implicitWidth
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.alignment: Qt.AlignVCenter
            opacity: rep.ready ? 1 : 0.5
        }

        RowLayout {
            visible: rep.showLoad
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.9)
            Layout.alignment: Qt.AlignVCenter

            Text {
                text: "GPU"
                visible: rep.showLabels
                font: Kirigami.Theme.smallFont
                color: rep.dimColor
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: rep.ready ? Math.round(rep.gfxLoad) + "%" : "—"
                color: rep.ready ? rep.loadColor : rep.dimColor
                font.features: ({ "tnum": 1 })
                Layout.alignment: Qt.AlignVCenter
            }
        }

        RowLayout {
            visible: rep.showVram
            spacing: Math.round(Kirigami.Units.smallSpacing * 0.9)
            Layout.alignment: Qt.AlignVCenter

            Text {
                text: "VRAM"
                visible: rep.showLabels
                font: Kirigami.Theme.smallFont
                color: rep.dimColor
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: rep.ready ? rep.vramText : "—"
                color: rep.ready ? rep.vramColor : rep.dimColor
                font.features: ({ "tnum": 1 })
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        onClicked: plasmoid.expanded = !plasmoid.expanded
    }
}
