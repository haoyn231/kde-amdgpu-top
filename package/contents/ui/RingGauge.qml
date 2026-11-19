// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 圆形负载表：画一圈底环 + 一段按百分比扫出的弧。
// 用 Canvas 而不是 Shape，是为了少一层图层、并且能随手做圆头端点。

import QtQuick
import org.kde.kirigami as Kirigami

Canvas {
    id: gauge

    property real value: 0
    property color color: Kirigami.Theme.highlightColor
    property color trackColor: Qt.rgba(Kirigami.Theme.textColor.r,
                                       Kirigami.Theme.textColor.g,
                                       Kirigami.Theme.textColor.b, 0.16)
    property real thickness: Math.max(3, Math.round(Math.min(width, height) * 0.09))

    onValueChanged: requestPaint()
    onColorChanged: requestPaint()
    onTrackColorChanged: requestPaint()
    onThicknessChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
        target: Kirigami.Theme
        function onTextColorChanged() { gauge.requestPaint() }
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        const cx = width / 2;
        const cy = height / 2;
        const radius = Math.min(width, height) / 2 - thickness / 2;
        if (radius <= 0) {
            return;
        }

        ctx.lineCap = "round";
        ctx.lineWidth = thickness;

        ctx.strokeStyle = trackColor;
        ctx.beginPath();
        ctx.arc(cx, cy, radius, 0, Math.PI * 2);
        ctx.stroke();

        const fraction = Math.max(0, Math.min(1, value / 100));
        if (fraction > 0.002) {
            ctx.strokeStyle = color;
            ctx.beginPath();
            ctx.arc(cx, cy, radius, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * fraction);
            ctx.stroke();
        }
    }
}
