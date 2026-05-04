# Build Spec — Luma V2

## 1. 版本信息

- 产品：Luma（拾光）
- 版本：V2 — 云端 AI 评分与修图建议
- 日期：2026-05

## 2. 本次版本目标

- 本次版本要解决的核心问题：MVP/V1 已跑通本地闭环，但选片决策仍主要依赖用户肉眼判断；本地 Core ML 只能做"废片识别"，无法做"好片判断"。用户在 300-1000 张候选中做精选时，缺乏一个能给出**主观审美评价 + 修图思路**的助手。
- 本次版本最重要的用户任务：让用户在选片时**看到云端模型的整组点评和单张精评**（构图/曝光/色彩/锐度/故事性五维），并对中意的照片**一键查看 AI 修图建议**（裁切/曝光/HSL/局部），辅助"该选哪张、选完怎么调"。
- 本次版本完成后，用户能做到什么：
  - **配置任意 OpenAI 兼容 / Gemini / Claude 模型**作为评分提供方（API Key 自管，本地 Keychain 加密）
  - **按分组批量打分**：每组 5-8 张一次 API 调用，5 维评分 + 总分 + 中文一句话评语 + AI 推荐标记
  - **单张精评（可选）**：对自己中意的照片，一键请求详细修图建议，结果在右栏可视化
  - **三档预算策略**：省钱（仅本地）/ 均衡（便宜模型全量 + 贵模型精评）/ 最佳质量（贵模型全量）
  - **费用透明**：实时显示已消耗 token / 美元，超阈值暂停

## 3. 功能范围

### 本次包含

- **F1 VisionModelProvider 协议层**：抽象 OpenAI 兼容 / Google Gemini / Anthropic Messages 三种 API 协议，统一返回 `GroupScoreResult` / `DetailedAnalysisResult`
- **F2 ModelConfig 持久化**：模型列表存 UserDefaults，API Key 单独存 Keychain；增删改 / 测试连接 / 启用停用
- **F3 云端组内批量评分**：以 PhotoGroup 为单位打包请求，写回 `MediaAsset.aiScore`（覆盖本地 Core ML 评分），同步刷新 `PhotoGroup.recommendedAssets` / `groupComment`
- **F4 单张 AI 修图建议**：选片右栏新增「请求修图建议」按钮，写回 `MediaAsset.editSuggestions`，可视化展示裁切框、曝光/对比度滑块值、HSL、局部建议
- **F5 三档评分策略**：省钱（仅本地）/ 均衡（primary 全量 + premiumFallback 仅 Top 20%）/ 最佳质量（premium 全量 + 修图建议）
- **F6 BatchScheduler 与费用追踪**：并发控制、指数退避、token 计费、超阈值弹窗暂停
- **F7 设置页 - AI 模型管理 Tab**：模型增删改、Endpoint / Key / Model ID / Role / 并发数、连接测试、费用阈值（默认 $5/批次）

### 本次不包含

- **评分校准**（20 张参考照片归一化）— 首版用模型原始评分，校准放 V3
- **AI 组名生成**（"清水寺·日落"）— 继续用「时间 + 地点」规则
- **修图建议写入 XMP**（`crs:Exposure2012` 等）— 数据先存 manifest，导出层放 V3
- **AI 评语写入 Photos App 描述**— 同上，输出层暂不动
- **视频归档完善**（Ken Burns / H.265）— 继续用 MVP 的精简方案
- **多语言切换**（中/英/跟随系统）
- **DiskArbitration SD 卡监控迁移**
- **AirDrop / Downloads 文件夹监控**
- **流式响应**（SSE）— 首版按整批 await，UI 用进度条而非逐字渲染

## 4. 用户主路径

1. 用户进入：打开 App → Session 列表，选择已导入完成的 Session
2. 用户看到：选片工作区右栏多了一个 **AI 增强**区块，提示「未启用云端评分 / 已配置 N 个模型 / 当前策略：均衡」
3. 用户执行：
  - 首次配置：进入设置 → AI 模型 Tab → 添加模型（Gemini / GPT-4o / Claude）→ 测试连接 → 选择策略
  - 触发评分：选片页顶部按钮「**开始 AI 评分**」→ 弹窗显示预估张数 / 预估费用 / 模型 / 并发，点确认后开始
  - 查看结果：评分进度条出现在顶部，结束后右栏的五维子分立刻刷新（带「云端/本地」标记）；连拍组的「采纳推荐」会优先用云端的 `recommended_assets`
  - 修图建议：在右栏选中一张照片后，点击「**生成修图建议**」→ 单张精评 → 右栏展开裁切预览框 + 调整参数滑块预览 + HSL 色块 + 中文修图思路
4. 系统反馈：每次 API 调用更新顶部费用累计；超阈值时全局暂停并弹窗（继续 / 取消 / 调整阈值）
5. 用户完成：评分完成的 session 在 Session 列表显示「云端评分 ✓」标记；导出时（与 V1 一致）按用户 Decision 走，不强依赖云端结果

## 5. 页面清单

- Session 列表：增加「云端评分进度 / 完成标记」（继承 MVP / V1 列表）
- **选片工作区**：右栏新增 **AI 增强**区块（评分来源、修图建议入口、修图建议可视化卡片）；顶部新增「开始 AI 评分」按钮和费用追踪条
- **AI 评分确认弹窗**：开始评分前弹出预估信息和模型选择
- **AI 修图建议卡片**（右栏内嵌，非独立页面）：裁切预览 + 调整滑块 + HSL + 局部建议 + 中文修图思路
- **设置页 - AI 模型 Tab**：模型列表（增删改）、单模型详情（Endpoint / Key / Model ID / Role / 并发 / 单价）、连接测试、策略选择、费用阈值
- **费用预警弹窗**：达到阈值时阻断式弹出

## 6. 每页核心任务

### 选片工作区

- 页面目标：基于 AI 评分高效完成照片决策；对中意照片获取修图思路
- 主操作：开始评分 → 查看右栏五维子分 → P / X / U 决策 → 选中后请求修图建议
- 次操作：在右栏看 AI 评语；切换评分来源（本地 / 云端）；查看费用进度

### AI 评分确认弹窗

- 页面目标：让用户在花钱前看清"会花多少 / 用什么模型"
- 主操作：选模型组合（按当前策略默认） → 确认开始
- 次操作：调整 maxConcurrency；切换策略；查看每张预估 token 数

### AI 修图建议卡片

- 页面目标：把 LLM 返回的非结构化建议**翻译成可视化的修图参数**，让用户看完就知道怎么调
- 主操作：查看裁切预览框 + 关键调整滑块（曝光 / 对比度 / 高光 / 阴影 / 色温 / 饱和度）+ HSL 色块
- 次操作：复制修图思路文本（中文 narrative）

### 设置页 - AI 模型 Tab

- 页面目标：让用户配置自己拥有的模型，并选评分策略
- 主操作：添加模型（OpenAI 兼容 / Gemini / Claude 三选一）→ 填 Endpoint / Key / Model ID → 测试连接
- 次操作：设置费用阈值；调整并发数；切换默认策略；删除模型

## 7. 关键交互规则

- 默认进入时展示什么：选片右栏默认展示 EXIF + 现有评分（本地或云端 whichever 最新）；未配置任何模型时，AI 增强区块显示「去设置」入口
- 主按钮点击后发生什么：「开始 AI 评分」点击 → 二次确认弹窗 → 后台批量任务，顶部进度条；不阻塞用户继续选片
- 返回逻辑是什么：评分进行中关闭 App / 切换 session 时，任务在后台继续；下次打开同 session 显示「评分中」状态
- 什么时候自动保存：每个 PhotoGroup 评分返回后立即写入 manifest（断点续传）；修图建议同理
- 什么时候要二次确认：每次开始批量评分前（显示费用预估）；超费用阈值时；删除模型配置时
- 什么时候给提示：评分中网络失败时（指数退避 3 次后跳过该组并标记）；本地 / 云端评分冲突时（默认云端覆盖本地，但保留 issues 标签）；API Key 测试失败时

## 8. 状态设计

- 默认状态：右栏 AI 增强区块显示「云端评分未启用 / 已配置 N 个模型 / 策略：xxx」
- 空状态：未配置任何模型 → 显示「前往设置添加 Gemini / GPT / Claude API Key」+ 一键跳转
- 加载状态：顶部细线进度条 + 当前模型名 + 已完成 / 总数 + 已花费 $ ；单张修图建议加载时右栏区块显示 spinner
- 成功状态：评分完成时 toast 提示 + Session 列表标记 ✓；修图建议返回时右栏直接展开卡片
- 失败状态：API 错误（key 无效 / 网络断 / 模型限速）→ 右栏显示具体原因 + 重试按钮；指数退避 3 次后跳过的组在卡片上显示「未评分（点击重试）」
- 异常状态：返回 JSON 解析失败 → 该组标记为「评分异常」，不写入 manifest；用户可在右栏一键重试

## 9. 数据与对象

- 核心对象：
  - `**ModelConfig`**（新）— UUID / 协议 / endpoint / Keychain 引用 / Model ID / Role / 并发 / 单价 / isActive
  - `**AIScore`**（已有，V2 增加 `provider` / `comment` / `recommended` 实际写入）
  - `**EditSuggestions**`（已有但未填充，V2 实际写入）
  - `**ScoringStrategy**`（新）— `.local` / `.balanced` / `.best`
  - `**BudgetTracker**`（新）— 当前批次累计 token / USD / 阈值
- 对象间关系：
  - `ModelConfig.role = .primary` 用于全量评分；`.premiumFallback` 用于 Top 20% 精评 + 修图建议
  - `MediaAsset.aiScore` 由 primary 模型填充，`.editSuggestions` 由 premiumFallback 模型填充
  - `PhotoGroup.recommendedAssets` 由 group_best 字段填充
- 用户会修改哪些内容：模型配置（增删改）、策略选择、费用阈值、对单张照片重新触发修图建议
- 哪些状态需要持久化：
  - `ModelConfig` 列表 → UserDefaults（key 走 Keychain）
  - `AIScore` / `EditSuggestions` → manifest.json（同 session 持久化）
  - `BudgetTracker` 累计值 → 每批次开始时清零，结束时写入 session 元数据用于追踪
  - `ScoringStrategy` → UserDefaults

## 10. 非目标范围

- 这版明确不解决什么：修图建议落地到 XMP / Photos 描述、AI 组名、视频归档增强、多语言、流式响应、AirDrop / Downloads 监控
- 评分膨胀问题已通过 **方案 A：Prompt anchoring**（5 段分布锚点 + 严格基调 + 相对评分约束）在 V2 内消化；详细背景与 V3 候选方案见 `docs/V2/AI Scoring Workflow.md` § 10
- 哪些想法先不做：本地大模型（Ollama）首版只列在 `.openAICompatible` 协议下，不做特殊优化；评分批量提示词的 A/B 调优；自定义 Prompt 模板（默认两套 Prompt 写死）；模型间评分一致性归一化（μ/σ 线性映射 = 方案 B，放 V3）

## 11. 验收标准

- 用户能在设置中添加至少一个 OpenAI 兼容 / Gemini / Claude 模型并通过连接测试
- 启动批量评分后，500 张照片的 session 在 5 分钟内完成并写入 manifest（取决于模型并发与速率限制）
- 评分中可继续选片，UI 不冻结
- 评分完成后右栏五维子分 / 总分 / 评语正确显示，标注「云端 / 本地」来源
- 单张修图建议返回后，右栏可视化展示裁切框 + 至少 5 项调整滑块 + HSL 色块 + 中文 narrative
- 三档策略均能选择并按预期工作（省钱不发起任何云端调用）
- 超费用阈值时弹窗暂停，继续 / 取消生效
- 网络失败 → 重试 → 跳过 → 重试 全链路通畅，session 不损坏
- API Key 始终通过 Keychain 存取，UserDefaults 无明文 key
- 所有新功能有对应单测；ResponseNormalizer 三种协议格式有独立测试
- V2 合约测试 `./scripts/run-v2-contract-tests.sh` 通过（首次创建）
- 不引入新的重型外部依赖（HTTP 走 URLSession，JSON 走 Codable，Keychain 走 Security framework）