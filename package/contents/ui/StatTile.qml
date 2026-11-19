// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 小数据块：标题在上、数值在下，背景是一层极淡的主题色。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Rectangle {
    id: tile

    property string title
    property string value: "—"
    property string unit: ""
    property color textColor: Kirigami.Theme.textColor

    Layout.fillWidth: true
    implicitHeight: body.implicitHeight + Kirigami.Units.smallSpacing * 2
    radius: Kirigami.Units.smallSpacing
    color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.055)
    border.width: 1
    border.color: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.06)

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing * 1.4
        spacing: 0

        Text {
            text: tile.title
            color: Qt.rgba(tile.textColor.r, tile.textColor.g, tile.textColor.b, 0.5)
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.56)
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            Text {
                text: tile.value
                color: tile.textColor
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.78)
                font.bold: true
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: tile.unit
                visible: text.length > 0
                color: Qt.rgba(tile.textColor.r, tile.textColor.g, tile.textColor.b, 0.45)
                font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.52)
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: Math.round(Kirigami.Units.gridUnit * 0.1)
            }
        }
    }
}
