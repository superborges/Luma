## 背景

当前要实现的是 AI 增强模块（F6 + F7），目标是解决两个问题：1）不同 AI 模型评分分布不一致（如 Gemini 偏高、Claude 偏低），通过校准归一化让评分跨模型可比；2）分组名称目前用时间+地点规则生成，缺乏语义，通过 AI 分析组内代表照片生成描述性名称。

## 本次只做

- `ScoreCalibrator`：评分校准
  - App bundle 内置 20 张参考照（好 7 / 中 7 / 差 6），覆盖风景/人像/街拍/夜景/微距等场景
  - 调用 `provider.scoreGroup()` 对 20 张评分，收集 overall 数组
  - 计算 μ（均值）和 σ（标准差）
  - 归一化公式：`normalized = 50 + (raw - μ) / σ × 15`
  - 将 `CalibrationResult`（μ/σ/sampleCount）写入 `ModelConfig`
  - 后续该模型返回的所有评分自动经线性映射
- `AIGroupNamer`：AI 组名生成
  - 取组内最多 20 张照片作为代表（覆盖组内不同场景）
  - 构造简短 Prompt：给出当前名称和位置信息，要求返回 ≤ 8 个汉字的描述性名称
  - 用 primary 模型发起单次 API 调用
  - 失败时 fallback 到原有的时间+地点规则名称
  - 生成的名称写入 `PhotoGroup.name` 并持久化到 manifest
- 设置页 - AI 模型 Tab：新增"校准评分"按钮 + 校准状态/结果展示
- `CloudScoringCoordinator` 扩展：评分完成后应用校准映射
- 分组列表 UI：显示 AI 生成的组名（已有样式，仅数据源变化）
- 单测：ScoreCalibrator 归一化公式 / σ < 1 边界 / AIGroupNamer Prompt 构造

## 本次明确不做

- 参考照用户可自定义（固定 App bundle 内置 20 张）
- 校准结果可视化图表（仅显示 μ/σ 数字）
- AI 组名用户可编辑（生成后可手动修改，但本次不做编辑 UI）
- 修改 V2 评分管线核心逻辑（BatchScheduler / BudgetTracker 不动）
- 多模型同时校准（一次校准一个模型）

## 用户主路径

### 校准
1. 用户进入：设置 → AI 模型 Tab → 选择某个模型
2. 用户操作：点击"校准评分"→ 弹窗提示将用 20 张参考照评分（预估费用 ~$0.02）→ 确认
3. 系统反馈：进度条显示 N/20 → 完成后显示 μ / σ 统计
4. 用户完成：该模型后续评分自动归一化

### AI 组名
1. 用户进入：云端评分完成后（或手动触发）
2. 用户操作：自动执行（或点击"生成 AI 组名"按钮）
3. 系统反馈：逐组生成名称 → 分组列表实时更新
4. 用户完成：分组列表显示语义名称

## 页面与组件

- 需要新增的页面：校准确认弹窗（显示预估费用 + 进度）
- 需要新增的组件：`ScoreCalibrator`、`AIGroupNamer`、校准进度 UI、校准结果展示
- 可以复用的组件：`VisionModelProvider`（复用现有评分 API）、`ImagePayloadBuilder`（图片预处理）、`PromptBuilder`（扩展组名 Prompt）、`ModelConfigStore`（写入校准参数）

## 交互要求

- 默认状态：模型详情页显示"未校准"标签 + "校准评分"按钮
- 主按钮行为："校准评分"→ 弹窗确认 → 后台评分 20 张
- 次按钮行为："重新校准"→ 覆盖上次结果
- 返回行为：校准进行中可取消，不保存不完整结果
- 空状态：未校准的模型显示"使用原始评分"提示
- 错误状态：API 调用失败 → 跳过该参考照，≥ 15/20 成功仍可计算；< 15 成功 → 校准失败提示

## UI 要求

- 风格方向：与现有设置页一致
- 必须保留的现有风格：AIModelsSettingsView 三段式布局不变
- 可以自由发挥的范围：模型详情区域增加校准 Section（状态 + 按钮 + μ/σ 显示）
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：复用现有 `VisionModelProvider` / `ImagePayloadBuilder` / `PromptBuilder`
- 状态管理方式：校准结果存入 `ModelConfig`（通过 `ModelConfigStore` 持久化到 UserDefaults）；AI 组名写入 `PhotoGroup.name`（通过 `ProjectStore` 持久化到 manifest）
- 数据先用 mock 还是真接口：校准逻辑用 mock provider 做单测；AI 组名同理
- 不要顺手重构无关模块
- 不要擅自引入新的大型依赖
- 参考照存放在 `Resources/CalibrationPhotos/`（App bundle）
- 归一化公式：`normalized = clamp(0, 100, 50 + (raw - μ) / σ × 15)`
- σ < 1 时跳过归一化并报警告（模型输出无差异）
- AI 组名 Prompt 要求：返回纯文本（非 JSON），≤ 8 个汉字，格式"地点·场景"或"主题·氛围"
- AI 组名对所有组串行调用（避免并发导致费用不可控）

## 输出顺序

1. 先搭 `ScoreCalibrator`（纯计算逻辑 + 单测）
2. 再搭校准 UI（设置页 Section + 确认弹窗 + 进度）
3. 再搭 `AIGroupNamer`（Prompt 构造 + API 调用 + fallback）
4. 再搭 AI 组名集成（CloudScoringCoordinator 完成后触发 / 手动触发）
5. 最后补 `CloudScoringCoordinator` 评分后自动应用校准映射

## 验收标准

- [ ] 设置页模型详情区域显示"校准评分"按钮
- [ ] 点击后弹窗显示预估费用（~$0.02）并确认
- [ ] 校准进度条显示 N/20 完成
- [ ] 校准完成后显示 μ / σ 统计
- [ ] 校准后该模型评分经线性映射（normalized ≈ μ=50, σ=15 分布）
- [ ] σ < 1 时跳过归一化并显示警告
- [ ] 校准参数持久化，重启 App 后仍生效
- [ ] "重新校准"能覆盖旧结果
- [ ] AI 组名生成后分组列表显示语义名称
- [ ] AI 组名失败时 fallback 到时间+地点
- [ ] AI 组名写入 manifest 并持久化
- [ ] 单测覆盖归一化公式（含边界：σ<1 / raw=0 / raw=100）
- [ ] 单测覆盖 AIGroupNamer Prompt 构造
- [ ] 没有大面积改坏 V2 评分管线
