#!/usr/bin/env bash
# V1 合约：真实文件夹导入 → 导出 / 归档 集成测试（需本地素材目录）。
# 见 scripts/v1-contract.local.example.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LOCAL_SH="$REPO_ROOT/scripts/v1-contract.local.sh"
if [[ -f "$LOCAL_SH" ]]; then
  # shellcheck source=/dev/null
  source "$LOCAL_SH"
fi

if [[ -z "${LUMA_V1_CONTRACT:-}" ]]; then
  echo "error: 未设置 LUMA_V1_CONTRACT" >&2
  echo "  复制 scripts/v1-contract.local.example.sh 为 scripts/v1-contract.local.sh 并填写目录，或：" >&2
  echo "  LUMA_V1_CONTRACT=/path/to/fixtures swift test --filter RealFolderIntegrationTests" >&2
  exit 1
fi

if [[ ! -d "$LUMA_V1_CONTRACT" ]]; then
  echo "error: 目录不存在: $LUMA_V1_CONTRACT" >&2
  exit 1
fi

export LUMA_V1_CONTRACT
echo "→ LUMA_V1_CONTRACT=$LUMA_V1_CONTRACT"
exec swift test --filter RealFolderIntegrationTests
