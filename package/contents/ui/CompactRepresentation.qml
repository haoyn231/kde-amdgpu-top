// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 面板上的紧凑显示：图标 + GPU 负载 + 显存占用。
//
// 两个坑（kde-perfmon 里也踩过）：
//   1. 面板是按 Layout 附加属性给 applet 分格子的。只写 implicitWidth/implicitHeight
//      时，Plasma 会退回"一个图标大小"的槽位，内容就溢出到旁边的时钟/托盘上。
//   2. 不要用铺满整块的 MouseArea 接管点击：那会吞掉按下事件，编辑模式下就拖不动。
//      改用 TapHandler（默认 DragThreshold 策略），点击生效、拖动仍然交给面板。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
    id: compact

    // 点具体指标时告诉外面"按哪一列打开进程列表"
    signal activated(string sortKey)

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
    readonly property int iconSize: Kirigami.Units.iconSizes.small

    implicitWidth: metrics.implicitWidth + Kirigami.Units.smallSpacing * 2
    implicitHeight: vertical
        ? metrics.implicitHeight + Kirigami.Units.smallSpacing
        : Math.max(iconSize, metrics.implicitHeight) + Math.round(Kirigami.Units.smallSpacing * 0.6)

    // 面板布局用的就是这几个附加属性，缺了就会退回图标大小的槽位
    Layout.preferredWidth: implicitWidth
    Layout.minimumWidth: implicitWidth
    Layout.maximumWidth: implicitWidth
    Layout.preferredHeight: implicitHeight
    Layout.minimumHeight: implicitHeight
    Layout.maximumHeight: implicitHeight

    Accessible.name: ready
        ? qsTr("GPU %1%，显存 %2").arg(Math.round(gfxLoad)).arg(vramText)
        : qsTr("AMD GPU 监视器")
    Accessible.role: Accessible.Button

    GridLayout {
        id: metrics
        anchors.centerIn: parent
        columns: compact.vertical ? 1 : Math.max(1, compact.groups)
        columnSpacing: Math.round(Kirigami.Units.smallSpacing * 1.2)
        rowSpacing: Math.round(Kirigami.Units.smallSpacing * 0.4)

        // 图标和 GPU 数字算一组：点哪儿都能按 GPU 排序打开
        Metric {
            visible: compact.showIcon || compact.showLoad
            iconSource: compact.showIcon ? "computer-symbolic" : ""
            label: compact.showLoad ? "GPU" : ""
            valueText: compact.ready ? Math.round(compact.gfxLoad) + "%" : "—"
            valueColor: compact.ready ? compact.loadColor : compact.dimColor
            sortKey: "gfx"
        }

        Metric {
            visible: compact.showVram
            label: "VRAM"
            valueText: compact.ready ? compact.vramText : "—"
            valueColor: compact.ready ? compact.vramColor : compact.dimColor
            sortKey: "vram"
        }
    }

    // 横向时按"组"分列（图标+GPU 是一组，显存是一组）；竖向时一行一组
    readonly property int groups: {
        let count = 0;
        if (showIcon || showLoad) {
            ++count;
        }
        if (showVram) {
            ++count;
        }
        return count;
    }

    component Metric: RowLayout {
        id: metric

        property string iconSource: ""
        property string label: ""
        property string valueText
        property color valueColor: compact.textColor
        property string sortKey: "gfx"

        spacing: Math.round(Kirigami.Units.smallSpacing * 0.9)
        Layout.alignment: Qt.AlignVCenter

        Kirigami.Icon {
            visible: metric.iconSource !== ""
            source: metric.iconSource
            implicitWidth: compact.iconSize
            implicitHeight: compact.iconSize
            Layout.preferredWidth: implicitWidth
            Layout.preferredHeight: implicitHeight
            Layout.alignment: Qt.AlignVCenter
            opacity: compact.ready ? 1 : 0.5
        }

        Text {
            visible: compact.showLabels && metric.label !== ""
            text: metric.label
            font: Kirigami.Theme.smallFont
            color: compact.dimColor
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: metric.valueText
            color: metric.valueColor
            font.features: ({ "tnum": 1 })      // 等宽数字，刷新时不左右跳
            Layout.alignment: Qt.AlignVCenter
        }

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        // TapHandler 而不是 MouseArea：点击可以生效，拖动仍然交给面板
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: compact.activated(metric.sortKey)
        }
    }
}
