# V2 架构设计

# 一、背景

Luma MVP / V1 已跑通「多源导入 → 智能分组 → **本地** Core ML 评分 → 选片 → 导出 / 归档」闭环。本地评分擅长识别废片（模糊 / 过曝 / 闭眼），但无法对"好片"做主观审美评价，也给不出修图建议。V2 引入云端 AI 管线作为主线：用户自带 OpenAI 兼容 / Gemini / Claude 模型 API Key，按 PhotoGroup 批量打分（5 维 + 总分 + 推荐 + 中文评语），并对中意照片单张精评返回结构化修图建议（裁切 / 曝光 / HSL / 局部）。本地评分继续保留作为 Phase A 初筛，云端是 Phase B 增强；二者解耦，用户可在「省钱 / 均衡 / 最佳质量」三档间切换。

# 二、目标

**功能目标**
- **VisionModelProvider 协议**：抽象三种 API 协议（OpenAI 兼容 / Gemini / Anthropic），上层调用方无感知
- **ModelConfig 持久化**：UserDefaults 存配置元信息，Keychain 单独存 API Key
- **批量组评 + 单张精评**两条 Prompt 路径，均返回严格 JSON
- **BatchScheduler**：按 PhotoGroup 打包、并发控制、指数退避、token / 美元计费、超阈值阻断
- **三档策略**：用 `ModelRole` 区分 primary / premiumFallback，组合出三档不同的开销曲线

**架构目标**
- **网络层 0 新依赖**：HTTP = URLSession，JSON = Codable，Keychain = Security framework，OAuth 不需要
- **数据流向**：评分结果通过 `ProjectStore` 写回 manifest，与 V1 已有的 `MediaAsset.aiScore` / `editSuggestions` 字段对齐，**不改 schema**
- **断点续传**：每个 PhotoGroup 完成后即刻写盘；中途崩溃 / 退出后下次进入 session 自动接续未完成的组
- **可测性**：协议层用真实 HTTP fixture 文件做集成测试；ResponseNormalizer 三协议格式各自有解析单测；Keychain 用 in-memory mock 跑 CI
- **性能**：500 张照片（按 80 组打包，每组 6 张）在 Gemini Flash + 4 并发下 < 5 分钟完成；评分进行中 UI 60fps

# 三、架构设计

## 3.1 整体分层（V2 变更标注）

```
┌──────────────────────────────────────────────────────────────┐
│  Views (SwiftUI / AppKit)                                    │
│  ┌──────────────┐ ┌─────────────┐ ┌─────────────────────┐    │
│  │ Culling      │ │ Scoring     │ │ Settings - AIModels │    │
│  │ Workspace    │ │ Confirm     │ │ Tab ★               │    │
│  │ ★ AI 增强    │ │ Sheet ★     │ │                     │    │
│  │   区块       │ │             │ │                     │    │
│  │ ★ 修图建议   │ │             │ │                     │    │
│  │   卡片       │ │             │ │                     │    │
│  │ ★ 顶部费用   │ │             │ │                     │    │
│  │   进度条     │ │             │ │                     │    │
│  └──────┬───────┘ └──────┬──────┘ └──────────┬──────────┘    │
│         │                │                    │              │
│  ┌──────┴────────────────┴────────────────────┴──────┐       │
│  │            ProjectStore (@Observable)             │       │
│  │  ★ startCloudScoring(strategy:)                  │       │
│  │  ★ requestEditSuggestions(assetID:)              │       │
│  │  ★ updateAIScore / updateEditSuggestions         │       │
│  └──────┬────────────────┬────────────────────┬─────┘        │
├─────────┼────────────────┼────────────────────┼──────────────┤
│  Services / AI ★（V2 新增子层）                               │
│  ┌──────────────────────────────────────────────────────┐    │
│  │  CloudScoringCoordinator ★                           │    │
│  │   ├─ BatchScheduler  (并发/重试/计费)               │    │
│  │   ├─ BudgetTracker   (token×单价 → 美元)             │    │
│  │   └─ ScoringStrategy (local / balanced / best)       │    │
│  └─────────────────────┬────────────────────────────────┘    │
│                        │                                     │
│  ┌─────────────────────┴────────────────────────────────┐    │
│  │  VisionModelProvider 协议  ★                         │    │
│  │   ├─ OpenAICompatibleProvider   (GPT-4o, DeepSeek...)│    │
│  │   ├─ GoogleGeminiProvider                            │    │
│  │   └─ AnthropicMessagesProvider                       │    │
│  └─────────────────────┬────────────────────────────────┘    │
│                        │                                     │
│  ┌─────────────────────┴────────────────────────────────┐    │
│  │  ResponseNormalizer ★ (统一三协议响应 → JSON)        │    │
│  │  PromptBuilder ★ (两套 Prompt：组评 / 单张精评)      │    │
│  │  ImagePayloadBuilder ★ (JPEG@1024px×85% → base64)    │    │
│  └─────────────────────┬────────────────────────────────┘    │
│                        │                                     │
│  ┌─────────────────────┴────────────────────────────────┐    │
│  │  HTTPClient (URLSession)  ModelConfigStore           │    │
│  │                            ├─ UserDefaults           │    │
│  │                            └─ Keychain ★             │    │
│  └──────────────────────────────────────────────────────┘    │
├──────────────────────────────────────────────────────────────┤
│  Existing: GroupingEngine / LocalMLScorer / ImportManager    │
│  (V1 已稳定，V2 不动)                                        │
├──────────────────────────────────────────────────────────────┤
│  Models                                                      │
│  ★ ModelConfig / ModelRole / APIProtocol                     │
│  ★ ScoringStrategy / BudgetSnapshot                          │
│  ★ GroupScoreResult / DetailedAnalysisResult                 │
│    AIScore / EditSuggestions / PhotoScores (已有，V2 实际填充)│
└──────────────────────────────────────────────────────────────┘
```

★ = V2 新增

## 3.2 模块详细设计

### F1 VisionModelProvider 协议

**位置**：`Sources/Luma/Services/AI/VisionModelProvider.swift`

```swift
protocol VisionModelProvider {
    var id: String { get }
    var displayName: String { get }
    var apiProtocol: APIProtocol { get }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult
    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult
    func testConnection() async throws -> Bool
}

enum APIProtocol: String, Codable {
    case openAICompatible
    case googleGemini
    case anthropicMessages
}

struct GroupScoreResult: Codable {
    let perPhoto: [PerPhotoScore]    // index → 5维 + overall + comment + recommended
    let groupBest: [Int]              // 推荐 index
    let groupComment: String
    let usage: TokenUsage             // input / output token
}

struct DetailedAnalysisResult: Codable {
    let crop: CropSuggestion?
    let filterStyle: FilterSuggestion?
    let adjustments: AdjustmentValues?
    let hsl: [HSLAdjustment]?
    let localEdits: [LocalEdit]?
    let narrative: String
    let usage: TokenUsage
}
```

三个具体 Provider 实现的差异仅在请求体结构和响应字段路径，统一通过 `ResponseNormalizer` 收敛到同一个 `GroupScoreResult` / `DetailedAnalysisResult`。

### F2 ModelConfigStore（Keychain）

**位置**：`Sources/Luma/Services/AI/ModelConfigStore.swift`

- **UserDefaults**（key=`Luma.aiModels`）存 `[ModelConfig]` JSON，**不含 apiKey 字段**
- **Keychain**（service=`com.luma.aikeys`，account=`<modelID>`）存 API Key，使用 `kSecClassGenericPassword`
- 读取时按 modelID 拼接：UserDefaults JSON + Keychain lookup → 内存中的 `ModelConfig`
- 删除模型时同时清 Keychain 条目（事务性失败仅 log warning，不阻塞）

### F3 BatchScheduler 与并发控制

**位置**：`Sources/Luma/Services/AI/BatchScheduler.swift`

- 输入：`[PhotoGroup]` + `Strategy` + `ModelConfig`
- 内部用 `TaskGroup` + 信号量限制并发数（取自 ModelConfig.maxConcurrency）
- 单组失败：指数退避 3 次（1s / 4s / 16s），最终失败标记该组 `scoringStatus = .failed`，不阻塞其他组
- 每组返回后立刻通过 `ProjectStore.applyGroupScoreResult(_:)` 写盘
- 取消支持：`Task.cancel()` 触发后，正在 in-flight 的请求会等当前 await 结束才退出（不强杀 URLSession 任务）
- 进度回调：每完成一组发布 `ScoringProgressEvent`，UI 顶部进度条订阅

### F4 BudgetTracker

**位置**：`Sources/Luma/Services/AI/BudgetTracker.swift`

- 维护当前批次累计 `inputTokens` / `outputTokens` / `usd`
- 计算：`usd = inputTokens × costPerInputToken + outputTokens × costPerOutputToken`
- 阈值检查在每组返回后触发（不在调用前预扣）
- 超阈值时通过 AsyncStream 通知 UI，UI 调用 `coordinator.pause()` 暂停 BatchScheduler；用户「继续 / 取消」决定后续

### F5 三档策略

**位置**：`Sources/Luma/Services/AI/ScoringStrategy.swift`

```swift
enum ScoringStrategy: String, Codable, CaseIterable {
    case local              // 仅本地 Core ML，不发任何云端请求（与 V1 当前行为一致）
    case balanced           // primary 全量评分 + premiumFallback 仅对 overall ≥ 70 的 Top 20% 精评
    case best               // primary 全量 + premiumFallback 全量精评 + 修图建议
}
```

`balanced` / `best` 时，`Coordinator` 先选第一个 `role == .primary && isActive` 的模型做 group scoring，结束后筛 Top N 给 `role == .premiumFallback` 模型做 detailed analysis。

### F6 PromptBuilder

**位置**：`Sources/Luma/Services/AI/PromptBuilder.swift`

- 两套 Prompt 模板按 `docs/raw/PRODUCT_SPEC.md` 5.4 写死
- 公共约束：System 强制要求「Respond ONLY in JSON. No markdown fences. All comments in 简体中文」
- 输入图像：`ImagePayloadBuilder` 把每张 JPEG/HEIC 缩到长边 1024px、质量 85%、转 base64
- 不在首版做 Prompt 模板用户自定义

### F7 ResponseNormalizer

**位置**：`Sources/Luma/Services/AI/ResponseNormalizer.swift`

- 入参：`(rawJSON: Data, protocol: APIProtocol)`
- 出参：`Result<GroupScoreResult, NormalizerError>`
- 三协议各自的取值路径：
  - OpenAI 兼容：`response.choices[0].message.content` → trim markdown fences → JSONDecoder
  - Gemini：`response.candidates[0].content.parts[0].text` → trim → JSONDecoder
  - Anthropic：`response.content[0].text` → trim → JSONDecoder
- 边界：模型偶发用 ` ```json ... ``` ` 包裹 → 正则去掉；trailing comma → 第二阶段尝试 `JSONSerialization` 容错

### F8 选片右栏 AI 增强 UI

**位置**：`Sources/Luma/Views/Culling/AIEnhancementSection.swift`（新）

- 顶部状态行：「云端评分：未启用 / 进行中 N/M / 已完成」
- 评分卡片：复用 V1 已有的 `AIScoreCardView`，增加左上角小角标显示「云端 ✓」或「本地」
- 修图建议卡片：可视化裁切预览（`Path` 画矩形 + 比例数字）+ 调整滑块（不可拖动，仅展示数值）+ HSL 色块（小圆点矩阵）+ 文本 narrative
- 「生成修图建议」按钮：仅在已配置 premiumFallback 模型时启用

### F9 设置页 - AI 模型 Tab

**位置**：`Sources/Luma/Views/Settings/AIModelsSettingsView.swift`（新）

- 三段式：模型列表 / 单模型详情 / 策略与预算
- 模型列表：左侧 List，每行显示名称 + 协议 + isActive 开关 + Role 下拉
- 详情面板：Endpoint TextField（带预设 placeholder，例如 `https://generativelanguage.googleapis.com`）/ API Key SecureField / Model ID / 单价 / maxConcurrency / 「测试连接」按钮
- 策略与预算：单选三档 + 预算阈值 stepper（默认 5 USD/批次）

## 3.3 关键时序

### 启动批量评分

```
User → CullingWorkspace ─── tap "开始 AI 评分" ──→ ProjectStore
                                                       │
                                                       ▼
                                  CloudScoringCoordinator.start(strategy:)
                                                       │
                              ┌────────────────────────┼─────────────────────────┐
                              ▼                        ▼                         ▼
                       BatchScheduler         BudgetTracker.reset      ProjectStore.session.scoringStatus = .running
                              │
              ┌───────────────┼─────────────── (TaskGroup, maxConcurrency=4) ──────────────┐
              ▼               ▼                              ▼                              ▼
        Group 1            Group 2                       Group 3                        Group N
   PromptBuilder      PromptBuilder                  PromptBuilder                  PromptBuilder
   → POST /chat       → POST /generateContent         → POST /messages              → ...
   → ResponseNorm     → ResponseNorm                  → ResponseNorm
   → applyResult      → applyResult                   → applyResult
                              │
                              ▼
                     manifest.json (per-group flush)
                              │
                              ▼
                 BudgetTracker.update → 超阈值? → pause + AlertSheet
```

### 单张修图建议

```
User → 选片右栏 ── tap "生成修图建议" ──→ ProjectStore.requestEditSuggestions(assetID)
                                                       │
                                                       ▼
                            选择 role==.premiumFallback && isActive 的 ModelConfig
                                                       │
                                                       ▼
                          PromptBuilder.detailedAnalysisPrompt(asset, exif, groupContext)
                                                       │
                                                       ▼
                          provider.detailedAnalysis(image, context)
                                                       │
                                                       ▼
                          ResponseNormalizer → DetailedAnalysisResult
                                                       │
                                                       ▼
                          ProjectStore.updateEditSuggestions(assetID, result)
                                                       │
                                                       ▼
                          AIEnhancementSection 自动刷新（Observable）
```

# 四、评估和验收

## 风险点

| 风险 | 等级 | 缓解 |
|------|------|------|
| 不同模型返回 JSON 格式差异（含 markdown / trailing comma / 字段缺失） | 高 | `ResponseNormalizer` 三段降级解析；`GroupScoreResult` 用 Codable + `decodeIfPresent` 容忍字段缺失；首版禁用 streaming |
| API Key 泄漏 | 高 | UserDefaults 永远不存 key；只走 Keychain；导出 / 备份 manifest 时不带 key |
| 速率限制（Gemini 60 RPM、Anthropic 50 RPM） | 中 | `maxConcurrency` 默认按模型给安全值（Gemini=4 / OpenAI=4 / Anthropic=2）；指数退避捕获 429 |
| 费用失控 | 中 | 每组返回后强制检查阈值；进入批量前必须二次确认弹窗显示预估 |
| Keychain 在 SPM 测试环境不可用 | 中 | `ModelConfigStore` 用协议 + 内存 mock 实现，CI 走 mock；真机走真 Keychain |
| 大批量评分阻塞 UI | 中 | 全程 async / off main actor；评分进度通过 AsyncStream 推到 UI；图片 base64 转码在 background queue |

## 验收 Checklist

- [ ] 用户能添加并通过测试至少一个 Gemini / OpenAI 兼容 / Claude 模型
- [ ] 启动评分后，进度条实时更新；进行中可继续选片，UI 不卡顿
- [ ] 500 张 / 80 组在 Gemini Flash 下 < 5 分钟评分完成
- [ ] 评分结果写入 manifest，重启 App 后仍可见
- [ ] 单张修图建议返回后，右栏可视化卡片正确显示裁切框 + 6+ 项调整滑块 + HSL + 中文 narrative
- [ ] 三档策略：local 不发任何 HTTP 请求；balanced 仅对 Top 20% 触发 detailed；best 全量 detailed
- [ ] 超阈值时弹窗暂停；点「继续」恢复；点「取消」终止并保留已完成部分
- [ ] API Key 仅存 Keychain，UserDefaults / manifest / log 中无明文 key
- [ ] 全量 `swift test` 通过（含 ResponseNormalizer 三协议解析单测、BatchScheduler 重试与取消单测、ModelConfigStore Keychain mock 单测）
- [ ] V2 合约测试 `./scripts/run-v2-contract-tests.sh` 通过（用录制的 fixture 跑端到端）
- [ ] 不引入新的重型外部依赖（HTTP、JSON、Keychain 全部走系统框架）
