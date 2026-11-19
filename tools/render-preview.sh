#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 haoyn231
# SPDX-License-Identifier: MIT
#
# 采集一帧真实数据，把弹窗、面板、错误态离屏渲染成 PNG（输出到 docs/）。
# 依赖：qt6-declarative（/usr/lib/qt6/bin/qml）、amdgpu_top 在运行。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML_BIN="${QML_BIN:-/usr/lib/qt6/bin/qml}"
SNAPSHOT=/tmp/gpu-preview.json

cd "$ROOT"

LIVE="${XDG_RUNTIME_DIR:-/tmp}/kde-amdgpu-top/snapshot.json"
if [[ -f "$LIVE" ]]; then
    # 优先用守护进程写出的那份：带 60 帧历史，趋势图才是真数据
    cp "$LIVE" "$SNAPSHOT"
    echo "已复制运行中的快照：$LIVE"
else
    "$ROOT/package/contents/scripts/amdgpu-topd.py" --once > "$SNAPSHOT"
    echo "已采集单帧快照：$SNAPSHOT（没有历史曲线）"
fi

environment=(QML_XHR_ALLOW_FILE_READ=1 QT_QPA_PLATFORMTHEME=KDE QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software)

echo "渲染弹窗…"
env "${environment[@]}" timeout 60 "$QML_BIN" tools/preview.qml 2>&1 | grep -v "legacy metadata\|platform plugin\|installEventFilter" || true
cp /tmp/preview-full.png "$ROOT/docs/popup.png"

echo "渲染面板…"
env "${environment[@]}" timeout 60 "$QML_BIN" tools/preview-compact.qml 2>&1 | grep -v "legacy metadata\|platform plugin\|installEventFilter" || true
cp /tmp/preview-compact.png "$ROOT/docs/panel.png"

echo "渲染错误态…"
echo error > /tmp/gpu-preview-mode.txt
env "${environment[@]}" timeout 60 "$QML_BIN" tools/preview.qml 2>&1 | grep -v "legacy metadata\|platform plugin\|installEventFilter" || true
cp /tmp/preview-full.png "$ROOT/docs/popup-error.png"
rm -f /tmp/gpu-preview-mode.txt

echo "完成：docs/popup.png、docs/panel.png、docs/popup-error.png"
