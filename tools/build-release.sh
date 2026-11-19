#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 haoyn231
# SPDX-License-Identifier: MIT
#
# 在本地打包 Release 资产（没有 CI，发布前手动跑一次）：
#   dist/kde-amdgpu-top-vX.Y.Z.tar.gz
#   dist/kde-amdgpu-top-vX.Y.Z.tar.gz.sha256
#
# 版本号取自 package/metadata.json 的 KPlugin.Version。
# 打包前默认跑一遍单元测试与 qmllint，可以用 --skip-checks 跳过。
#
#   ./tools/build-release.sh
#   ./tools/build-release.sh --skip-checks

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SKIP_CHECKS=0
for arg in "$@"; do
    case "$arg" in
        --skip-checks) SKIP_CHECKS=1 ;;
        -h|--help)
            sed -n '4,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "未知参数：$arg" >&2
            exit 2
            ;;
    esac
done

VERSION="$(python3 -c 'import json;print(json.load(open("package/metadata.json"))["KPlugin"]["Version"])')"
ASSET="kde-amdgpu-top-v${VERSION}.tar.gz"
DIST="$ROOT/dist"

echo "==> 版本：v${VERSION}"

if [[ $SKIP_CHECKS -eq 0 ]]; then
    echo "==> 单元测试"
    python3 tests/test_backend.py 2>&1 | tail -3

    QMLLINT="/usr/lib/qt6/bin/qmllint"
    command -v qmllint >/dev/null 2>&1 && QMLLINT="$(command -v qmllint)"
    if [[ -x "$QMLLINT" ]]; then
        echo "==> qmllint"
        for file in package/contents/ui/*.qml package/contents/ui/config/*.qml package/contents/config/config.qml; do
            out="$("$QMLLINT" -I /usr/lib/qt6/qml "$file" 2>&1 | grep -E "Error|Warning" | grep -v "unqualified\|missing-property\|KConfigPropertyMap" || true)"
            if [[ -n "$out" ]]; then
                echo "qmllint 在 $file 上报警：" >&2
                echo "$out" >&2
                exit 1
            fi
        done
        echo "    QML 检查通过"
    else
        echo "==> 没找到 qmllint，跳过 QML 检查"
    fi
fi

echo "==> 组装 $ASSET"
rm -rf "$DIST"
mkdir -p "$DIST/org.hao.amdgputop"
cp -a package/. "$DIST/org.hao.amdgputop/"
chmod +x "$DIST/org.hao.amdgputop/contents/scripts/amdgpu-topd.py"

tar -C "$DIST" -czf "$DIST/$ASSET" org.hao.amdgputop
( cd "$DIST" && sha256sum "$ASSET" > "$ASSET.sha256" )

echo "==> 包内文件（前 20 项）"
tar -tzf "$DIST/$ASSET" | head -20

echo "==> 校验"
( cd "$DIST" && sha256sum -c "$ASSET.sha256" )

cat <<EOF

完成：
  dist/$ASSET
  dist/$ASSET.sha256

发布步骤：
  git tag -a v${VERSION} -m "kde-amdgpu-top v${VERSION}"
  git push origin main --tags
  gh release create v${VERSION} \\
      dist/$ASSET dist/$ASSET.sha256 \\
      --title "v${VERSION}" \\
      --notes-file docs/releases/v${VERSION}.md
EOF
