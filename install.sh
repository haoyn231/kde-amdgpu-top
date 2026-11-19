#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 haoyn231
# SPDX-License-Identifier: MIT
#
# 把小程序装到当前用户的 Plasma 目录（不需要 root）。
#   ./install.sh            安装 / 升级
#   ./install.sh --restart  安装后顺手重启 plasmashell
#   ./install.sh --symlink  用软链接安装，改代码即时生效（方便开发）

set -euo pipefail

PLUGIN_ID="org.hao.amdgputop"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_DIR="$SRC_DIR/package"
TARGET_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids"
TARGET_DIR="$TARGET_ROOT/$PLUGIN_ID"
RESTART=0
SYMLINK=0

for arg in "$@"; do
    case "$arg" in
        --restart) RESTART=1 ;;
        --symlink) SYMLINK=1 ;;
        -h|--help)
            sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "未知参数：$arg" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$PKG_DIR/metadata.json" ]]; then
    echo "找不到 $PKG_DIR/metadata.json，请在仓库根目录运行。" >&2
    exit 1
fi

if ! command -v plasmashell >/dev/null 2>&1; then
    echo "警告：没找到 plasmashell，确认这是 KDE Plasma 6 环境。" >&2
fi

if ! command -v amdgpu_top >/dev/null 2>&1; then
    echo "警告：没找到 amdgpu_top，小组件会显示「未找到 amdgpu_top」。"
    echo "      Arch: sudo pacman -S amdgpu_top"
fi

mkdir -p "$TARGET_ROOT"

if [[ $SYMLINK -eq 1 ]]; then
    rm -rf "$TARGET_DIR"
    ln -s "$PKG_DIR" "$TARGET_DIR"
    echo "已用软链接安装：$TARGET_DIR -> $PKG_DIR"
else
    if command -v kpackagetool6 >/dev/null 2>&1; then
        # 已经装过就走 --upgrade，否则先 --install
        if kpackagetool6 --type Plasma/Applet --upgrade "$PKG_DIR" >/dev/null 2>&1; then
            echo "已通过 kpackagetool6 升级：$PLUGIN_ID"
        elif kpackagetool6 --type Plasma/Applet --install "$PKG_DIR" >/dev/null 2>&1; then
            echo "已通过 kpackagetool6 安装：$PLUGIN_ID"
        else
            echo "kpackagetool6 失败，退回直接复制。" >&2
            rm -rf "$TARGET_DIR"
            cp -r "$PKG_DIR" "$TARGET_DIR"
            echo "已复制到：$TARGET_DIR"
        fi
    else
        rm -rf "$TARGET_DIR"
        cp -r "$PKG_DIR" "$TARGET_DIR"
        echo "已复制到：$TARGET_DIR"
    fi
fi

chmod +x "$TARGET_DIR/contents/scripts/amdgpu-topd.py" 2>/dev/null || true

# 清掉旧的采集进程，让新版本参数生效
"$TARGET_DIR/contents/scripts/amdgpu-topd.py" --stop >/dev/null 2>&1 || true

cat <<EOF

安装完成。接下来：
  1. 右键面板 → 进入编辑模式 → 添加小组件
  2. 搜索「AMD GPU 监视器」，拖到面板上

采集进程会随小组件自动拉起，日志在 ~/.cache/kde-amdgpu-top/daemon.log
排查状态：$TARGET_DIR/contents/scripts/amdgpu-topd.py --status
EOF

if [[ $RESTART -eq 1 ]]; then
    echo
    echo "正在重启 plasmashell…"
    systemctl --user restart plasma-plasmashell.service
fi
