# Coding Agent Brief — F3 云端组内批量评分 + F6 BatchScheduler 与费用追踪

## 背景

当前要实现的是 **云端批量评分流水线**，目标是让用户能在选片工作区一键启动「按 PhotoGroup 批量评分」，过程中实时显示进度与费用，每组完成立即写盘（断点续传），失败有重试与跳过。本 Brief 依赖已完成的 Brief A（VisionModelProvider 协议层 + ModelConfigStore），输出能让用户**真实跑通一次端到端云端评分**的链路（含 UI 顶部进度条与确认弹窗）。

## 本次只做

- **数据模型**：
  - `ScoringStatus`（`.idle` / `.running` / `.paused` / `.completed` / `.failed`）写入 session 元数据
  - `ScoringJob`（id / strategy / startedAt / model: ModelConfig.id / totalGroups / completedGroups / status / pausedReason?）
  - `BudgetSnapshot`（inputTokens / outputTokens / usd / threshold）
  - `ScoringProgressEvent`（已完成 / 总数 / 当前组名 / 累计 USD / 当前模型名）
- **服务层**（`Sources/Luma/Services/AI/`）：
  - `BatchScheduler`：以 PhotoGroup 为单位调度；`TaskGroup` + 信号量限制并发；指数退避（1s / 4s / 16s）；通过 AsyncStream 推 `ScoringProgressEvent`
  - `BudgetTracker`：累加每组返回的 `TokenUsage`；按模型单价计算 USD；超阈值通过回调通知 Coordinator 暂停
  - `CloudScoringCoordinator`：编排 BatchScheduler + BudgetTracker + ProjectStore 写盘；提供 `start(strategy:) / pause() / resume() / cancel()` API
  - `ScoringJobStore`：把 `ScoringJob` 持久化到 session 目录（`scoring_job.json`），支持断点续传（重启 App 后继续未完成的组）
- **ProjectStore 接入**（`Sources/Luma/App/ProjectStore.swift`）：
  - 新增 `@Published scoringStatus: ScoringStatus`
  - 新增 `@Published scoringProgress: ScoringProgressEvent?`
  - 新增 `@Published currentBudget: BudgetSnapshot?`
  - 新增方法：`startCloudScoring(strategy: ScoringStrategy)` / `pauseCloudScoring()` / `resumeCloudScoring()` / `cancelCloudScoring()`
  - 新增方法：`applyGroupScoreResult(_ groupID: UUID, result: GroupScoreResult)` — 把云端评分覆盖写入 `MediaAsset.aiScore` 并立即 flush manifest；保留本地 Core ML 已识别的 `issues` 标签
  - 新增方法：`applyGroupScoreFailure(_ groupID: UUID, error: Error)` — 记录失败但不阻塞其他组
  - 启动时检测 `scoring_job.json`：若存在且 status == `.running`，自动恢复
- **UI**（`Sources/Luma/Views/Culling/`）：
  - 顶部新增 `ScoringProgressBar`：细线进度条 + 模型名 + 已完成 / 总数 + 累计 USD + 暂停按钮
  - 顶部 toolbar 新增「**开始 AI 评分**」按钮（仅在 `scoringStatus == .idle` 且至少有一个 isActive 模型时启用）
  - **`ScoringConfirmSheet`**：显示预估张数 / 预估费用（按 `count × avg_token × 单价`，标注「预估，实际以返回为准」） / 模型名 / 并发数 / 当前策略；按钮：「确认开始 / 取消」
  - **`BudgetExceededSheet`**：超阈值时阻断式弹出；显示「已花费 $X / 阈值 $Y」+「继续 / 取消 / 调整阈值」三按钮
  - 评分进行中右栏 `AIScoreCardView` 增加左上角「云端 ✓」/「本地」小角标（沿用 V1 视觉，仅加角标）

## 本次明确不做

- 不做单张修图建议（`requestEditSuggestions` 流程）→ 在 Brief C
- 不做策略选择 UI（默认硬编码 `.balanced`，可通过测试代码切换）→ 在 Brief C
- 不做设置页 AI 模型 Tab → 在 Brief C
- 不做评分进度的图表可视化（仅细线进度条 + 数字）
- 不做 RPM 自适应限速（用 ModelConfig.maxConcurrency 静态值）
- 不做并行多模型混评
- 不动 `LocalMLScorer`：本地评分继续在导入阶段跑，云端评分**覆盖** `aiScore` 字段，但保留 `issues`
- 不动导出流程：导出仍按 `userDecision` 走

## 用户主路径

1. 用户进入：打开 App → Session 列表 → 选已配置至少一个 AI 模型的 session（无模型则按钮 disabled）
2. 用户操作：
   - 点选片工作区顶部「**开始 AI 评分**」 → 弹出 `ScoringConfirmSheet`
   - 看到「预估 ~120 张 / ~$0.30 / 模型: Gemini 2.0 Flash / 并发 4」
   - 点「确认开始」→ 弹窗关闭，顶部出现细线进度条
   - 进行中可继续选片决策（P/X/U），UI 不冻结
   - （可选）点暂停 → 进度条停 → 再点继续
3. 系统反馈：
   - 每组完成后 manifest flush + 进度条更新
   - 单组失败：右栏角标「该组评分失败」+ 重试按钮（手动重试该组）
   - 累计 USD 超阈值：阻断弹 `BudgetExceededSheet`
4. 用户完成：
   - 全部组评分结束 → toast「云端评分完成 / 用时 X 分 / 共 $Y」+ Session 列表打 ✓
   - 中途取消 → 已完成的组保留，未开始的组保持 `aiScore` 为本地评分

## 页面与组件

- 需要新增的页面：
  - `ScoringConfirmSheet`：开始评分前的二次确认弹窗
  - `BudgetExceededSheet`：超费用阈值的阻断弹窗
- 需要新增的组件：
  - `ScoringProgressBar`：选片工作区顶部细线进度条
- 可以复用的组件：
  - V1 `AIScoreCardView`（仅给左上角加「云端 / 本地」角标）
  - V1 `IssueTagsView`（不变）
  - 现有 `ProjectStore` 的 manifest 持久化能力

## 交互要求

- 默认状态：`scoringStatus == .idle`，按钮显示「开始 AI 评分」
- 主按钮行为：「开始 AI 评分」→ 弹 `ScoringConfirmSheet` → 「确认开始」启动 Coordinator
- 次按钮行为：进度条上的暂停 / 继续 / 取消
- 返回行为：评分进行中关闭 session 视图 → 后台继续；下次进入时进度条仍可见
- 空状态：未配置任何 isActive 模型 → 「开始 AI 评分」按钮 disabled，hover 显示「请先在设置中添加 AI 模型」
- 错误状态：
  - 单组失败 → 卡片角标「评分失败」+ 重试按钮
  - 全局网络断 → 全局 banner「网络异常，已暂停」+ 自动恢复（监听 `NWPathMonitor`）
  - 模型 Key 失效（401）→ banner「API Key 无效」+ 跳转设置

## UI 要求

- 风格方向：与 V1 选片工作区视觉一致（深色背景、紧凑间距、StitchTheme.primary 高亮色）
- 必须保留的现有风格：
  - V1 已稳定的 `AIScoreCardView` / `IssueTagsView` 视觉不变
  - 顶部 toolbar 现有按钮位置不动，新增按钮加在右侧
- 可以自由发挥的范围：
  - 进度条样式（细线 / 块状均可）
  - 模型来源角标（小图标 + 文字）
- 不要为了"好看"增加复杂装饰（无动画进度条、无粒子效果）

## 技术约束

- 技术栈：SwiftUI / Swift Concurrency / 现有 `ProjectStore` 的 `@Observable`
- 状态管理方式：所有评分相关 state 进 `ProjectStore`，UI 订阅；BatchScheduler / Coordinator 是独立 service，由 ProjectStore 持有
- 数据先用 mock 还是真接口：
  - 单测：用 `MockHTTPClient` + fixture（同 Brief A）
  - 集成测试：标记 `XCTSkip(LUMA_V2_CONTRACT 未设置)`，仅在本地配置真实 API Key 时跑
- 不要顺手重构无关模块（特别是 `LocalMLScorer` / `GroupingEngine` / `ImportManager`）
- 不要擅自引入新的大型依赖
- 网络全程 async，不阻塞主 actor；图片 base64 编码已在 Brief A 保证 background queue
- manifest flush 必须**事务性**：先写 `.tmp` → 重命名（沿用现有 `Self.saveManifest` 逻辑）
- API Key 不进 trace / log；只记录 modelID 与 group counts
- BatchScheduler 取消必须可在 < 2s 内停止（不强杀已发送的 HTTP，但不再发新请求）

## 输出顺序

1. **数据模型 + ScoringJobStore**（独立可测）
2. **BudgetTracker**（独立可测）
3. **BatchScheduler**（依赖 1 + 2 + Brief A 的 Provider）
4. **CloudScoringCoordinator**（编排层）
5. **ProjectStore 接入** + manifest flush 逻辑 + 启动恢复
6. **ScoringProgressBar** + 顶部按钮
7. **ScoringConfirmSheet** + **BudgetExceededSheet**
8. **AIScoreCardView 加角标**
9. **单测**：
   - `BatchSchedulerTests`：并发上限、指数退避、单组失败不阻塞、取消生效
   - `BudgetTrackerTests`：阈值检查、累加正确性
   - `ScoringJobStoreTests`：断点续传、JSON round-trip
   - `CloudScoringCoordinatorTests`：编排顺序、暂停/恢复
   - `ProjectStoreScoringTests`：applyGroupScoreResult 写盘 + issues 保留

## 验收标准

- [ ] 用户可点「开始 AI 评分」，看到确认弹窗，确认后顶部进度条出现
- [ ] 评分进行中可继续 P / X / U 选片，UI 60fps（无明显卡顿）
- [ ] 每组完成后 `MediaAsset.aiScore.provider` 字段反映实际模型 ID（区分本地/云端）
- [ ] 重启 App 后，未完成评分的 session 自动恢复进度（断点续传）
- [ ] 单组评分失败 → 右栏角标 + 手动重试按钮可用
- [ ] 超费用阈值时阻断弹窗，「继续」恢复 / 「取消」终止
- [ ] 评分完成后 Session 列表显示 ✓ 标记
- [ ] API Key 在 trace / log 中均无明文出现
- [ ] `swift test` 全量通过（含本次新增测试）
- [ ] V2 合约测试 `./scripts/run-v2-contract-tests.sh` 在配置 LUMA_V2_CONTRACT 时通过（无配置时 XCTSkip）
- [ ] 没有大面积改坏其他页面（V1 已有功能不受影响）
- [ ] 不引入新的外部依赖
