#!/usr/bin/env bash
# 清空本机 Luma 本地数据：项目 / 可恢复导入 / 归档 / 诊断等（与 App 内「数据目录」一致）。
# 不改动系统「照片」TCC 授权；若权限状态异常，可在完全退出 App 后执行：
#   tccutil reset Photos app.luma.Luma
set -euo pipefail

BUNDLE_ID="app.luma.Luma"
SUPPORT="${HOME}/Library/Application Support/Luma"

usage() {
  echo "用法: $0 [--yes]"
  echo "  删除: $SUPPORT"
  echo "  并执行: defaults delete $BUNDLE_ID（UserDefaults：Session 排序、导出选项、是否看过 Onboarding 等）"
  exit 1
}

YES=0
[[ "${1:-}" == "--yes" ]] && YES=1
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage

if [[ "$YES" != 1 ]]; then
  echo "将删除本机 Luma 数据目录并清空 UserDefaults。"
  echo "  目录: $SUPPORT"
  echo "若确认，请加上: --yes"
  exit 2
fi

if pgrep -xq "Luma" 2>/dev/null; then
  echo "请先完全退出 Luma（⌘Q），再运行本脚本。" >&2
  exit 3
fi

if [[ -d "$SUPPORT" ]]; then
  echo "→ 删除 $SUPPORT"
  rm -rf "$SUPPORT"
else
  echo "→ 数据目录不存在，跳过: $SUPPORT"
fi

# 本机构建若从未写入过该 domain，会报错，忽略即可
if defaults read "$BUNDLE_ID" &>/dev/null; then
  echo "→ defaults delete $BUNDLE_ID"
  defaults delete "$BUNDLE_ID" 2>/dev/null || true
else
  echo "→ 无 $BUNDLE_ID 的 UserDefaults 记录，跳过"
fi

echo "完成。下次打开 Luma 为干净状态；若仍反复索要照片权限，可尝试：tccutil reset Photos $BUNDLE_ID"
