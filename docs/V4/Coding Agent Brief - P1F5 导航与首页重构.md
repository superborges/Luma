## 背景

当前要实现的是 V4 Phase 1 的导航与首页重构（P1F5），目标是将 Luma 的应用级导航从 V3 的「`hasActiveProject` 二选一（Session 列表 vs 选片工作台）」改为 `NavigationSplitView` 三栏架构，引入 Library 侧栏导航，以 Expedition 卡片列表取代 Session 列表，建立「照片管理中心」的首页体验。

**前置依赖**：P1F2（Expedition/资产管理）+ P1F4（选片工作台迁移）已完成。

## 本次只做

- **`ContentView` 重构**：从 `if hasActiveProject` 二选一改为 `NavigationSplitView` 三栏：
  ```swift
  NavigationSplitView {
      LibrarySidebar()
  } content: {
      // 基于侧栏选中状态切换：
      // - .allPhotos → AllPhotosGridView
      // - .recentlyAdded → RecentlyAddedView
      // - .unorganized → UnorganizedPhotosView
      // - .expedition(id) → ExpeditionDetailView / CullingWorkspaceView
      // - .macPhotos → MacPhotosPlaceholder (Phase 2)
  } detail: {
      // 选中照片时的大图/详情
  }
  ```
- **`LibrarySidebar`**（新视图，替代旧 `SessionListView` 的导航角色）：
  ```text
  资料库
    所有照片
    Mac Photos        （Phase 2 前为灰色占位）
    最近添加
    未整理
  
  旅程
    日本关西 2026
    周末扫街
    家庭照片整理      （从 DB 加载 Expedition 列表）
    ＋ 新建旅程
  
  相册                （Phase 3 前为空/占位）
    Luma 精选
    待修图
  
  任务                （当前无运行任务则隐藏）
    正在导入
    正在分析
  ```
  - Section 使用 `DisclosureGroup`，展开/折叠状态持久化
  - Expedition 列表：`ForEach(expeditions)`，行显示名称 + 照片数 + 状态标签
  - 底部「新建旅程」按钮 → 弹出创建 Expedition sheet
  - 右键菜单：重命名 / 设封面 / 删除
- **`LibraryStore`**（新的全局状态管理器，逐步替代 `ProjectStore`）：
  - `@Observable` class
  - 持有 `LumaDatabase`、`ExpeditionManager`、`AssetManager`、`AssetSourceManager`
  - `expeditions: [Expedition]`
  - `selectedNavItem: NavigationItem?`
  - `allAssetsCount: Int`
  - `recentlyAddedAssets: [MasterAsset]`
  - `unorganizedAssets: [MasterAsset]`（不属于任何 Expedition 的资产）
  - `isImporting: Bool`、`importProgress: ImportProgress?`
  - `macPhotosConnected: Bool`（Phase 2 使用，Phase 1 默认 false）
  - 方法：`refreshExpeditions()`、`createExpedition(name:)`、`deleteExpedition(id:)`、`openExpedition(id:)`
- **`NavigationItem` 枚举**：
  ```swift
  enum NavigationItem: Hashable {
      case allPhotos
      case macPhotos
      case recentlyAdded
      case unorganized
      case expedition(UUID)
      case album(UUID)          // Phase 3 激活
      case taskList
  }
  ```
- **`ExpeditionCardView`**（Expedition 列表中的卡片展示，对应 Product Spec §15.3）：
  - 封面图（`coverAssetId` → `MasterAsset.thumbnailCacheURL`）
  - 名称、时间范围（`startDate – endDate`）
  - 统计：总照片数 / 分组数量 / 已选 / 未审
  - 状态标签（`ExpeditionStatus` 映射为中文文案 + 颜色）
  - 点击 → 进入 Expedition 工作台
- **`ExpeditionListView`**（首页主区域，当 `selectedNavItem` 为 nil 或非具体 Expedition 时）：
  - 顶部 header：欢迎文案 + 快速操作（新建旅程 / 添加照片）
  - `LazyVGrid` 展示 `ExpeditionCardView`
  - Mac Photos 状态卡片（Phase 1 显示「未连接」占位）
  - 当前进行中的任务（导入/评分进度）
- **`CreateExpeditionSheet`**（创建 Expedition 弹窗）：
  - 名称输入（必填）
  - 可选：副标题、时间范围、来源模式选择
  - 创建后可选择立即添加照片
- **`AllPhotosGridView`**（全局所有照片网格）：
  - `LazyVGrid` 展示全局 `MasterAsset` 缩略图
  - 支持排序：按拍摄时间 / 添加时间
  - 点击照片显示详情（属于哪些 Expedition、评分、EXIF）
- **`RecentlyAddedView`**：按 `MasterAsset.createdAt` 降序展示最近添加
- **`UnorganizedPhotosView`**：展示不属于任何 Expedition 的 MasterAsset
- **App 入口重构**：`LumaApp.swift` 的 `WindowGroup` 将 `ContentView` 的 `store` 参数从 `ProjectStore` 切换为 `LibraryStore`
- **引用失效检测与重定位**（对应 Product Spec §17.3 / §17.6）：
  - 对 `storageMode == .referenced` 的 MasterAsset，定期或打开 Expedition 时检测原文件是否存在
  - 检测维度：文件是否存在、外置硬盘是否连接、权限是否有效
  - 失效资产在 UI 上展示警告标志（缩略图叠加「⚠️ 引用失效」标签）
  - 提供「重新定位」操作：用户选择新路径 → 更新 `MasterAsset.originalURL`
  - `LibraryStore` 新增方法：
    - `checkReferencedAssetValidity(expeditionId:) -> [MasterAsset]`：返回引用失效的资产列表
    - `relocateAsset(assetId:newURL:)`：更新资产引用路径
  - 首页 Expedition 卡片上若存在引用失效资产，显示警告图标
- **旧 `SessionListView` 标记 deprecated**，保留源文件但不再使用

## 本次明确不做

- 不实现 Mac Photos 浏览器（Phase 2）
- 不实现 Album/相册管理界面（Phase 3）
- 不实现 Action System 界面（Phase 3）
- 不做数据迁移（P1F6 负责）
- 不改 `SettingsView`（后续 Phase 增量修改）

## 用户主路径

1. 用户进入：启动 App → 看到三栏布局（左侧 Library 导航 + 中间 Expedition 列表 + 右侧空/详情）
2. 用户看到：左侧「资料库」和「旅程」分区；中间显示 Expedition 卡片
3. 用户执行：
   - 点击 Expedition 卡片 → 进入选片工作台
   - 点击「新建旅程」→ 填写名称 → 创建
   - 点击「所有照片」→ 浏览全局资产
   - 点击「最近添加」→ 按时间查看
4. 用户完成：在 Library 级别管理多个 Expedition 和全局资产

## 页面与组件

- 需要新增的页面：`LibrarySidebar`、`ExpeditionListView`、`ExpeditionCardView`、`CreateExpeditionSheet`、`AllPhotosGridView`、`RecentlyAddedView`、`UnorganizedPhotosView`
- 需要新增的组件：`LibraryStore`、`NavigationItem`
- 需要修改的组件：`ContentView`（重构为 `NavigationSplitView`）、`LumaApp`（切换到 `LibraryStore`）
- 可以复用的组件：`CullingWorkspaceView`（P1F4 已迁移）、`SettingsView`、`DisplayImageCache`、`ThumbnailCache`、深色主题 / `StitchTypography` / `StitchTheme`

## 交互要求

- 默认状态：启动时展示 Expedition 列表（首页），左侧导航展开「资料库」和「旅程」
- 主按钮行为：点击 Expedition → 中间区域切换为选片工作台
- 返回行为：工作台中点击「返回」或侧栏选择其他项 → 离开工作台
- 空状态：无 Expedition → 中间显示引导页（创建第一个旅程 / 添加照片）
- 新建弹窗：名称必填，其他可选，确认后立即创建

## UI 要求

- 风格方向：深色主题延续，侧栏使用系统标准 `List` + `Section` 样式
- 必须保留的现有风格：`StitchTypography` 字体系统、`StitchTheme` 配色、深色背景
- 新增部分：
  - Expedition 卡片使用大封面图 + 底部信息条
  - 左侧导航使用 SF Symbols 图标（`photo.on.rectangle` / `star` / `clock` / `tray` 等）
  - 首页 header 简洁大气，不堆砌功能按钮
- `NavigationSplitView` 侧栏宽度：200–260pt（系统默认即可）
- 不要为了"好看"增加复杂装饰

## 技术约束

- `NavigationSplitView` 需要 macOS 13+（Luma 最低 macOS 14，满足）
- `LibraryStore` 使用 `@Observable`（macOS 14+ Observation 框架）
- 侧栏选择状态通过 `@State var selectedNavItem: NavigationItem?` 驱动 `content` 区域
- Expedition 列表从 `ExpeditionRepository` 加载，支持排序（按 updatedAt 降序）
- 全局照片计数使用 `MasterAssetRepository.fetchCount()`
- 「最近添加」查询 `MasterAsset` 表 `ORDER BY createdAt DESC LIMIT 100`
- 「未整理」查询 `MasterAsset` 中不存在于任何 `ExpeditionAsset` 的记录（`LEFT JOIN ... WHERE expedition_assets.id IS NULL`）
- `ProjectStore` 暂时保留，`LibraryStore` 可持有 `ProjectStore` 引用用于过渡期（评分/导入等旧逻辑调用）
- `LumaCommands`（菜单栏命令）需要适配新的 `LibraryStore` 环境
- `KeyboardShortcutBridge` 在 Expedition 工作台内保持工作
- 不要顺手重构无关模块

## 输出顺序

1. 先搭 `NavigationItem` 枚举 + `LibraryStore`
2. 搭 `LibrarySidebar`
3. 重构 `ContentView` 为 `NavigationSplitView`
4. 搭 `ExpeditionCardView` + `ExpeditionListView`（首页主区域）
5. 搭 `CreateExpeditionSheet`
6. 搭 `AllPhotosGridView` / `RecentlyAddedView` / `UnorganizedPhotosView`
7. 适配 `LumaApp` 入口 + `LumaCommands`

## 文件组织建议

```
Sources/Luma/
  App/
    LibraryStore.swift         (新)
  Views/
    Library/
      LibrarySidebar.swift     (新)
      ExpeditionListView.swift (新)
      ExpeditionCardView.swift (新)
      CreateExpeditionSheet.swift (新)
      AllPhotosGridView.swift  (新)
      RecentlyAddedView.swift  (新)
      UnorganizedPhotosView.swift (新)
    MainWindow/
      ContentView.swift        (重构)
```

## 验收标准

- [ ] 启动后显示 `NavigationSplitView` 三栏布局
- [ ] 左侧导航显示「资料库」和「旅程」两个分区
- [ ] 「旅程」下列出所有 Expedition，显示名称和照片数
- [ ] 点击 Expedition → 中间区域切换为选片工作台
- [ ] 「新建旅程」按钮弹出创建弹窗，填写名称后可创建
- [ ] 「所有照片」显示全局 MasterAsset 网格
- [ ] 「最近添加」按时间降序展示
- [ ] 「未整理」正确展示不属于任何 Expedition 的照片
- [ ] 删除 Expedition 后列表正确刷新（右键菜单）
- [ ] 空 Expedition 列表显示引导页
- [ ] Mac Photos 入口显示「未连接」占位（Phase 1）
- [ ] 相册区域显示占位（Phase 3）
- [ ] 窗口最小尺寸和标题栏样式与 V3 一致
- [ ] 快捷键在选片工作台内正常工作
- [ ] Expedition 卡片展示分组数量
- [ ] 引用失效的资产在 UI 上有警告标志
- [ ] 用户可通过「重新定位」操作更新失效引用
- [ ] Expedition 卡片存在引用失效时显示警告图标
