# Coding Agent Brief — F4 单张修图建议 + F5 三档策略 + F7 设置页 AI 模型 Tab

## 背景

当前要实现的是 **V2 用户面前最直观的部分**：选片右栏的 AI 增强卡（含修图建议可视化）、三档评分策略选择、设置页 AI 模型管理 Tab。本 Brief 依赖已完成的 Brief A（Provider 协议层）和 Brief B（CloudScoringCoordinator + 评分流水线），输出**用户能从设置加模型 → 选策略 → 跑评分 → 看修图建议的完整闭环**。

## 本次只做

- **数据模型补全**：
  - `ScoringStrategy`（`.local` / `.balanced` / `.best`）写入 UserDefaults
  - `EditSuggestionsRequestStatus`（`.idle` / `.loading` / `.completed` / `.failed`）每个 asset 一份
- **ProjectStore 扩展**（接续 Brief B）：
  - 新增 `requestEditSuggestions(for assetID: UUID)` 方法
  - 内部：找 `role == .premiumFallback && isActive` 的模型 → 调 `provider.detailedAnalysis(image, context)` → 写回 `MediaAsset.editSuggestions`
  - 同时维护 `editSuggestionsRequestStatus: [UUID: Status]`，UI 订阅
  - 用户在 strategy 切换时调 `setScoringStrategy(_:)`，立即持久化到 UserDefaults
- **设置页 AI 模型 Tab**（`Sources/Luma/Views/Settings/AIModelsSettingsView.swift`）：
  - 三段式布局：模型列表 / 单模型详情 / 策略与预算
  - **模型列表**：左侧 List + 「+」按钮添加；每行：名称 / 协议 / Role 下拉 / isActive Toggle / 删除按钮
  - **单模型详情**：
    - 协议选择（segmented control：OpenAI 兼容 / Gemini / Claude）
    - 名称（TextField，必填）
    - Endpoint（TextField，按协议给 placeholder 默认值）
    - Model ID（TextField，按协议给 placeholder，如 `gemini-2.0-flash`）
    - API Key（SecureField，**不显示已存值**，只在用户输入新值时覆盖）
    - 单价（两个数字输入：input / output token，单位 USD/1M tokens）
    - maxConcurrency（Stepper，范围 1-10）
    - 「**测试连接**」按钮：调 `provider.testConnection()` → 显示 ✓ / ✗ 与原因
  - **策略与预算**：
    - 策略选择（RadioGroup：省钱 / 均衡 / 最佳质量），下方文案解释含义与预估费用规模
    - 预算阈值（Stepper：1 / 5 / 10 / 20 / 50 USD/批次，默认 5）
- **选片工作区右栏 AI 增强区块**（`Sources/Luma/Views/Culling/AIEnhancementSection.swift`）：
  - 顶部状态行：策略 + 当前评分来源（云端/本地）+ 「请求修图建议」按钮
  - 「**请求修图建议**」按钮：仅在 `editSuggestions == nil && status != .loading` 且已配置 premiumFallback 模型时启用；点后变 spinner
  - **修图建议可视化卡片**（仅在 `editSuggestions != nil` 时展示）：
    - **裁切预览框**：用 `Path` 在缩略图上画出 crop 区域 + 比例数字（如 `16:9`）+ 方向描述
    - **关键调整**：6 项滑块（不可拖动，仅展示数值）— 曝光 / 对比度 / 高光 / 阴影 / 色温 / 饱和度
    - **HSL 色块**：横向小色块矩阵，每个色块下显示 H/S/L 调整值
    - **滤镜风格**：标签 + 参考字符串（如「VSCO A6 风格」）
    - **局部建议**：bullet 列表
    - **修图思路**：中文 narrative 文本（多行可滚动）
- **合约测试脚本**（`scripts/run-v2-contract-tests.sh` + `Tests/LumaTests/AIContractIntegrationTests.swift`）：
  - 读取 `scripts/v2-contract.local.sh`（用户本地配置 API Key，**.gitignore**）
  - 用真实 API 跑一次 group scoring + 一次 detailed analysis（数据集：仓库内 `Tests/Fixtures/AI/sample_photos/`，3-5 张测试图）
  - 断言返回结构完整 + token 使用量 > 0 + narrative 非空
  - 默认 `XCTSkip` 未配置时

## 本次明确不做

- 不重构 V1 已稳定的 EXIF 信息卡 / 决策按钮
- 不做修图建议的"应用到 Lightroom"导出（XMP 写入放 V3）
- 不做评分校准（线性归一化）
- 不做模型管理的导入 / 导出 JSON 配置文件（手动配即可）
- 不做"批量请求修图建议"（单张触发即可，避免一次烧爆预算）
- 不动 Brief B 已实现的 BatchScheduler / Coordinator（仅消费）
- 不做修图建议的版本历史（只保留最新一次）
- 不做修图建议「重新生成」之外的编辑（如手动调整滑块值）

## 用户主路径

1. **首次配置**：
   - 用户进入设置 → AI 模型 Tab → 看到空列表
   - 点「+」→ 选「Gemini」→ 自动填默认 endpoint / model id placeholder
   - 用户填名称「我的 Gemini」/ Model ID `gemini-2.0-flash` / API Key（粘贴）/ 单价（默认值）
   - 点「测试连接」→ ✓
   - 设 Role = `.primary` / isActive = on
   - （可选）再加一个 Claude Sonnet 设为 `.premiumFallback`
   - 切换策略 = 均衡，预算 = 5 USD
2. **跑评分**（沿用 Brief B 的流程）：
   - 选片页点「开始 AI 评分」→ 确认弹窗 → 后台跑
3. **看修图建议**：
   - 选片页选中一张满意照片 → 右栏 AI 增强区块 → 点「请求修图建议」
   - 5-15 秒后右栏展开可视化卡片：裁切预览 + 6 项滑块 + HSL 色块 + 中文 narrative
   - 用户对照建议在 Lightroom / Photos 手动调整
4. **完成**：用户继续选下一张；已请求过的照片右栏直接展示已有建议

## 页面与组件

- 需要新增的页面：
  - `AIModelsSettingsView` 整个 Tab（位于 `SettingsView` 内）
  - 新增子组件 `ModelDetailEditor` / `StrategyPicker` / `BudgetThresholdStepper`
- 需要新增的组件：
  - `AIEnhancementSection`（右栏内嵌）
  - `EditSuggestionsCard`（修图建议可视化主卡）
    - `CropPreviewOverlay`（缩略图上的裁切框）
    - `AdjustmentSliderRow`（不可拖动的展示用滑块行）
    - `HSLPaletteRow`（HSL 色块矩阵）
- 可以复用的组件：
  - V1 `AIScoreCardView`（继续用于显示总分）
  - V1 `IssueTagsView`（不变）
  - Brief B 的 `ScoringProgressBar`

## 交互要求

- 默认状态（设置页）：模型列表为空 → 显示「点 + 添加你的第一个 AI 模型」+ 引导文案
- 默认状态（右栏）：未请求过修图建议 → 显示按钮 + 灰色文案「请求 AI 修图建议（约 ~$0.02 / 张）」
- 主按钮行为：
  - 设置页「测试连接」→ 后台调 `provider.testConnection()` → 结果展示在按钮旁
  - 右栏「请求修图建议」→ spinner → 成功展开卡片 / 失败展示 retry
- 次按钮行为：
  - 设置页删除模型 → 确认弹窗 → 同时清 Keychain
  - 右栏「重新生成」（仅在已有建议时显示，二次确认避免误操作烧钱）
- 返回行为：设置 Tab 切换前自动保存所有字段（API Key 仅在用户主动输入时写 Keychain）
- 空状态：
  - 模型列表空 → 引导添加
  - 未配 premiumFallback → 「请求修图建议」按钮 disabled，hover 提示「策略需要 premiumFallback 模型」
- 错误状态：
  - 测试连接失败 → 红色 ✗ + 错误原因（"401 invalid key" / "network timeout" / "model not found"）
  - 修图建议请求失败 → 卡片显示「请求失败：原因」+「重试」

## UI 要求

- 风格方向：
  - 设置 Tab 风格与 V1 设置页一致（macOS Settings 原生风格）
  - 右栏 AI 增强区块沿用 V1 卡片样式（深色背景、StitchTheme.primary 高亮）
- 必须保留的现有风格：
  - V1 选片工作区右栏布局不变（EXIF 卡 + AI 评分卡 + 废片标签 → 这次新增 AI 增强区块加在最下方）
  - V1 设置页其他 Tab（通用 / 默认导入 / 等）不动
- 可以自由发挥的范围：
  - 修图建议卡片的可视化方式（滑块 / 数字 / 色块的具体样式）
  - HSL 色块矩阵的视觉
- 不要为了"好看"增加复杂装饰：
  - 滑块只展示数值，不模拟 Lightroom 的实际渲染效果
  - 不做实时图像预览滤镜应用（这是 V3+ 的事）

## 技术约束

- 技术栈：SwiftUI（设置 Tab + 右栏区块）；Swift Concurrency（异步请求）
- 状态管理方式：
  - 模型配置走 `ModelConfigStore`（Brief A 已实现）
  - 修图建议走 `ProjectStore.requestEditSuggestions` + manifest 持久化
  - 策略选择走 UserDefaults（key=`Luma.scoringStrategy`）
  - 预算阈值走 UserDefaults（key=`Luma.budgetThreshold`）
- 数据先用 mock 还是真接口：
  - UI 单测：`PreviewProvider` + 静态 `EditSuggestions` mock
  - ProjectStore 单测：用 `MockVisionModelProvider`
  - 真实跑通：合约测试脚本（用户本地配置 API Key 后跑）
- 不要顺手重构无关模块（特别是 V1 设置页其他 Tab、V1 选片工作区核心布局）
- 不要擅自引入新的大型依赖
- API Key SecureField 不读已存值（`""` 占位），仅在用户主动输入时调 `setAPIKey`；提交未输入时**不动**已存 key
- 删除模型 → 同时清 Keychain；删除失败仅 log warning（避免 UI 卡死）
- 修图建议 manifest 写入与 Brief B 的 `applyGroupScoreResult` 走同一个 flush 函数（事务性）
- 合约测试 `XCTSkip` 模式与 `RealFolderIntegrationTests` 一致

## 输出顺序

1. **数据模型补全 + UserDefaults key 定义**
2. **ProjectStore.requestEditSuggestions** + 单测（用 MockProvider）
3. **AIModelsSettingsView 模型列表 + 增删改**
4. **ModelDetailEditor + 测试连接按钮**
5. **StrategyPicker + BudgetThresholdStepper**
6. **AIEnhancementSection 顶部状态行 + 请求按钮**
7. **EditSuggestionsCard + 子组件**（裁切预览 / 滑块 / HSL）
8. **合约测试脚本 + AIContractIntegrationTests**
9. **单测补充**：
   - `AIModelsSettingsViewModelTests`：增删改、Keychain 同步
   - `EditSuggestionsCardTests`：snapshot test（关键参数渲染）
   - `ProjectStoreEditSuggestionsTests`：requestEditSuggestions 流程
   - `AIContractIntegrationTests`（XCTSkip）：真实 API round-trip

## 验收标准

- [ ] 用户能在设置页添加 / 编辑 / 删除模型，操作即时持久化
- [ ] 「测试连接」按钮对三种协议（OpenAI 兼容 / Gemini / Claude）均能正确调用并显示 ✓ / ✗
- [ ] 删除模型时同时清 Keychain（manifest / log 永远无明文 key）
- [ ] 策略选择持久化到 UserDefaults，重启后保持
- [ ] 预算阈值持久化到 UserDefaults，超阈值时 Brief B 的弹窗触发（端到端联调）
- [ ] 选片右栏 AI 增强区块正确显示策略 + 来源
- [ ] 「请求修图建议」按钮在配置正确时启用；点击后右栏展开可视化卡片
- [ ] 修图建议卡片包含：裁切预览框 + ≥6 项调整滑块数值 + HSL 色块 + 中文 narrative
- [ ] 修图建议失败时显示具体原因 + 重试按钮
- [ ] V2 合约测试脚本在本地配置 API Key 时全过；CI 中 XCTSkip
- [ ] `swift test` 全量通过（含本次新增测试）
- [ ] 没有大面积改坏 V1 已稳定的设置页其他 Tab / 选片工作区其他区域
- [ ] 不引入新的外部依赖
