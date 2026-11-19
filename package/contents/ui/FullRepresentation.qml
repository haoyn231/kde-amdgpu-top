// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 弹窗内容：GPU 概要 → 显存条 → 负载趋势 → 传感器小块 → 进程占用。
// 所有颜色都来自 Kirigami.Theme，明暗主题切换即时生效。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.Representation {
    id: page

    property var snap: null
    property int maxProcs: 12
    property string preferredSort: "vram"
    property bool active: true

    readonly property bool ready: snap !== null && snap.ok === true
    readonly property color textColor: Kirigami.Theme.textColor
    readonly property color accentColor: Kirigami.Theme.highlightColor
    readonly property color dimColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.6)
    readonly property color faintColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.4)
    readonly property color hairline: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)

    readonly property var load: ready ? snap.load : ({ gfx: 0, mem: 0, media: 0 })
    readonly property var vram: ready ? snap.vram : ({ used: 0, total: 0, gtt_used: 0, gtt_total: 0 })
    readonly property var temp: ready ? snap.temp : ({ edge: null, junction: null, mem: null })
    readonly property var power: ready ? snap.power : ({ avg: null, gfx: null })
    readonly property var fan: ready ? snap.fan : ({ rpm: null, max: null })
    readonly property var clk: ready ? snap.clk : ({ sclk: null, mclk: null, max: null })
    readonly property var history: ready && snap.hist ? snap.hist.gfx : []
    readonly property int historySeconds: Math.round(page.history.length * (ready && snap.interval ? snap.interval : 1))

    readonly property real vramFraction: vram.total > 0 ? vram.used / vram.total : 0
    readonly property color loadColor: load.gfx >= 90 ? Kirigami.Theme.negativeTextColor
                                     : (load.gfx >= 70 ? Kirigami.Theme.neutralTextColor : accentColor)
    readonly property color vramColor: vramFraction >= 0.9 ? Kirigami.Theme.negativeTextColor
                                     : (vramFraction >= 0.75 ? Kirigami.Theme.neutralTextColor : accentColor)
    readonly property color tempColor: temp.edge === null || temp.edge === undefined ? dimColor
                                     : (temp.edge >= 85 ? Kirigami.Theme.negativeTextColor
                                        : (temp.edge >= 70 ? Kirigami.Theme.neutralTextColor : textColor))

    function fixed(value, digits) {
        if (value === null || value === undefined || isNaN(value)) {
            return "—";
        }
        return digits > 0 ? Number(value).toFixed(digits) : String(Math.round(value));
    }

    function gib(mib) {
        return (mib / 1024).toFixed(1) + " G";
    }

    function metaLine() {
        if (!ready) {
            if (snap === null) {
                return qsTr("正在启动采集进程…");
            }
            return snap.error ? qsTr("采集不可用") : qsTr("正在读取 amdgpu_top 数据…");
        }
        const parts = [];
        if (snap.chip) {
            parts.push(snap.chip);
        }
        if (snap.type) {
            parts.push(snap.type);
        }
        if (snap.pcie) {
            parts.push(snap.pcie);
        }
        return parts.join("  ·  ");
    }

    Layout.minimumWidth: Kirigami.Units.gridUnit * 21
    Layout.preferredWidth: Kirigami.Units.gridUnit * 25
    Layout.maximumWidth: Kirigami.Units.gridUnit * 34
    Layout.minimumHeight: Kirigami.Units.gridUnit * 22
    Layout.preferredHeight: Kirigami.Units.gridUnit * 30

    contentItem: Item {
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(Kirigami.Units.gridUnit * 0.85)
            spacing: Kirigami.Units.largeSpacing

            // ---------------- 头部：负载环 + 型号 + 温度 ----------------
            RowLayout {
                Layout.fillWidth: true
                spacing: Math.round(Kirigami.Units.gridUnit * 0.7)

                Item {
                    Layout.preferredWidth: Math.round(Kirigami.Units.gridUnit * 2.6)
                    Layout.preferredHeight: Layout.preferredWidth

                    RingGauge {
                        anchors.fill: parent
                        value: page.load.gfx
                        color: page.loadColor
                        opacity: page.ready ? 1 : 0.35
                    }

                    Text {
                        anchors.centerIn: parent
                        text: page.ready ? Math.round(page.load.gfx) + "%" : "—"
                        color: page.textColor
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.62)
                        font.bold: true
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        Layout.fillWidth: true
                        text: page.ready ? page.snap.name : qsTr("AMD GPU")
                        color: page.textColor
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.86)
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: page.metaLine()
                        color: page.dimColor
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.58)
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    visible: page.ready
                    implicitWidth: tempLabel.implicitWidth + Kirigami.Units.smallSpacing * 3
                    implicitHeight: Kirigami.Units.gridUnit * 1.6
                    radius: height / 2
                    color: Qt.rgba(page.tempColor.r, page.tempColor.g, page.tempColor.b, 0.14)
                    border.width: 1
                    border.color: Qt.rgba(page.tempColor.r, page.tempColor.g, page.tempColor.b, 0.3)

                    Text {
                        id: tempLabel
                        anchors.centerIn: parent
                        text: page.fixed(page.temp.edge, 0) + " °C"
                        color: page.tempColor
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.62)
                        font.bold: true
                    }
                }
            }

            // ---------------- 显存条 ----------------
            MeterBar {
                visible: page.ready
                title: qsTr("显存")
                value: page.gib(page.vram.used) + " / " + page.gib(page.vram.total)
                caption: Math.round(page.vramFraction * 100) + "%"
                fraction: page.vramFraction
                barColor: page.vramColor
                textColor: page.textColor
            }

            // ---------------- 负载趋势 ----------------
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                // 数据不足两个点时画不出曲线，索性整块藏掉
                visible: page.ready && page.history.length > 1

                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: qsTr("GPU 负载")
                        color: page.faintColor
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: qsTr("最近 %1 秒").arg(page.historySeconds)
                        color: page.faintColor
                        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.54)
                    }
                }

                Sparkline {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(Kirigami.Units.gridUnit * 1.7)
                    values: page.history
                    lineColor: page.loadColor
                }
            }

            // ---------------- 传感器小块 ----------------
            GridLayout {
                Layout.fillWidth: true
                visible: page.ready
                columns: 4
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: Kirigami.Units.smallSpacing

                StatTile {
                    title: qsTr("功耗")
                    value: page.fixed(page.power.avg, 0)
                    unit: "W"
                    textColor: page.textColor
                }
                StatTile {
                    title: qsTr("结温")
                    value: page.fixed(page.temp.junction, 0)
                    unit: "°C"
                    textColor: page.textColor
                }
                StatTile {
                    title: qsTr("显存温度")
                    value: page.fixed(page.temp.mem, 0)
                    unit: "°C"
                    textColor: page.textColor
                }
                StatTile {
                    title: qsTr("风扇")
                    value: page.fixed(page.fan.rpm, 0)
                    unit: "RPM"
                    textColor: page.textColor
                }
                StatTile {
                    title: qsTr("核心频率")
                    value: page.fixed(page.clk.sclk, 0)
                    unit: "MHz"
                    textColor: page.textColor
                }
                StatTile {
                    title: qsTr("显存频率")
                    value: page.fixed(page.clk.mclk, 0)
                    unit: "MHz"
                    textColor: page.textColor
                }
                StatTile {
                    title: qsTr("电压")
                    value: page.fixed(page.snap ? page.snap.volt : null, 0)
                    unit: "mV"
                    textColor: page.textColor
                }
                StatTile {
                    title: "GTT"
                    value: page.fixed(page.vram.gtt_used, 0)
                    unit: "MiB"
                    textColor: page.textColor
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                visible: page.ready
                color: page.hairline
            }

            // ---------------- 进程 ----------------
            ProcessList {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: page.ready
                snap: page.snap
                maxProcs: page.maxProcs
                preferredSort: page.preferredSort
                active: page.active
            }

            // ---------------- 错误 / 等待状态 ----------------
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !page.ready
                spacing: Kirigami.Units.smallSpacing

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: page.snap === null ? qsTr("正在启动采集进程…") : (page.snap.error || qsTr("未知错误"))
                    color: page.textColor
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.75)
                    font.bold: true
                    wrapMode: Text.WordWrap
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: page.snap !== null && !!page.snap.hint
                    text: page.snap !== null ? (page.snap.hint || "") : ""
                    color: page.dimColor
                    font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.6)
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
