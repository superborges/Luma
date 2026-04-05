#!/bin/zsh
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: scripts/run_real_folder_e2e.sh <import-folder> [output-root]" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
IMPORT_PATH=$1
OUTPUT_ROOT=${2:-"$REPO_ROOT/Artifacts/real-folder-e2e"}

if [[ ! -d "$IMPORT_PATH" ]]; then
  echo "Import folder does not exist: $IMPORT_PATH" >&2
  exit 1
fi

mkdir -p "$OUTPUT_ROOT"

cd "$REPO_ROOT"

HOME=/tmp \
CLANG_MODULE_CACHE_PATH=/tmp/luma-clang-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/luma-swiftpm-module-cache \
LUMA_REAL_IMPORT_PATH="$IMPORT_PATH" \
LUMA_REAL_OUTPUT_ROOT="$OUTPUT_ROOT" \
swift test --filter RealFolderIntegrationTests
