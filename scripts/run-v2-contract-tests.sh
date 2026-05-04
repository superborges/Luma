#!/usr/bin/env bash
# V2 合约：用真实 API Key 跑一次端到端的 group scoring + detailed analysis。
# 仅当本地配置了 scripts/v2-contract.local.sh（含 API Key）时才会真正发请求；否则测试 XCTSkip。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

LOCAL_SH="$REPO_ROOT/scripts/v2-contract.local.sh"
if [[ -f "$LOCAL_SH" ]]; then
  # shellcheck source=/dev/null
  source "$LOCAL_SH"
fi

if [[ -z "${LUMA_V2_AI_KEY:-}" ]]; then
  echo "warning: 未设置 LUMA_V2_AI_KEY，合约测试将走 XCTSkip。" >&2
  echo "  复制 scripts/v2-contract.local.example.sh 为 scripts/v2-contract.local.sh 并填写。" >&2
fi

export LUMA_V2_AI_KEY
export LUMA_V2_AI_PROTOCOL="${LUMA_V2_AI_PROTOCOL:-}"
export LUMA_V2_AI_ENDPOINT="${LUMA_V2_AI_ENDPOINT:-}"
export LUMA_V2_AI_MODEL_ID="${LUMA_V2_AI_MODEL_ID:-}"

exec swift test --filter AIContractIntegrationTests
