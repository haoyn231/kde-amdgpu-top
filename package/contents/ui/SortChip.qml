// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 排序小按钮：当前排序列高亮，并在文字后面显示升/降序箭头。

import QtQuick
import org.kde.kirigami as Kirigami

Rectangle {
    id: chip

    property string text
    property bool active: false
    property bool descending: true
    property color textColor: Kirigami.Theme.textColor
    property color accentColor: Kirigami.Theme.highlightColor

    signal clicked()

    implicitWidth: caption.implicitWidth + Kirigami.Units.smallSpacing * 3
    implicitHeight: Kirigami.Units.gridUnit * 1.45
    radius: height / 2
    color: active
           ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, hover.hovered ? 0.34 : 0.24)
           : Qt.rgba(textColor.r, textColor.g, textColor.b, hover.hovered ? 0.13 : 0.07)
    border.width: 1
    border.color: active
                  ? Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.5)
                  : "transparent"

    Behavior on color {
        ColorAnimation { duration: Kirigami.Units.shortDuration }
    }

    Text {
        id: caption
        anchors.centerIn: parent
        text: chip.text + (chip.active ? (chip.descending ? "  ↓" : "  ↑") : "")
        color: chip.active ? chip.accentColor : Qt.rgba(chip.textColor.r, chip.textColor.g, chip.textColor.b, 0.66)
        font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.58)
        font.bold: chip.active
    }

    HoverHandler { id: hover }
    TapHandler { onTapped: chip.clicked() }
}
