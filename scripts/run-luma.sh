#!/usr/bin/env bash
# 构建 → 打 Luma.app → ad-hoc 签名 → 重启。macOS 对 Photos 等 TCC 权限
# 要求标准 .app bundle，裸可执行文件授权弹窗不稳定。
#
# 用法：
#   scripts/run-luma.sh                # debug + 启动（默认）
#   scripts/run-luma.sh --release      # release 构建 + 启动
#   scripts/run-luma.sh --release --no-launch
#                                      # release 构建并打包成 .app，不启动
set -euo pipefail

CONFIGURATION="debug"
LAUNCH=1
for arg in "$@"; do
  case "$arg" in
    --release)
      CONFIGURATION="release"
      ;;
    --debug)
      CONFIGURATION="debug"
      ;;
    --no-launch)
      LAUNCH=0
      ;;
    *)
      echo "未知参数: $arg" >&2
      echo "用法: $0 [--release|--debug] [--no-launch]" >&2
      exit 1
      ;;
  esac
done

cd "$(dirname "$0")/.."

echo "[1/5] swift build (configuration=$CONFIGURATION)"
swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BIN="$BIN_DIR/Luma"
APP="$BIN_DIR/Luma.app"
if [ ! -x "$BIN" ]; then
  echo "找不到可执行文件: $BIN" >&2
  exit 1
fi

echo "[2/5] 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Luma"
cp Sources/Luma/App/Info.plist "$APP/Contents/Info.plist"
# SwiftPM 把资源放在 Luma_Luma.bundle，位于可执行文件旁边。带进来，免得 .app 找不到。
for res in "$BIN_DIR"/*.bundle; do
  [ -e "$res" ] || continue
  cp -R "$res" "$APP/Contents/Resources/"
done

echo "[3/5] codesign --force --sign - $APP"
codesign --force --deep --sign - --timestamp=none "$APP"

if [ "$LAUNCH" -eq 0 ]; then
  echo "[4/5] --no-launch：跳过启动，已生成 $APP"
  exit 0
fi

echo "[4/5] 杀掉旧 Luma 进程"
osascript -e 'tell application "Luma" to quit' 2>/dev/null || true
pkill -x Luma 2>/dev/null || true
sleep 0.5

echo "[5/5] open $APP"
# macOS 26 / Swift 6.2 / arm64e 的 swift_task_isCurrentExecutorWithFlagsImpl PAC failure 全局规避：
# 让 Swift 运行时用 legacy（非崩溃）模式做 executor isolation check。
# 详见 KNOWN_ISSUES.md 及 https://www.hughlee.page/en/posts/swift-6-migration-pitfalls/
# Info.plist LSEnvironment 也设了同样的值（Finder 双击启动时生效），这里覆盖开发流程。
SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE=legacy open "$APP"
sleep 0.8
if pgrep -x Luma >/dev/null; then
  echo "Luma 已启动 (pid=$(pgrep -x Luma))"
else
  echo "启动似乎失败，查看 Console 或 /tmp/luma.out"
  exit 1
fi
