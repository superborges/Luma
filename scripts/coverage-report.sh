#!/usr/bin/env bash
# 单测行覆盖率：终端摘要 + **HTML 报告**（llvm-cov / Xcode 工具链）。
# 用法：仓库根目录执行 ./scripts/coverage-report.sh
# 已跑过测试且要秒出报告：SKIP_TEST=1 ./scripts/coverage-report.sh
# 跑完后在 macOS 上自动用默认浏览器打开「应用源」报告：COVERAGE_OPEN=1 ./scripts/coverage-report.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROF="$ROOT/.build/arm64-apple-macosx/debug/codecov/default.profdata"
BIN="$ROOT/.build/arm64-apple-macosx/debug/LumaPackageTests.xctest/Contents/MacOS/LumaPackageTests"
HTML_DIR="$ROOT/.build/coverage-html"
HTML_APP_DIR="$ROOT/.build/coverage-html-app"
HTML_CORE_DIR="$ROOT/.build/coverage-html-core"

if [[ -z "${SKIP_TEST:-}" ]]; then
  swift test --enable-code-coverage
else
  echo "(SKIP_TEST=1，复用已有 .profdata，未执行 swift test)"
fi

if [[ ! -f "$PROF" || ! -f "$BIN" ]]; then
  echo "coverage 数据未找到；请先成功执行 swift test --enable-code-coverage。" >&2
  exit 1
fi

generate_html() {
  local out="$1"
  local title=$2
  shift 2
  rm -rf "$out"
  xcrun llvm-cov show "$BIN" --instr-profile="$PROF" \
    --format=html --output-dir="$out" --project-title="$title" "$@"
}

echo "=== 正在生成 HTML 报告（llvm-cov show --format=html）==="

# 1) 含单测、DerivedSources 等，最全
generate_html "$HTML_DIR" "Luma — 全量（含单测与生成代码）"

# 2) 推荐日常查看：仅 Sources/Luma 应用/库，无 Tests*
generate_html "$HTML_APP_DIR" "Luma — 应用与库" \
  --ignore-filename-regex='Tests/|/LumaPackageTests\.derived/|/DerivedSources/resource_bundle'

# 3) 再排除典型 SwiftUI/主题层，与下方终端「2)」口径一致
generate_html "$HTML_CORE_DIR" "Luma — 无 Views 与 Design" \
  --ignore-filename-regex='Tests/|/LumaPackageTests\.derived/|/DerivedSources/resource_bundle|/Sources/Luma/Views/|/Sources/Luma/Design/'

echo ""
echo "已生成："
echo "  - 全量     file://$HTML_DIR/index.html"
echo "  - 应用源   file://$HTML_APP_DIR/index.html  （一般看这个）"
echo "  - 无 UI 层  file://$HTML_CORE_DIR/index.html"
echo ""

if [[ "${COVERAGE_OPEN:-}" == "1" ]] && command -v open >/dev/null; then
  open "$HTML_APP_DIR/index.html"
  echo "已用系统浏览器打开「应用与库」报告。"
fi

cov_total() {
  xcrun llvm-cov report "$BIN" -instr-profile="$PROF" "$@" 2>/dev/null | grep 'TOTAL' | tail -1
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " 行覆盖率 为何「看起来低」"
echo " - 下表「全量」= 整包 Luma 可执行体（含所有 SwiftUI View、LumaApp、"
echo "   PhotoKit/未桩适配器、Design 等）。单测不启动窗口，这些文件多为 0% 行，"
echo "   分母大，把百分比拉低，属工具口径，不代表业务逻辑全未测。"
echo " - 「排除 Views + Design」= 从分母中去掉最典型、只能靠 UI/快照测的层，"
echo "   数字更贴近 *Services / Models / 纯工具* 在你当前用例里的覆盖情况。"
echo " - 与 Photo 真机/TCC 强相关的文件仍可能接近 0%，需手测或专项桩工程。"
echo " - HTML 中「无 Views 与 Design」一版与下表第 2 行口径一致。"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "=== 1) 全量（仅排除 Test 目标自身）==="
cov_total -ignore-filename-regex='Tests'

echo ""
echo "=== 2) 排除 Sources/Luma/Views/ 与 Design/（见上文说明）==="
cov_total -ignore-filename-regex='Tests|/Sources/Luma/Views/|/Sources/Luma/Design/'

echo ""
echo "=== 3) 再排除 Luma 入口/若干 CLI/Inspector（可选参考，勿当作 KPI）==="
EXCLUDE_SHELL='Tests|/Sources/Luma/Views/|/Sources/Luma/Design/|/Sources/Luma/App/LumaApp\.swift|/Sources/Luma/App/LumaCommands\.swift|/Sources/Luma/App/BurstReviewCLI|/Sources/Luma/App/TraceSummaryCLI|/Sources/Luma/App/UISnapshotRenderer|/Sources/Luma/Views/Import/AppKitPhotos.*|/Sources/Luma/Views/Common/LumaInspectorOverlay|/Sources/Luma/Views/Common/View\+LumaTracking'
cov_total -ignore-filename-regex="$EXCLUDE_SHELL"

echo ""
echo "=== 4) 核心文件行（与业务相关、便于盯目录）==="
xcrun llvm-cov report "$BIN" -instr-profile="$PROF" 2>/dev/null | grep -E 'Sources/Luma/Services/(Import|Export|Grouping|Archive)/|Sources/Luma/App/ProjectStore\.swift' || true

echo ""
echo "未自动打开时，在终端执行: open $HTML_APP_DIR/index.html"
