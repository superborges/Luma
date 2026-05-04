# Coding Agent Brief — F1 VisionModelProvider 协议 + F2 ModelConfig 持久化

## 背景

当前要实现的是 **AI 基础设施层**，目标是让上层（评分流水线、设置页）能通过统一的 `VisionModelProvider` 协议调用 OpenAI 兼容 / Google Gemini / Anthropic Messages 三种 API，并安全持久化 `ModelConfig`（API Key 走 Keychain）。本 Brief 不涉及任何 UI 或评分流水线，**输出是可在单测中调用 `provider.scoreGroup()` / `provider.detailedAnalysis()` / `provider.testConnection()` 拿到统一结构数据的协议层**。

## 本次只做

- **数据模型**：
  - `APIProtocol`（`.openAICompatible` / `.googleGemini` / `.anthropicMessages`）
  - `ModelConfig`（id / name / apiProtocol / endpoint / modelId / role / maxConcurrency / costPer{Input,Output}Token / isActive）
  - `ModelRole`（`.primary` / `.premiumFallback`）
  - `ImageData`（jpegBase64: String / longEdgePixels: Int / mimeType: String）
  - `GroupContext`（groupName / cameraModel / lensModel / timeRangeDescription）
  - `PhotoContext`（baseName / exif / groupName / overall）
  - `PerPhotoScore`（index / scores: PhotoScores / overall / comment / recommended）
  - `GroupScoreResult`（perPhoto / groupBest: [Int] / groupComment / usage: TokenUsage）
  - `DetailedAnalysisResult`（crop? / filterStyle? / adjustments? / hsl? / localEdits / narrative / usage）
  - `TokenUsage`（inputTokens / outputTokens）
  - `NormalizerError`（`.markdownFenceUnstripped` / `.malformedJSON` / `.missingField(String)` / `.protocolMismatch`）
- **协议层**（`Sources/Luma/Services/AI/VisionModelProvider.swift`）：
  - 主协议 + 默认实现 `BaseProvider` 把通用流程（构造请求、发请求、解析响应、错误归一）抽出来
- **三个 Provider**（`Sources/Luma/Services/AI/Providers/`）：
  - `OpenAICompatibleProvider`：构造 `chat/completions` 请求；图像走 `image_url` data URL
  - `GoogleGeminiProvider`：构造 `:generateContent` 请求；图像走 `inline_data` base64
  - `AnthropicMessagesProvider`：构造 `messages` 请求；图像走 `image.source.base64`
- **PromptBuilder**（`Sources/Luma/Services/AI/PromptBuilder.swift`）：
  - 两套 Prompt 写死，按 `docs/raw/PRODUCT_SPEC.md` § 5.4 的 Prompt 1 / Prompt 2 复刻
  - `groupScoringPrompt(_ context: GroupContext, photoCount: Int) -> (system: String, user: String)`
  - `detailedAnalysisPrompt(_ context: PhotoContext) -> (system: String, user: String)`
- **ResponseNormalizer**（`Sources/Luma/Services/AI/ResponseNormalizer.swift`）：
  - `normalizeGroupScoreResponse(_ data: Data, protocol: APIProtocol) -> Result<GroupScoreResult, NormalizerError>`
  - `normalizeDetailedAnalysisResponse(...)` 同形
  - 三协议各自解析路径 + 通用 markdown fence 剥离 + trailing comma 容错
- **ImagePayloadBuilder**（`Sources/Luma/Services/AI/ImagePayloadBuilder.swift`）：
  - 输入 `MediaAsset` → 解码 preview/raw → 缩放长边 1024px → JPEG 质量 85% → base64
  - 在 background queue；不阻塞主线程
- **HTTPClient 抽象**（`Sources/Luma/Services/AI/HTTPClient.swift`）：
  - 协议 `protocol HTTPClient { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`
  - 默认实现 `URLSessionHTTPClient`
  - 测试用 mock `MockHTTPClient`（接收预设 fixture 文件，验证请求 URL/Header/Body）
- **ModelConfigStore**（`Sources/Luma/Services/AI/ModelConfigStore.swift`）：
  - `protocol ModelConfigStore`：`load() -> [ModelConfig]` / `save([ModelConfig])` / `apiKey(for: modelID) -> String?` / `setAPIKey(_, for: modelID)` / `deleteAPIKey(for: modelID)`
  - 默认实现 `KeychainModelConfigStore`：UserDefaults 存 `[ModelConfig]` JSON（**不含** apiKey），Keychain（service=`com.luma.aikeys`）按 modelID 存 key
  - 测试用 mock `InMemoryModelConfigStore`（CI 用）

## 本次明确不做

- 不做任何 UI（设置页 / 评分按钮 / 修图建议卡片）→ 在 Brief C
- 不做 BatchScheduler / BudgetTracker / Coordinator → 在 Brief B
- 不做 ProjectStore 接入 → 在 Brief B
- 不做评分校准（线性归一化）
- 不做 streaming 响应
- 不做自定义 Prompt 模板
- 不做 token 使用量精确预估（首版按返回的 usage 字段为准）
- 不真打外部 API；CI 用 mock + fixture
- 不动 `LocalMLScorer` / `GroupingEngine` / `ImportManager` 等已稳定的模块

## 用户主路径

本 Brief 不暴露用户路径，仅供上层调用。等价的「开发者路径」：

1. 测试代码：构造 `MockHTTPClient` + 加载 fixture（如 `Tests/Fixtures/gemini_group_score_response.json`）
2. 调用 `GoogleGeminiProvider(client: mockClient).scoreGroup(images: [...], context: ...)`
3. 断言返回的 `GroupScoreResult.perPhoto.count == n`、`groupBest` 不空、`usage.inputTokens > 0`
4. 类似断言三协议、两种 Prompt 路径

## 页面与组件

- 需要新增的页面：**无**
- 需要新增的组件：**无**
- 可以复用的组件：无（这是新建子层）

## 交互要求

- 默认状态：N/A（无 UI）
- 主按钮行为：N/A
- 次按钮行为：N/A
- 返回行为：N/A
- 空状态：`ModelConfigStore.load()` 返回空数组时不报错
- 错误状态：
  - HTTP 4xx/5xx → 抛 `LumaError.aiProvider(code: Int, message: String)`
  - JSON 解析失败 → 抛 `NormalizerError`
  - Keychain 失败（如沙盒拒绝）→ 抛 `LumaError.keychainUnavailable`，UserDefaults 仍保留模型元信息

## UI 要求

N/A（本 Brief 不涉及 UI）

## 技术约束

- 技术栈：Swift 6 / Foundation / Security framework / URLSession，**不引入新依赖**
- 状态管理方式：纯 service 层，无 `@Observable`；ModelConfigStore 是 `actor` 或 `final class` + 内部锁均可
- 数据先用 mock 还是真接口：测试用 fixture（录制真响应 JSON 后剥敏并入库 `Tests/Fixtures/AI/`）；运行时走真 URLSession
- 不要顺手重构无关模块（特别是 `ProjectStore` / `MediaAsset` / `LocalMLScorer`）
- 不要擅自引入新的大型依赖（无 Alamofire / Moya / SwiftKeychainWrapper 等）
- Keychain：用 `Security` framework 原生 API，包装在 `KeychainModelConfigStore` 内部，不暴露 `SecItemAdd` 给上层
- 错误统一走 `LumaError`，不要新建独立错误类型层级（`NormalizerError` 仅 internal）
- API Key 永远不进 UserDefaults / manifest / log；trace 中只记录 modelID（UUID）
- 全部 async / await；不在 main actor 上做网络与 base64 编码

## 输出顺序

1. **数据模型**先（无依赖，可独立编译通过）
2. **PromptBuilder + ImagePayloadBuilder**（无外部依赖）
3. **HTTPClient 协议 + URLSessionHTTPClient + MockHTTPClient**
4. **ResponseNormalizer**（依赖数据模型）
5. **三个 Provider**（依赖前 4 项）
6. **ModelConfigStore**（独立模块）
7. **单测**：
   - `ResponseNormalizerTests`：三协议 × 两种 Prompt = 6 个 fixture 解析路径
   - `PromptBuilderTests`：System/User 内容包含中文约束、JSON-only、关键字段名
   - `ImagePayloadBuilderTests`：长边 1024px 缩放、质量 85%、base64 解码后能复原 CGImage
   - `OpenAICompatibleProviderTests` / `GoogleGeminiProviderTests` / `AnthropicMessagesProviderTests`：构造的 URLRequest 路径 + Header + Body 形状正确
   - `ModelConfigStoreTests`：UserDefaults round-trip 不含 apiKey；Keychain mock 增删查通过

## 验收标准

- [ ] 三个 Provider 单测通过（构造请求 + 解析响应）
- [ ] PromptBuilder 单测验证两套 Prompt 含中文约束 + JSON-only 指令
- [ ] ResponseNormalizer 三协议响应 fixture 解析单测全过
- [ ] ImagePayloadBuilder 输出可解码、长边 ≤ 1024px、JPEG quality 85%
- [ ] ModelConfigStore：UserDefaults JSON 中 **不出现** apiKey 字段；Keychain 增删查通过
- [ ] HTTPClient 抽象层 + Mock 可被三 Provider 共用
- [ ] `swift test` 全量通过（含本次新增测试）
- [ ] 不动 `LocalMLScorer` / `GroupingEngine` / `ImportManager`
- [ ] 没有大面积改坏其他页面（本 Brief 无 UI 改动）
- [ ] 不引入新的外部依赖（`Package.swift` 无新增 `.package`）
