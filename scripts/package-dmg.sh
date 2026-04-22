#!/usr/bin/env bash
# 把 release 版 Luma.app 打包成简易 DMG 给内测用。
# 不做公证（v1 阶段还未配置 Apple Developer 账户）；用户首启需手动右键 → 打开。
set -euo pipefail

cd "$(dirname "$0")/.."

# 1. 打 release .app（复用 run-luma.sh）
scripts/run-luma.sh --release --no-launch

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$BIN_DIR/Luma.app"
if [ ! -d "$APP" ]; then
  echo "找不到 Luma.app: $APP" >&2
  exit 1
fi

# 2. 准备 staging 目录
STAGING="${BIN_DIR}/Luma-DMG-Staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 3. 输出位置：Artifacts/Luma-<timestamp>.dmg
TS="$(date +%Y%m%d_%H%M%S)"
OUT_DIR="Artifacts"
mkdir -p "$OUT_DIR"
DMG="$OUT_DIR/Luma-$TS.dmg"

if command -v create-dmg >/dev/null 2>&1; then
  create-dmg --volname "Luma $TS" --window-size 540 380 --app-drop-link 380 200 \
    "$DMG" "$STAGING/Luma.app"
else
  hdiutil create -volname "Luma $TS" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
fi

echo "DMG written: $DMG"
echo "提示：内测用户首启时需要右键 → 打开（无公证签名）。"
