// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Kirigami.FormLayout {
    id: page

    property alias cfg_sampleInterval: intervalSpin.value
    property alias cfg_gpuIndex: gpuIndexSpin.value
    property alias cfg_maxProcesses: processSpin.value
    property alias cfg_showIcon: iconCheck.checked
    property alias cfg_showLoad: loadCheck.checked
    property alias cfg_showVram: vramCheck.checked
    property alias cfg_showLabels: labelsCheck.checked
    property alias cfg_usePerfCounters: perfCheck.checked
    property alias cfg_vramUnit: vramUnitBox.currentValue
    property alias cfg_sortKey: sortKeyBox.currentValue

    PlasmaComponents3.SpinBox {
        id: intervalSpin
        Kirigami.FormData.label: i18n("刷新间隔：")
        from: 1
        to: 10
        stepSize: 1
        editable: true
    }

    PlasmaComponents3.Label {
        Kirigami.FormData.isSection: false
        text: i18n("采样间隔越长越省电；amdgpu_top 自身固定每秒出帧，这里控制写入与刷新频率。")
        font: Kirigami.Theme.smallFont
        opacity: 0.65
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("面板显示")
    }

    PlasmaComponents3.CheckBox {
        id: iconCheck
        text: i18n("显示 GPU 图标")
    }

    PlasmaComponents3.CheckBox {
        id: loadCheck
        text: i18n("显示负载百分比")
    }

    PlasmaComponents3.CheckBox {
        id: vramCheck
        text: i18n("显示显存占用")
    }

    PlasmaComponents3.CheckBox {
        id: labelsCheck
        text: i18n("显示 GPU / VRAM 文字标签")
    }

    PlasmaComponents3.ComboBox {
        id: vramUnitBox
        Kirigami.FormData.label: i18n("显存显示为：")
        enabled: vramCheck.checked
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("百分比"), value: "percent" },
            { text: i18n("实际容量"), value: "absolute" }
        ]
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("进程列表")
    }

    PlasmaComponents3.SpinBox {
        id: processSpin
        Kirigami.FormData.label: i18n("最多显示：")
        from: 3
        to: 40
        stepSize: 1
        editable: true
    }

    PlasmaComponents3.ComboBox {
        id: sortKeyBox
        Kirigami.FormData.label: i18n("默认排序：")
        textRole: "text"
        valueRole: "value"
        model: [
            { text: i18n("显存占用"), value: "vram" },
            { text: i18n("GPU 占用"), value: "gfx" },
            { text: i18n("进程名"), value: "name" }
        ]
    }

    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: i18n("高级")
    }

    PlasmaComponents3.SpinBox {
        id: gpuIndexSpin
        Kirigami.FormData.label: i18n("GPU 序号：")
        from: 0
        to: 7
        stepSize: 1
        editable: true
    }

    PlasmaComponents3.Label {
        text: i18n("机器上有多个 AMD GPU 时，用序号选择要监视的那一块（0 表示第一块）。")
        font: Kirigami.Theme.smallFont
        opacity: 0.65
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
    }

    PlasmaComponents3.CheckBox {
        id: perfCheck
        text: i18n("读取性能计数器（GRBM）")
    }

    PlasmaComponents3.Label {
        text: i18n("读取性能计数器可能让显卡无法进入深度省电状态，默认关闭；关闭后仍会显示 GFX 占用。")
        font: Kirigami.Theme.smallFont
        opacity: 0.65
        Layout.maximumWidth: Kirigami.Units.gridUnit * 22
        wrapMode: Text.WordWrap
    }
}
