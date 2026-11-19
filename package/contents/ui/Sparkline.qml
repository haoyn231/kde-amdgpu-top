// SPDX-FileCopyrightText: 2026 haoyn231
// SPDX-License-Identifier: MIT
//
// 迷你趋势图：把守护进程留下的 60 帧历史画成一条折线（带同色渐变填充）。
// 数据点不够两个时什么都不画，避免出现莫名其妙的竖线。

import QtQuick
import org.kde.kirigami as Kirigami

Canvas {
    id: chart

    property var values: []
    property color lineColor: Kirigami.Theme.highlightColor
    property real maximum: 100

    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()
    onMaximumChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    Connections {
        target: Kirigami.Theme
        function onTextColorChanged() { chart.requestPaint() }
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        const series = values || [];
        if (series.length < 2 || width <= 4 || height <= 4) {
            return;
        }

        const stepX = width / (series.length - 1);
        const points = [];
        for (let i = 0; i < series.length; ++i) {
            const raw = Number(series[i]) || 0;
            const clamped = Math.max(0, Math.min(maximum, raw));
            points.push({
                x: i * stepX,
                y: height - 1 - (clamped / maximum) * (height - 2)
            });
        }

        // 填充区域
        ctx.beginPath();
        ctx.moveTo(points[0].x, height);
        for (let i = 0; i < points.length; ++i) {
            ctx.lineTo(points[i].x, points[i].y);
        }
        ctx.lineTo(points[points.length - 1].x, height);
        ctx.closePath();
        ctx.fillStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.16);
        ctx.fill();

        // 折线
        ctx.beginPath();
        ctx.moveTo(points[0].x, points[0].y);
        for (let i = 1; i < points.length; ++i) {
            ctx.lineTo(points[i].x, points[i].y);
        }
        ctx.strokeStyle = lineColor;
        ctx.lineWidth = 1.6;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.stroke();
    }
}
