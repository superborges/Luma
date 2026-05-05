#!/usr/bin/env bash
# E2E 回归测试：真实目录导入 → 分组 → 评分 → 导出 → 归档 全链路。
# 需要本地配置 scripts/e2e-regression.local.sh（从 .example.sh 复制）。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LOCAL_SH="$REPO_ROOT/scripts/e2e-regression.local.sh"
if [[ -f "$LOCAL_SH" ]]; then
  # shellcheck source=/dev/null
  source "$LOCAL_SH"
fi

MISSING=()
[[ -z "${LUMA_E2E_SD_PATH:-}" ]] && MISSING+=("LUMA_E2E_SD_PATH")
[[ -z "${LUMA_E2E_PHOTO_PATH:-}" ]] && MISSING+=("LUMA_E2E_PHOTO_PATH")
[[ -z "${LUMA_E2E_OUTPUT_ROOT:-}" ]] && MISSING+=("LUMA_E2E_OUTPUT_ROOT")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "error: 缺少环境变量: ${MISSING[*]}" >&2
  echo "  复制 scripts/e2e-regression.local.example.sh 为 scripts/e2e-regression.local.sh 并填写目录" >&2
  exit 1
fi

for VAR in LUMA_E2E_SD_PATH LUMA_E2E_PHOTO_PATH; do
  DIR="${!VAR}"
  if [[ ! -d "$DIR" ]]; then
    echo "error: $VAR 目录不存在: $DIR" >&2
    exit 1
  fi
done

mkdir -p "$LUMA_E2E_OUTPUT_ROOT"

export LUMA_E2E_SD_PATH LUMA_E2E_PHOTO_PATH LUMA_E2E_OUTPUT_ROOT

echo "═══════════════════════════════════════════════════"
echo "  Luma E2E Regression Tests"
echo "═══════════════════════════════════════════════════"
echo "  SD:     $LUMA_E2E_SD_PATH"
echo "  Photo:  $LUMA_E2E_PHOTO_PATH"
echo "  Output: $LUMA_E2E_OUTPUT_ROOT"
echo "═══════════════════════════════════════════════════"

exec swift test --filter FullRegressionTests
