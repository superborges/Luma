# V2 AI 评分工作原理

> 本文档解释 V2 云端 AI 评分的完整工作流，包括 Prompt 设计、图像处理、写入语义、错误处理与已知局限。
>
> 适合在以下情况阅读：
> - 想理解一次「AI 评分」按钮按下后到底发生了什么
> - 调试评分结果不符合预期
> - 设计 V3 评分校准

## 一、触发入口

用户在选片工作区顶部点击 **「AI 评分」** 按钮 → 弹出 `ScoringConfirmSheet` → 确认后调用：

```
ProjectStore.startCloudScoring(strategy: ScoringStrategy)
```

策略由用户在「设置 → AI 模型 Tab」选择，三档：

| 策略 | 行为 | 当前实现状态 |
|------|------|-------------|
| `local` | 不发起任何云端调用 | ✓ 已实现（直接抛 `LumaError.unsupported`） |
| `balanced` | primary 全量 + premiumFallback Top 20% 精评 | ⚠️ V2 仅做 primary 全量；Top 20% 精评由用户在右栏单张点「请求修图建议」手动触发 |
| `best` | primary 全量 + premiumFallback 全量精评 + 修图建议 | ⚠️ 同上 |

> **注**：V2 没有自动触发"全量精评 + 修图建议"，仅 primary 全量评分 + 用户**单张主动**请求修图建议。

## 二、整体数据流

```
用户点 [AI 评分]
    │
    ▼
ProjectStore.startCloudScoring(strategy)
    │
    ├─ ensureCloudScoringCoordinator()
    │   └─ 立即订阅 progressEvents 流，更新 UI 进度条
    │
    ▼
CloudScoringCoordinator.start(...)
    │
    ├─ 1. 选 primary 模型（role == .primary && isActive）
    ├─ 2. 从 Keychain 读 API Key
    ├─ 3. 取消上一批次（如有）
    ├─ 4. 检查 scoring_job.json 是否有未完成任务（断点续传）
    ├─ 5. 监听 BudgetTracker 的阈值跨越事件
    │
    ▼
为每个 PhotoGroup 构造 ScoringTask：
    │
    ├─ 取该组 asset 的 previewURL（最多 8 张）
    ├─ ImagePayloadBuilder：1024px 长边 + JPEG 85% + base64
    ├─ PromptBuilder.groupScoringPrompt(context, photoCount)
    │
    ▼
BatchScheduler.run(tasks: [ScoringTask], onCompleted: ...)
    │
    ├─ TaskGroup + ConcurrencySemaphore（限并发，默认 4）
    ├─ 每组失败：1s → 4s → 16s 退避，最多 3 次
    │
    ▼
provider.scoreGroup(images, context) → GroupScoreResult
    │
    ▼
Coordinator.handleGroupCompleted
    │
    ├─ BudgetTracker.add(usage, cost) → 检查阈值
    ├─ ProjectStore.applyGroupScoreResult(...)
    │   ├─ 写 MediaAsset.aiScore = AIScore(provider: "cloud:...", ...)
    │   ├─ 写 PhotoGroup.recommendedAssets / groupComment
    │   ├─ invalidateAllCachesAfterDirectMutation()
    │   └─ persistManifestNow() → manifest.json
    │
    └─ scoring_job.json 更新单组状态为 .completed
```

完成所有组后：`Coordinator.finalizeIfDone()` 把 `ScoringJob.status = .completed`，UI 进度条变绿。

## 三、Prompt 设计（写死，不开放运行时自定义）

### Prompt 1：组内批量评分（`PromptBuilder.groupScoringPrompt`）

**System**：
```
You are a professional photo editor evaluating a group of similar photos
taken at the same scene. Score each photo and recommend the best ones.
Respond ONLY in JSON format. No markdown fences, no preamble.
All comment / group_comment fields must be in Chinese (简体中文).
```

**User**（伪结构）：
```
Here are {N} photos from scene: "{groupName}".
Camera: {cameraModel} | Lens: {lensModel} | Time range: {timeRange}

Return JSON:
{
  "photos": [
    {
      "index": 1,
      "scores": {
        "composition": 0-100,
        "exposure": 0-100,
        "color": 0-100,
        "sharpness": 0-100,
        "story": 0-100
      },
      "overall": 0-100,
      "comment": "一句话中文评价",
      "recommended": true
    }
  ],
  "group_best": [1, 5],
  "group_comment": "整组中文点评"
}

Index starts from 1 and matches the order of attached images.
```

### Prompt 2：单张精评 + 修图建议（`PromptBuilder.detailedAnalysisPrompt`）

**System**：
```
You are a master photographer and retouching expert. Analyze this photo
and provide detailed editing suggestions with specific values.
Respond ONLY in JSON format. No markdown fences, no preamble.
All text fields (direction, mood, area, action, narrative) must be in Chinese.
```

**User**（伪结构）：
```
Photo: {baseName} | EXIF: {aperture}, {shutter}, ISO {iso}, {focalLength}mm
Scene: {groupName} | Initial score: {overall}/100

Return JSON: {
  "crop": {needed, ratio, direction, rule, top/bottom/left/right},
  "filter_style": {primary, reference, mood},
  "adjustments": {exposure -3..+3, contrast/highlights/shadows... -100..+100},
  "hsl": [{color, hue, saturation, luminance}],
  "local_edits": [{area, action}],
  "narrative": "完整修图思路，2-3 句中文"
}
```

> **关键约束**：仅 `index` / `scores` / `overall` 是必填字段。其他字段（`comment` / `recommended` / `group_best` / `group_comment`）模型偶发漏掉时由 `ResponseNormalizer` 补默认值（避免一组评分被丢弃）。

## 四、图像预处理（`ImagePayloadBuilder`）

| 参数 | 当前值 | 备注 |
|------|--------|------|
| 长边 | **1024px** | StepFun 文档推荐 1280px (low) / 2688px (high) — 我们略保守 |
| JPEG 质量 | **85%** | 比 StepFun 推荐的 80% 略高 |
| 编码格式 | **JPEG** | 输出不带 alpha 通道，避免 PNG 透明被解读为黑色 |
| 编码 | **base64** | 通过 data URL（OpenAI 兼容 / Anthropic）或 `inline_data`（Gemini） |
| 单组图像数 | **≤ 8** | `prefix(8)`；防止 token 烧爆，且 ≤ 协议限制（StepFun 50/Anthropic 5MB/单图） |

每张图压缩后约 80–200KB（base64 后 ~110–280KB）。

## 五、三种 API 协议适配

每个 Provider 实现 `VisionModelProvider` 协议，统一返回 `GroupScoreResult` / `DetailedAnalysisResult`。

### `OpenAICompatibleProvider`
- 兼容：OpenAI / DeepSeek / 阶跃星辰 StepFun / 智谱 / 通义 / Together AI / Ollama
- 请求：`POST {endpoint}/chat/completions`
- 鉴权：`Authorization: Bearer {key}`
- 多模态：`messages[].content` 为数组，每张图 `{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,..."}}`
- 注：**不发送 `response_format: json_object`**（Ollama 等不支持）；JSON-only 由 system prompt 强约束

### `GoogleGeminiProvider`
- 请求：`POST {endpoint}/v1beta/models/{modelID}:generateContent?key={apiKey}`
- 鉴权：URL query string `?key=...`
- 多模态：`contents[].parts` 为数组，图像 `{"inline_data":{"mime_type":"image/jpeg","data":"<base64>"}}`
- 系统消息：合并到 user message 头部（Gemini 没有独立 system role）
- `responseMimeType: application/json` 让模型默认返回 JSON

### `AnthropicMessagesProvider`
- 请求：`POST {endpoint}/messages`
- 鉴权：`x-api-key: {key}` + `anthropic-version: 2023-06-01`
- 多模态：`messages[0].content` 为数组，每张图 `{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"..."}}`
- `max_tokens: 2048`（足够 group score ~1500 token，避免 Haiku 等小模型上限）
- `system` 字段独立传入

### `ResponseNormalizer` 三协议归一化

输入 HTTP body → 输出 `GroupScoreResult`，路径：

| 协议 | 模型生成 JSON 的字段路径 | Token 用量字段 |
|------|------------------------|---------------|
| OpenAI 兼容 | `choices[0].message.content` | `usage.{prompt_tokens, completion_tokens}` |
| Gemini | `candidates[0].content.parts[0].text` | `usageMetadata.{promptTokenCount, candidatesTokenCount}` |
| Anthropic | `content[0].text` | `usage.{input_tokens, output_tokens}` |

提取 `content` 字符串后：剥离 markdown fence (`` ```json ... ``` ``) → JSON 解码到 `RawGroupScore`（snake_case 自动转 camelCase）。

## 六、评分写入语义（`ProjectStore.applyGroupScoreResult`）

### `MediaAsset.aiScore`

```swift
AIScore(
    provider: "cloud:openAICompatible:step-1o-turbo-vision",  // 或 "cloud:googleGemini:gemini-2.0-flash" / "local-heuristic"
    scores: PhotoScores(composition: ..., exposure: ..., color: ..., sharpness: ..., story: ...),
    overall: 0-100,
    comment: "一句话中文评价",
    recommended: true,
    timestamp: Date
)
```

### Provider 字符串约定

| 前缀 | 来源 | UI 角标 |
|------|------|---------|
| `cloud:<protocol>:<modelID>` | 云端 V2 评分 | 「云端」（StitchTheme.primary 蓝色） |
| `local-heuristic` 等其他 | 本地 Core ML（V1） | 「本地」（灰色） |

`AIScoreCardView.sourceBadge` 通过 `provider.hasPrefix("cloud:")` 判别。

### `PhotoGroup.recommendedAssets` / `groupComment`

`group_best` 是 **1-based 索引**（与 prompt 中 "Index starts from 1" 对齐）。`applyGroupScoreResult` 把每个索引 `−1` 映射成 `assetIDs[zeroBased]` 写入 `recommendedAssets`。越界保护：超出 group asset 数量的索引被丢弃。

### 与本地 issues 的关系

云端评分**覆盖** `aiScore` 字段，但**保留** `issues`（本地 Core ML 已识别的"模糊 / 过曝 / 闭眼"标签）。即：

- 云端可能给一张闭眼照打 75 分
- 但 `issues` 仍含 `.eyesClosed`，右栏 IssueTagsView 仍显示"面部异常"标签

## 七、错误处理与重试（`BatchScheduler.runWithRetry`）

```
1st attempt fails → wait 1s
2nd attempt fails → wait 4s
3rd attempt fails → wait 16s
4th attempt fails → 该组标记 .failed，但不影响其他组继续
```

### 哪些错误码会重试

| HTTP 状态 | 是否重试 | 备注 |
|-----------|---------|------|
| 408（请求超时） | ✓ | 短暂网络问题 |
| 429（限速） | ✓ | 应降低 maxConcurrency |
| 5xx | ✓ | 服务端故障 |
| 401（鉴权失败） | ✗ | API Key 无效 → 重试无意义 |
| 403（权限不足） | ✗ | 同上 |
| 404（model 不存在） | ✗ | 配置错误 |
| 400（请求格式错误） | ✗ | 通常是模型不支持视觉 |

### 用户能看到的诊断信息（`ProviderHTTPSupport.humanReadableMessage`）

- `image_url` / `unknown variant` 关键字 → "该模型不支持视觉输入"
- 401 → "API Key 无效或已过期"
- 404 → "Model ID 不存在或 endpoint 错误：{服务端原始消息摘要}"
- 429 → "触发限速；请稍后再试或调低并发"
- 其他：状态码前缀 + 服务端 `error.message` 字段（最多 240 字符）

## 八、费用追踪（`BudgetTracker`）

actor 类型，线程安全：

```swift
inputTokens, outputTokens, usd  // 累加
thresholdUSD                    // 由用户在设置页配置（默认 5 USD）
```

每组 API 返回后：
```swift
cost = usage.inputTokens / 1_000_000 × ModelConfig.costPerInputTokenUSD
     + usage.outputTokens / 1_000_000 × ModelConfig.costPerOutputTokenUSD
budget.add(usage, cost)
```

如果累计 USD 跨过阈值（首次跨过仅触发一次），通过 `thresholdCrossedStream` 推送 `BudgetSnapshot`，Coordinator 收到后：
1. 取消所有未完成的组
2. 把 ScoringJob.status 标记为 `.paused`
3. UI 弹出 `BudgetExceededSheet`，要求用户**调高阈值**才能继续

## 九、断点续传（`ScoringJobStore`）

`<projectDir>/scoring_job.json` 跟随 manifest 同目录：

```json
{
  "id": "...",
  "strategy": "balanced",
  "primaryModelID": "...",
  "totalGroups": 5,
  "status": "running",
  "groupStatuses": {
    "<group-uuid-1>": "completed",
    "<group-uuid-2>": "running",
    "<group-uuid-3>": "pending"
  },
  "budget": { "inputTokens": 1500, "outputTokens": 400, "usd": 0.012, "thresholdUSD": 5.0 }
}
```

**重启 App / 切换 session 后**：`Coordinator.start` 会检测 `scoring_job.json`，若 `strategy + primaryModelID` 一致且 `status != .completed`，则：
1. 复用 BudgetTracker 累计值（不清零，避免再次触发阈值）
2. 把 `running` 状态降级回 `pending`（重启意味着重做）
3. 仅给"未完成"的组准备 ScoringTask 并继续

## 十、评分校准：现状与未来方向

### ✅ 方案 A：Prompt Anchoring（已落地，2026-05）

**问题**：早期用户反馈大相册里照片得分都在 80+，缺乏区分度（评分膨胀 / score inflation）。

**根因**：
1. 缺乏 anchoring：早期 prompt 只说"score 0-100"，没告诉模型分布锚点。LLM 在无参考样本时倾向给"礼貌评分"，集中在 70-90 区间
2. 模型评分尺度不一：GPT-4o 偏严格、StepFun 偏宽松、Gemini 居中
3. 没有相对评分约束：单组独立评分，模型不知道整批水平
4. 过于宽容的 prompt："professional photo editor" 暗示职业评价，偏宽松

**已实施改动**（`PromptBuilder.groupScoringPrompt` system 部分）：

| 维度 | 改动 |
|------|------|
| 基调 | "professional editor" → "STRICT and CRITICAL" + "RANK and FILTER, not polite encouragement" |
| 分布锚点 | 5 段明确语义 + 比例（90-100 = TOP 3-5% / 75-89 ~20-30% / 60-74 = most snapshots / 40-59 = mediocre / 0-39 = reject） |
| 拒绝扎堆 | "DO NOT cluster all scores in 70-85" |
| 强制相对评分 | "Same group: scores should DIFFER by 5-10 points" |
| 限制 recommended | "AT MOST 1-2 photos per group of 5+" |
| 评语风格 | "comment should be honest — point out specific flaws, not generic praise" |

**实测效果**（StepFun `step-1o-turbo-vision` + 大相册）：
- 评分中位数从 ~80 降到 ~65-70 ✓
- 同组内评分差异变明显（不再扎堆 80-85）✓
- `recommended` 标记数量减少 ✓
- comment 更具体——指出具体问题而非泛泛而谈 ✓

**契约保护**：`PromptBuilderTests.testGroupScoringPromptIncludesScoreDistributionAnchors` 把 5 段锚点 + 关键约束词作为契约固定，prompt 误改会立即测试报错。

### V3 后续可选改进（未实施）

#### B. 校准机制（PRD 中提及）

首次配置模型时让用户标注 20 张参考照片（5 顶级 / 10 中等 / 5 烂片），跑一次模型记录该模型的「评分均值与标准差」，后续用线性映射归一化：

```
calibrated_overall = (raw_overall - μ_model) / σ_model × 15 + 70
```

每个模型存自己的 μ / σ，切换模型时评分仍然可比。**适用场景**：用户在 OpenAI / Gemini / StepFun 间切换且对评分一致性有要求。

#### C. 相对评分约束（更激进，未推荐）

prompt 增加："Among these N photos, exactly K should score 90+, exactly M should score < 60"。强制相对排序而非绝对评分。

**风险**：可能把烂组里"最不烂"的也打 90 分；约束硬编码导致某些场景失真。**当前 A 方案的"DIFFER by 5-10 points"已经是软约束版本**，无需再激进。

#### D. 多模型投票（最贵）

对每张照片用 2-3 个模型评分取均值。**收益边际**：评分稳定性提升，但成本翻倍。**适用场景**：评审重要赛事 / 商业项目，平时不必。

### 推荐改进路径

```
✅ V2 已发: 方案 A — Prompt anchoring (10 行改动，零成本)
                 ↓
🔄 V3 候选: 方案 B — 校准 UI + μ/σ 归一化 (中等工作量)
                 ↓
⏸️ 待定:  方案 D — 多模型投票 (高成本，按需)
                 ↓
❌ 不推荐: 方案 C — 硬性相对评分约束 (副作用大)
```

### 其他局限

| 局限 | 影响 | 备选方案 |
|------|------|---------|
| `balanced` / `best` 策略未自动触发精评 | 用户必须手动点单张「请求修图建议」 | V3 实现批量精评 |
| 评分中切换 session，进度条不会跨 session 持续显示 | 单 session 视图 | UI 改造，把进度条提到全局 |
| 单组最多 8 张（`prefix(8)` 硬编码） | 大组只评前 8 张 | 配置化或拆 sub-batch |
| 没有评分历史 | 重新跑评分会覆盖 | manifest 存 `aiScoreHistory: [AIScore]` |
| Token 计费依赖用户填写单价 | 单价填错 → BudgetTracker 不准 | 内置常见模型价格表 |

## 十一、文件位置（代码索引）

| 模块 | 路径 |
|------|------|
| 协议定义 | `Sources/Luma/Services/AI/VisionModelProvider.swift` |
| 三 Provider | `Sources/Luma/Services/AI/Providers/{OpenAICompatible,GoogleGemini,AnthropicMessages}Provider.swift` |
| Prompt 模板 | `Sources/Luma/Services/AI/PromptBuilder.swift` |
| 图像处理 | `Sources/Luma/Services/AI/ImagePayloadBuilder.swift` |
| HTTP 抽象 | `Sources/Luma/Services/AI/HTTPClient.swift` |
| 响应归一化 | `Sources/Luma/Services/AI/ResponseNormalizer.swift` |
| 调度 | `Sources/Luma/Services/AI/BatchScheduler.swift` |
| 编排 | `Sources/Luma/Services/AI/CloudScoringCoordinator.swift` |
| 费用 | `Sources/Luma/Services/AI/BudgetTracker.swift` |
| 任务持久化 | `Sources/Luma/Services/AI/ScoringJobStore.swift` |
| 配置存储 | `Sources/Luma/Services/AI/ModelConfigStore.swift` |
| ProjectStore 接入 | `Sources/Luma/App/ProjectStore+CloudScoring.swift` |
| 修图建议接入 | `Sources/Luma/App/ProjectStore+EditSuggestions.swift` |
| 设置页 UI | `Sources/Luma/Views/Settings/AIModelsSettingsView.swift` |
| 评分进度条 | `Sources/Luma/Views/Culling/ScoringProgressBar.swift` |
| 确认弹窗 | `Sources/Luma/Views/Culling/ScoringConfirmSheet.swift` |
| 修图建议卡片 | `Sources/Luma/Views/Culling/EditSuggestionsCard.swift` |
| AI 增强区块 | `Sources/Luma/Views/Culling/AIEnhancementSection.swift` |
