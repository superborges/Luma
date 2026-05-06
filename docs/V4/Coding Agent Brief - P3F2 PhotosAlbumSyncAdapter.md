## 背景

当前要实现的是 V4 Phase 3 Feature 2（P3F2）— PhotosAlbumSyncAdapter，目标是从 V3 `PhotosAppExporter` 中提取相册回写能力，抽象为 `AlbumSyncAdapter` 协议，实现 Photos-backed 相册的创建和双向同步。产品规格将此能力从「导出到相册」升级为「Photos-backed Album Sync」。

## 本次只做

- **AlbumSyncAdapter 协议**（`Services/MacPhotos/AlbumSyncAdapter.swift`）：
  ```swift
  protocol AlbumSyncAdapter: Sendable {
      var displayName: String { get }
      func createAlbum(name: String, assets: [MasterAsset]) async throws -> ExternalAlbumRef
      func updateAlbum(_ ref: ExternalAlbumRef, assets: [MasterAsset]) async throws
      func removeAssets(_ assets: [MasterAsset], from ref: ExternalAlbumRef) async throws
      func validateAccess() async throws -> Bool
  }
  ```
- **PhotosAlbumSyncAdapter 实现**（从 V3 `PhotosAppExporter` 提取）：
  - `createAlbum`：`PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:)` → 返回 `ExternalAlbumRef(provider: .macPhotos, localIdentifier: placeholder.localIdentifier)`
  - `updateAlbum`：fetch `PHAssetCollection` by `localIdentifier` → `PHAssetCollectionChangeRequest(for:)` + `addAssets`
    - `.externalReference` 资产通过 `PHAsset.fetchAssets(withLocalIdentifiers:)` 获取 PHAsset 引用
    - 非 Photos 来源的资产需通过 `PHAssetCreationRequest` 先导入到 Photos
  - `removeAssets`：`PHAssetCollectionChangeRequest` + `removeAssets`（从相册移除，不删除照片本体）
  - `validateAccess`：检查 PhotoKit authorization + 检查 `PHAssetCollection` 是否仍存在
- **ExternalAlbumRef 生命周期管理**（在 `AlbumManager` 中扩展）：
  - 同步创建后写入 `external_album_refs` 表
  - `validateAlbumRef(albumId:)` → 调用 `validateAccess` 检测 Photos 侧相册是否被删除
  - 失效时标记 album 为 stale（UI 显示「外部相册已失效」）
- **LibraryStore 集成**：
  - `syncAlbumToPhotos(albumId:) async throws`：首次同步 → createAlbum + 写 ref；后续 → updateAlbum
  - `validatePhotosAlbumRefs()` 启动时或手动触发
- **UI**：
  - `AlbumDetailView` 增加「同步到 Photos」按钮（仅对 `.manual` 和 `.photosBacked` 相册显示）
  - 同步状态指示：未同步 / 同步中 / 已同步 / 已失效
  - 失效状态下显示「外部相册已失效 — 重新绑定 / 转为本地相册」选项
- **单元测试**：
  - `MockAlbumSyncAdapter` 实现
  - `PhotosAlbumSyncAdapterTests`（5-6 条，mock PhotoKit 行为）

## 本次明确不做

- 不做 Action System 集成（P3F3/F4 负责将 sync 包装为 ActionJob）
- 不做删除 Photos 中照片本体（产品规格 V4 第一阶段不支持）
- 不做自动同步（仅手动触发）
- 不做 Lightroom 同步适配器

## 用户主路径

1. 用户在相册详情页点击「同步到 Photos」
2. 首次同步：创建系统 Photos 相册 + 添加照片
3. 后续同步：更新系统 Photos 相册内容（增量）
4. 如果系统侧相册被删除，显示「已失效」提示，用户可重新绑定

## 页面与组件

- 需要修改的页面：`AlbumDetailView`（增加同步按钮和状态）
- 需要新增的组件：`AlbumSyncAdapter` 协议、`PhotosAlbumSyncAdapter`
- 可以复用的组件：V3 `PhotosAppExporter` 中 `performChanges`、`authorizationStatus` 逻辑

## 技术约束

- `PhotosAlbumSyncAdapter` 不持有状态，每次操作独立（Sendable）
- `PHPhotoLibrary.shared().performChanges` 的 completion handler 需正确处理用户取消（`NSUserCancelledError`）→ 映射为 `LumaError.userCancelled`
- `ExternalAlbumRef.localIdentifier` 存储 `PHAssetCollection.localIdentifier`
- `.externalReference` 资产（Mac Photos）同步时直接用 `localIdentifier` fetch PHAsset，不需要文件复制
- 非 `.externalReference` 资产同步时需要 `PHAssetCreationRequest` 将本地文件添加到 Photos 图库
- 同步失败不影响 Luma 本地相册数据

## 文件组织

```
Sources/Luma/
  Services/MacPhotos/
    AlbumSyncAdapter.swift           # 协议定义
    PhotosAlbumSyncAdapter.swift     # Photos 实现
  Services/Library/
    AlbumManager.swift               # 扩展 ref 生命周期管理
  App/
    LibraryStore.swift               # syncAlbumToPhotos 集成
  Views/Library/
    AlbumDetailView.swift            # 增加同步按钮和状态
Tests/LumaTests/
  PhotosAlbumSyncAdapterTests.swift  # 5-6 条单测
```

## 验收标准

- [ ] AlbumSyncAdapter 协议定义完整，MockAlbumSyncAdapter 可用于测试
- [ ] 首次同步创建系统 Photos 相册并正确写入 external_album_refs
- [ ] 后续同步更新相册内容（增量 addAssets）
- [ ] externalReference 资产通过 PHAsset fetch 直接引用，不触发文件复制
- [ ] validateAccess 检测外部相册是否被删除，失效时 UI 有提示
- [ ] 同步失败时 Luma 本地数据不受影响
- [ ] 5-6 条单测通过
- [ ] `swift build` 通过，不破坏现有测试
