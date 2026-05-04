# Coding Agent Brief — F1 选片右栏增强 + F2 快捷键补齐

## 背景

当前要实现的是选片工作区（`CullingWorkspaceView`）的右栏增强与快捷键补齐，目标是让用户能够在选片时直接看到 AI 评分与废片标签，并通过完整快捷键高效决策。

## 本次只做

- 右栏新增 **AI 评分卡组件**（`AIScoreCardView`）：总分 + 五维子分条 + comment
- 右栏新增 **废片标签组件**（`IssueTagsView`）：读取 `MediaAsset.issues`，展示标签列表
- 快捷键 `U` = 回待定（`markSelection(.pending)`）
- 快捷键 `G` = 切换网格/单张视图模式
- 连拍组内 **「采纳 AI 推荐」** 按钮：将 `subGroup.bestAsset` 设为 Picked，其余设为 Rejected
- AI 推荐照片在连拍视图中有蓝色边框标记

## 本次明确不做

- 不改动 `LocalMLScorer` 评分逻辑（只消费已有数据）
- 不加云端评分
- 不做跨组批量「全部采纳 AI 推荐」
- 不做评分卡展开/收起动画
- 不做雷达图（五维子分用横条即可）

## 用户主路径

1. 用户进入：点击 Session → 选片工作区
2. 用户操作：浏览照片，右栏可见评分与废片标签；按 P/X/U 做决策；按 G 切视图；在连拍组点「采纳推荐」
3. 系统反馈：决策立即标记并跳下一张；推荐采纳后组内状态刷新
4. 用户完成：全部决策完 → 去导出

## 页面与组件

- 需要新增的页面：无
- 需要新增的组件：
  - `AIScoreCardView`：读取 `AIScore`，渲染总分（大号数字+色彩）、五维横条、comment 文案
  - `IssueTagsView`：读取 `[AssetIssue]`，渲染红/橙色小标签
- 可以复用的组件：右栏 EXIF 区域（已有）、`KeyboardShortcutBridge`

## 交互要求

- 默认状态：右栏依次展示 EXIF → AI 评分卡 → 废片标签
- 主按钮行为：P = Pick, X = Reject, U = Pending
- 次按钮行为：G 切视图；连拍组「采纳推荐」
- 返回行为：无需确认，状态已自动保存
- 空状态：无评分时评分卡区域显示「暂无评分」灰色文案
- 错误状态：评分数据异常时显示「评分不可用」，不阻塞选片

## UI 要求

- 风格方向：与现有 `CullingWorkspaceView` 右栏一致（深色背景、紧凑间距）
- 必须保留的现有风格：EXIF 信息卡的样式与位置不变
- 可以自由发挥的范围：评分卡配色（建议绿>70/黄40-70/红<40）
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：SwiftUI，`@Observable` ProjectStore
- 状态管理方式：从 `ProjectStore` 读 `assets[selectedIndex].aiScore` / `.issues`
- 数据先用 mock 还是真接口：真数据（`aiScore` / `issues` 在导入后已由 `LocalMLScorer` 填充）
- 不要顺手重构无关模块
- 不要擅自引入新的大型依赖
- `U` 键复用 `markSelection(.pending)`，不需新接口
- `G` 键需在 `ProjectStore` 或 View 层加一个 `viewMode` toggle

## 输出顺序

1. 先搭 `AIScoreCardView` + `IssueTagsView` 组件
2. 嵌入右栏（EXIF 下方）
3. 补 `U` / `G` 快捷键
4. 实现连拍「采纳推荐」按钮与逻辑
5. 补单测

## 验收标准

- [ ] 右栏可见 AI 总分 + 五维子分 + 废片标签
- [ ] 无评分照片显示灰色占位
- [ ] U 键可将已 Pick/Reject 的照片回退为 Pending
- [ ] G 键可切换网格/单张
- [ ] 连拍组内「采纳推荐」可用，效果正确
- [ ] 没有大面积改坏其他页面
- [ ] 新增组件有基本单测
