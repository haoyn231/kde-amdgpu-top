#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 haoyn231
# SPDX-License-Identifier: MIT
#
# 卸载小组件：删掉 Plasma 包，停掉采集进程，清掉运行时文件。
# 不会动 Plasma 的配置（面板里残留的 applet 条目需要你自己移除）。

set -euo pipefail

PLUGIN_ID="org.hao.amdgputop"
TARGET_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids"
TARGET_DIR="$TARGET_ROOT/$PLUGIN_ID"
SCRIPT="$TARGET_DIR/contents/scripts/amdgpu-topd.py"

if [[ -x "$SCRIPT" ]]; then
    "$SCRIPT" --stop >/dev/null 2>&1 || true
fi

if command -v kpackagetool6 >/dev/null 2>&1; then
    kpackagetool6 --type Plasma/Applet --remove "$PLUGIN_ID" >/dev/null 2>&1 || true
fi
rm -rf "$TARGET_DIR"

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/kde-amdgpu-top"
rm -rf "$RUNTIME_DIR"
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/kde-amdgpu-top"

echo "已卸载 $PLUGIN_ID。"
echo "如果面板上还留着空位，右键面板 → 编辑模式 → 移除即可。"
