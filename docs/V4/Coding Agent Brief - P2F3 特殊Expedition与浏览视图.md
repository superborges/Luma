## 背景

当前要实现的是 V4 Phase 2 Feature 3（P2F3）— 特殊 Expedition 与浏览视图，目标是让 Mac Photos 作为系统级特殊 Expedition 在 UI 中拥有独立的浏览体验：按年/月时间线网格浏览已索引照片，而不是混在普通旅程列表中。

## 本次只做

- **侧栏优化**：
  - Mac Photos Expedition 从旅程（Expedition）列表中隐藏（`!$0.isMacPhotos` 过滤）
  - 侧栏 Mac Photos 入口常驻可点击：已连接显示资产数量，未连接显示"未连接"标签
- **MacPhotosBrowseView**：
  - 按年/月分组的时间线网格视图
  - `LazyVStack` + `pinnedViews: [.sectionHeaders]` 实现粘性月份标题头
  - 复用 `AssetThumbnailCell`（externalReference 资产通过 PhotoKit 加载）
  - 顶部 header 显示总数、索引状态、刷新按钮、设置入口（齿轮图标 → sheet）
  - 空状态提示
- **ContentView 路由**：`.macPhotos` 导航项根据连接状态分发
  - 已连接 → `MacPhotosBrowseView`
  - 未连接 → `MacPhotosSettingsView`
- **数据层**：
  - `MasterAssetRepository.fetchBySourceKind(_:orderedBy:ascending:)`：按来源类型查询
  - `LibraryStore.MacPhotosMonthSection`：年/月分组模型，含 `displayTitle`（"2024 年 3 月"格式）
  - `LibraryStore.refreshMacPhotosAssets()`：查询 macPhotos 资产 → 按 captureDate 降序 → 按月分组
- **共享组件**：`AssetThumbnailCell` 从 `private` 改为 `internal` 供跨文件复用

## 本次明确不做

- 不做按地点/GPS 分组浏览（后续优化）
- 不做按系统相册分组浏览（后续优化）
- 不做照片详情/大图预览（复用现有 Expedition 选片台路径）
- 不做 Mac Photos 资产的选片/评分（在普通 Expedition 中进行）
- 不做虚拟滚动优化（当前 LazyVGrid 已满足）

## 用户主路径

1. 用户连接 Mac Photos 后，侧栏"Mac Photos"显示已索引数量
2. 用户点击"Mac Photos"→ 进入时间线浏览视图
3. 照片按月份分组，最新的月份在最上方
4. 滚动时月份标题粘在顶部
5. 右上角齿轮按钮可打开设置页管理连接

## 页面与组件

- 需要新增的页面：`MacPhotosBrowseView`
- 需要新增的组件：`MacPhotosMonthSection`
- 可以复用的组件：`AssetThumbnailCell`、`MacPhotosSettingsView`（sheet）
- 需要修改的组件：`LibrarySidebar`、`ContentView`、`LibraryStore`、`MasterAssetRepository`

## 交互要求

- 默认状态：按月降序显示所有已索引照片
- 刷新按钮：触发 `refreshMacPhotosIndex()` + `refreshMacPhotosAssets()`
- 设置按钮：打开 `MacPhotosSettingsView` sheet
- 空状态：当图库为空时显示提示
- 粘性标题：滚动时月份标题固定在顶部

## UI 要求

- 暗色主题，遵循 StitchTheme
- 网格间距 3px，自适应列宽 130~200
- 月份标题 14pt semibold + 右侧资产数量
- header 区域：蓝色图标 + 标题 + 索引状态 + 总数 + 工具按钮

## 技术约束

- `captureDate` 以 `timeIntervalSinceReferenceDate` (Double) 存储，需转换为 `Date` 再按 Calendar 分组
- 无日期资产归入特殊 "无日期" 分组（year=0, month=0），排在最后
- `fetchBySourceKind` 返回按 captureDate 降序排列的全部 macPhotos 资产
- `onAppear` 时触发 `refreshMacPhotosAssets()`

## 文件组织

```
Sources/Luma/
  Views/Library/
    MacPhotosBrowseView.swift          # 新建：时间线浏览视图
    MacPhotosSettingsView.swift        # 已有：作为 sheet 复用
    AllPhotosGridView.swift            # 修改：AssetThumbnailCell 改为 internal
    LibrarySidebar.swift               # 修改：过滤 isMacPhotos + 显示数量
  Views/MainWindow/
    ContentView.swift                  # 修改：路由分发
  Database/Repositories/
    MasterAssetRepository.swift        # 新增 fetchBySourceKind
  App/
    LibraryStore.swift                 # 新增 MacPhotosMonthSection + refreshMacPhotosAssets
```

## 验收标准

- [x] Mac Photos Expedition 不出现在侧栏旅程列表中
- [x] 侧栏 Mac Photos 入口始终可点击
- [x] 已连接时显示 MacPhotosBrowseView，未连接时显示 MacPhotosSettingsView
- [x] 照片按月分组、降序排列、粘性标题
- [x] 空状态正确显示
- [x] 设置页可通过齿轮按钮打开
- [x] `swift build` 通过，341 测试全部通过
