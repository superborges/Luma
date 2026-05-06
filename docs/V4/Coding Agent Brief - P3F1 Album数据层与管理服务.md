## 背景

当前要实现的是 V4 Phase 3 Feature 1（P3F1）— Album 数据层与管理服务 + 基础 UI。目标是建立完整的相册系统，支持手动相册、智能相册（预设规则）、Photos-backed 相册三种类型。GRDB schema（`albums`/`album_assets`/`external_album_refs`）和基础 Repository（`AlbumRepository`/`GRDBAlbumRepository`）在 P1 已预建。

## 本次只做

- **域模型**：
  - `LumaAlbum`（从 `AlbumRecord` 映射，含 `AlbumKind` 枚举 `.manual/.smart/.photosBacked`）
  - `AlbumAsset`（从 `AlbumAssetRecord` 映射）
  - `ExternalAlbumRef`（从 `ExternalAlbumRefRecord` 映射）
  - `SmartAlbumRule` + `SmartAlbumScope` + `SmartAlbumFilter`（JSON 序列化存入 `ruleJSON` 列）
- **Repository 扩展**（在 `AlbumRepository` 上增加）：
  - `fetchOne(id:) throws -> AlbumRecord?`
  - `fetchAlbumAssets(albumId:) throws -> [AlbumAssetRecord]`
  - `insertBatchAssets(_ records: [AlbumAssetRecord]) throws`
  - `fetchAssetCount(albumId:) throws -> Int`
  - ExternalAlbumRef 的 `insertRef/fetchRef/deleteRef`
- **AlbumManager 服务**：
  - `createManualAlbum(name:expeditionId:) throws -> LumaAlbum`
  - `createSmartAlbum(name:expeditionId:rule:) throws -> LumaAlbum`
  - `deleteAlbum(id:) throws`（Photos-backed 相册需先解除外部绑定）
  - `addAssets(albumId:assetIds:) throws`
  - `removeAssets(albumId:assetIds:) throws`
  - `fetchAlbumsForExpedition(_:) throws -> [LumaAlbum]`
  - `fetchAlbumWithAssets(id:) throws -> (LumaAlbum, [MasterAsset])`
  - `evaluateSmartRule(_:) throws -> [UUID]`（返回匹配的 MasterAsset ID 列表）
- **智能相册预设规则**（`SmartAlbumFilter` 枚举或结构）：
  - `.allPicked`：`ExpeditionAsset.decision == .picked`
  - `.allRejected`：`ExpeditionAsset.decision == .rejected`
  - `.highScore`：`asset_scores.overall >= 80`
  - `.cleanupCandidates`：rejected + 低分 + 模糊
  - `.unreviewed`：`ExpeditionAsset.decision == .pending`
  - `.archived`：`ExpeditionAsset.isArchived == true`
- **UI**：
  - `LibrarySidebar` 增加「相册」section（手动 + 智能相册列表）
  - `CreateAlbumSheet`：创建手动相册（命名 + 可选绑定 Expedition）
  - `AlbumDetailView`：相册内照片网格浏览（`LazyVGrid`）
  - `ExpeditionCullingView` 增加「添加到相册」上下文菜单操作
  - `ContentView` 的 `detailContent` 增加 `.album(id)` 分支
- **LibraryStore 集成**：
  - `albums: [LumaAlbum]` observable 状态
  - `refreshAlbums()`
  - `createAlbum()` / `deleteAlbum()`
- **单元测试**：`AlbumManagerTests`（6-8 条）

## 本次明确不做

- 不做 Photos-backed 相册同步到系统 Photos（P3F2 负责）
- 不做 Action System / 归档（P3F3 负责）
- 不做导出到文件夹（P3F4 负责）
- 不做复杂智能规则编辑器 UI（Build Spec 明确排除）
- 不做相册拖拽排序

## 用户主路径

1. 用户在侧栏看到「相册」section
2. 点击「+」创建手动相册，命名，可选绑定 Expedition
3. 在 Expedition 选片台中，选中照片 → 右键「添加到相册」
4. 点击侧栏中的相册名，进入网格浏览
5. 智能相册自动显示匹配结果（如「已选」「高分」等）

## 页面与组件

- 需要新增的页面：`AlbumDetailView`、`CreateAlbumSheet`
- 需要新增的组件：`LumaAlbum`、`AlbumAsset`、`ExternalAlbumRef`、`AlbumKind`、`SmartAlbumRule`、`AlbumManager`
- 可以复用的组件：`AlbumRepository`（扩展）、`AssetThumbnailCell`（from `AllPhotosGridView`）、`AssetImageProviderFactory`

## 技术约束

- `LumaAlbum` 使用 `init?(record:)` failable 初始化器（与 P1 其他域模型保持一致）
- `SmartAlbumRule` 序列化为 JSON 字符串存入 `AlbumRecord.ruleJSON`
- 智能相册的 `evaluateSmartRule` 通过 SQL 查询实现（不在内存过滤），利用已有索引
- `AlbumAssetRecord` 使用复合主键 `(albumId, assetId)`，`addAssets` 需用 `INSERT OR IGNORE` 避免重复
- 侧栏导航使用 `NavigationItem.album(UUID)` 新增 case

## 文件组织

```
Sources/Luma/
  Models/
    LumaAlbum.swift              # 域模型 + AlbumKind + AlbumAsset + ExternalAlbumRef
    SmartAlbumRule.swift          # SmartAlbumRule + SmartAlbumScope + SmartAlbumFilter
  Services/Library/
    AlbumManager.swift            # 相册 CRUD + 智能规则评估
  Database/Repositories/
    AlbumRepository.swift         # 扩展已有 Repository
  App/
    LibraryStore.swift            # 相册状态集成
  Views/Library/
    CreateAlbumSheet.swift        # 创建相册弹窗
    AlbumDetailView.swift         # 相册详情网格
    LibrarySidebar.swift          # 增加相册 section
  Views/MainWindow/
    ContentView.swift             # 增加 .album(id) 导航
    ExpeditionCullingView.swift   # 增加「添加到相册」操作
Tests/LumaTests/
  AlbumManagerTests.swift         # 6-8 条单测
```

## 验收标准

- [ ] 用户能创建手动相册并命名
- [ ] 用户能在选片台将照片添加到相册
- [ ] 相册详情页以网格展示相册内照片
- [ ] 智能相册按预设规则自动匹配（至少支持 all-picked / all-rejected / high-score / unreviewed / archived）
- [ ] 侧栏正确显示手动相册和智能相册
- [ ] AlbumManager 单测全部通过（6-8 条）
- [ ] `swift build` 通过，不破坏现有测试
