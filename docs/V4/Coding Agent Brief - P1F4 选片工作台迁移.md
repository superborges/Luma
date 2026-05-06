## 背景

当前要实现的是 V4 Phase 1 的选片工作台迁移（P1F4），目标是将 `CullingWorkspaceView` 从基于 `Session`/`MediaAsset` 的旧模型迁移到基于 `Expedition`/`MasterAsset`/`ExpeditionAsset` 的新模型。选片状态（Decision）从 `MediaAsset.userDecision` 迁移到 `ExpeditionAsset.decision`，所有分组/评分/推荐逻辑与 Expedition 上下文关联。

**前置依赖**：P1F1（数据层）+ P1F2（Expedition/资产管理）+ P1F3（导入流程）已完成。

## 本次只做

- **`ExpeditionWorkspaceStore`**（替代 `ProjectStore` 的选片相关状态）：
  - 持有当前 Expedition 上下文
  - `currentExpedition: Expedition?`
  - `expeditionAssets: [ExpeditionAssetWithMaster]`（联合查询：ExpeditionAsset + MasterAsset）
  - `groups: [PhotoGroupWithAssets]`（PhotoGroup + 组内资产详情）
  - `selectedGroupId: UUID?`
  - `selectedAssetId: UUID?`
  - `visibleAssets: [ExpeditionAssetWithMaster]`（按当前选中组/筛选条件过滤）
  - 方法：
    - `openExpedition(id:)`：加载 Expedition 数据
    - `closeExpedition()`
    - `selectGroup(id:)`
    - `selectAsset(id:)`
    - `setDecision(assetId:decision:)`→ 调用 `AssetManager.setDecision`
    - `setRating(assetId:rating:)`
    - `togglePicked(assetId:)`
    - `selectAllPhotosOverview()`
    - `applyAIRecommendations(groupId:)`
    - `refreshGroups()`
    - `triggerLocalScoring()`
    - `triggerCloudScoring(strategy:)`
- **联合查询类型**：
  - `ExpeditionAssetWithMaster`：包含 `ExpeditionAsset` + `MasterAsset`（用于 UI 展示需要两者的场景）
  - `PhotoGroupWithAssets`：包含 `PhotoGroup` + 组内 `[ExpeditionAssetWithMaster]`
- **`CullingWorkspaceView` 重构**：
  - 数据源从 `store.assets` / `store.groups` 改为 `workspaceStore.expeditionAssets` / `workspaceStore.groups`
  - 决策操作从 `store.updateDecision(assetID:decision:)` 改为 `workspaceStore.setDecision(assetId:decision:)`
  - 评分展示从 `asset.aiScore` 改为通过 `AssetScoreRepository` 查询
  - 左侧 Smart Groups 从 `store.groups` 改为 `workspaceStore.groups`
  - 右侧 EXIF/AI 卡片从 `MediaAsset` 属性改为 `MasterAsset` + `ExpeditionAsset` 组合
  - 底部操作栏的已选/未选/待定计数改为查询 `ExpeditionAssetRepository.fetchByExpeditionAndDecision`
- **Expedition 内导航侧栏**（左栏新增项）：
  ```text
  当前旅程
    全部照片
    AI 推荐（decision == .pending && isRecommended）
    已选（decision == .picked）
    未选（decision == .rejected）
    未审（decision == .pending）
    可清理（issues 非空 || 低分）
  
  分组
    清水寺日落
    伏见稻荷
    京都街拍
  ```
- **适配评分服务**：
  - `LocalMLScorer.score(_:)` 输入从 `MediaAsset` 改为 `MasterAsset`
  - `CloudScoringCoordinator.start(...)` 的 `assets` 参数从 `[MediaAsset]` 改为 `[MasterAsset]`
  - 评分结果写入 `AssetScoreRepository`（SQLite），不再写入 `MediaAsset.aiScore`
  - `ExpeditionAssetWithMaster` 提供 `latestScore: AIScore?` 计算属性（从 DB 查询）
- **适配分组服务**：
  - `GroupingEngine.makeGroups` 的结果写入 `PhotoGroupRepository`（SQLite）
  - 分组操作通过 `PhotoGroupRepository` 实现
- **分组编辑操作**（对应 Product Spec §6.5）：
  - **合并相邻组**：选中多个组 → 合并为一个组，保留第一个组的名称，资产合并
  - **拆分组**：在组内选中部分照片 → 拆出为新组
  - **从组中移除照片**：将照片从当前组移除（照片变为未分组状态）
  - **移动照片到另一组**：选中照片 → 拖拽或菜单选择目标组 → 移动
  - **重命名组**：双击组名或右键菜单 → 编辑组名
  - **设定组封面**：右键照片 → 「设为封面」，更新 `PhotoGroup.coverAssetId`
  - 所有分组编辑只影响当前 Expedition，不改变 MasterAsset
  - `ExpeditionWorkspaceStore` 新增方法：
    - `mergeGroups(ids:)` → 合并选中组
    - `splitGroup(groupId:assetIds:)` → 从组中拆出资产为新组
    - `removeFromGroup(groupId:assetIds:)` → 从组中移除照片
    - `moveToGroup(assetIds:targetGroupId:)` → 移动照片到另一组
    - `renameGroup(groupId:newName:)` → 重命名组
    - `setGroupCover(groupId:assetId:)` → 设定组封面
- **快捷键保留**：`P`/`X`/`U`/方向键/Space/1-5/Cmd+A/Tab 全部保留，底层 action 改为调用 `workspaceStore`
- **`AIGroupNamer` 适配**：结果通过 `PhotoGroupRepository.update` 写入

## 本次明确不做

- 不改首页/导航结构（P1F5 负责）
- 不做数据迁移（P1F6 负责）
- 不实现 Album/相册管理（Phase 3）
- 不实现 Mac Photos 相关逻辑（Phase 2）
- 不实现 Action System（Phase 3）

## 用户主路径

1. 用户进入：从 Expedition 列表点击进入某个 Expedition
2. 用户看到：三栏选片工作台（左栏分组导航 + 中栏大图 + 右栏 EXIF/AI）
3. 用户执行：浏览分组 → 按 P/X 标记 → 查看 AI 推荐 → 设定星级
4. 用户完成：选片结果保存在 ExpeditionAsset 上；切换到其他 Expedition 时该 Expedition 的决策独立保留

## 页面与组件

- 需要新增的组件：`ExpeditionWorkspaceStore`、`ExpeditionAssetWithMaster`、`PhotoGroupWithAssets`
- 需要修改的组件：`CullingWorkspaceView`（数据源替换）、`AIScoreCardView`（数据源）、`IssueTagsView`、`AIEnhancementSection`、`ScoringProgressBar`、`ScoringConfirmSheet`、`KeyboardShortcutBridge`、`LocalMLScorer`、`CloudScoringCoordinator`
- 可以复用的组件：`EditSuggestionsCard`（V3 修图建议展示）、`DisplayImageCache`（图片缓存）、`ThumbnailCache`

## 交互要求

- 默认状态：进入 Expedition 后显示全部照片概览
- 主按钮行为：P/X 标记决策，立即写入 SQLite
- 返回行为：退出 Expedition 工作台 → 返回 Library 首页
- 空状态：Expedition 无照片 → 显示「添加照片」引导
- 左栏筛选：点击「已选」仅显示 `decision == .picked` 的照片

## UI 要求

- 风格方向：保留现有 `CullingWorkspaceView` 的三栏布局和深色主题
- 必须保留的现有风格：大图预览、分组缩略图网格、底部操作栏、EXIF 卡片
- 新增部分：左栏增加「AI 推荐/已选/未选/未审/可清理」智能筛选项
- 不要为了"好看"增加复杂装饰

## 技术约束

- `ExpeditionWorkspaceStore` 应为 `@Observable` class，持有 `LumaDatabase`、`AssetManager`、`ExpeditionManager` 引用
- 联合查询 `ExpeditionAssetWithMaster` 在 GRDB 中用 `joining(required:)` 或手动组合实现
- 评分结果不再内嵌在资产对象中，改为按需从 `asset_scores` 表查询
- `visibleAssets` 应支持按 decision/rating/issues 过滤，使用 SQL WHERE 条件
- 分组数据从 `photo_groups` + `photo_group_assets` 表加载，不再内嵌在 Session
- 旧 `ProjectStore` 的选片相关逻辑（`updateDecision`、`selectGroup`、`refreshGroupRecommendations` 等）迁移到 `ExpeditionWorkspaceStore`
- `ProjectStore` 暂时保留用于过渡期兼容（P1F5 完成后可能进一步拆分）
- 大图加载仍使用 `DisplayImageCache`，输入从 `MediaAsset.primaryDisplayURL` 改为 `MasterAsset.existingImageFileURL`
- 不要顺手重构无关模块

## 输出顺序

1. 先搭 `ExpeditionAssetWithMaster`、`PhotoGroupWithAssets` 联合类型
2. 搭 `ExpeditionWorkspaceStore`（核心状态管理）
3. 适配 `LocalMLScorer` + `CloudScoringCoordinator` 输入类型
4. 重构 `CullingWorkspaceView` 数据源
5. 重构左栏导航（增加智能筛选项）
6. 重构右栏 EXIF/AI 卡片数据源
7. 验证快捷键和底部操作栏

## 验收标准

- [ ] 进入 Expedition 后选片工作台正确加载该 Expedition 的照片和分组
- [ ] 按 P/X/U 标记决策后，`ExpeditionAsset.decision` 正确更新（SQLite）
- [ ] 星级评分正确写入 `ExpeditionAsset.rating`
- [ ] 左栏「已选/未选/未审/AI 推荐」筛选功能正常
- [ ] 分组导航正确展示 PhotoGroup 列表
- [ ] 分组合并：选中两个相邻组后合并成功，资产正确合并
- [ ] 分组拆分：从组中选中部分照片拆出为新组
- [ ] 照片移动：将照片从 A 组移动到 B 组，两组资产正确更新
- [ ] 从组移除照片：照片变为未分组状态
- [ ] 组重命名：双击/右键可编辑组名
- [ ] 组封面设定：右键照片可设为封面，封面更新正确
- [ ] AI 评分卡片正确展示从 `asset_scores` 表查询的评分
- [ ] EXIF 卡片正确展示 `MasterAsset.metadata`
- [ ] 本地评分（LocalMLScorer）能对 `MasterAsset` 评分并写入 `asset_scores`
- [ ] 云端评分（CloudScoringCoordinator）能正常触发并写入结果
- [ ] 快捷键全部正常工作
- [ ] 退出 Expedition 后再进入，所有状态保留
- [ ] 同一照片在不同 Expedition 中有独立的 Decision
