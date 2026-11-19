// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 一行「标题 + 数值 + 进度条」，用于显存占用这类需要看比例的指标。

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: meter

    property string title
    property string value
    property string caption: ""
    property real fraction: 0          // 0..1
    property color barColor: Kirigami.Theme.highlightColor
    property color textColor: Kirigami.Theme.textColor

    spacing: Kirigami.Units.smallSpacing
    Layout.fillWidth: true

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        Text {
            text: meter.title
            color: Qt.rgba(meter.textColor.r, meter.textColor.g, meter.textColor.b, 0.62)
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.62)
        }

        Item { Layout.fillWidth: true }

        Text {
            text: meter.caption
            visible: text.length > 0
            color: Qt.rgba(meter.textColor.r, meter.textColor.g, meter.textColor.b, 0.45)
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.62)
        }

        Text {
            text: meter.value
            color: meter.textColor
            font.pixelSize: Math.round(Kirigami.Units.gridUnit * 0.62)
            font.bold: true
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(4, Math.round(Kirigami.Units.gridUnit * 0.28))

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Qt.rgba(meter.textColor.r, meter.textColor.g, meter.textColor.b, 0.14)
        }

        Rectangle {
            height: parent.height
            radius: height / 2
            width: Math.max(parent.height, Math.min(1, Math.max(0, meter.fraction)) * parent.width)
            visible: meter.fraction > 0.001
            color: meter.barColor

            Behavior on width {
                NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic }
            }
        }
    }
}
