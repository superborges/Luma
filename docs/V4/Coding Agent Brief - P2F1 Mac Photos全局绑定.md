## 背景

当前要实现的是 V4 Phase 2 Feature 1（P2F1）— Mac Photos 全局绑定，目标是让 Luma 能够连接用户的 Mac 照片图库，通过 PhotoKit 授权后索引全量 PHAsset 为 MasterAsset（externalReference 模式），不复制原图。

## 本次只做

- **PhotoLibraryProvider 协议**：PhotoKit 抽象层，定义 `PHAssetSnapshot`（Sendable）、`PHCollectionSnapshot`、`PhotoAuthorizationStatus` 枚举
- **SystemPhotoLibraryProvider**：真实 PhotoKit 实现，使用 `PhotoKitSafetyWrapper.withTimeout`（120s 超时）枚举资产
- **MacPhotosManager**：`@MainActor` 服务类
  - 授权（`requestAuthorization`）→ connect / disconnect 状态管理
  - `performFullIndex()`：枚举全部 PHAsset → 每 500 条批量写入 MasterAsset（`createOrReuseMasterAsset`），按 externalIdentifier 去重
  - `isDisconnectedByUser` 标记与 `authorizationStatus` 分离，disconnect 不修改系统授权状态
  - `restoreIndexedCount(_:)` 启动恢复
  - `fetchCollections()` / `assetIdentifiers(in:)` 集合查询
- **AssetSourceManager.fetchByKind(_:)**：按 sourceKind 查询 AssetSource
- **LibraryStore 集成**：
  - `connectMacPhotos()` / `disconnectMacPhotos()` / `refreshMacPhotosIndex()`
  - `ensureMacPhotosExpedition()`：连接后自动创建不可删除的 Mac Photos Expedition
  - `refreshMacPhotosState()`：启动时从 DB 恢复已连接状态
- **单元测试**：`MacPhotosManagerTests`（9 条），使用 `MockPhotoLibraryProvider`

## 本次明确不做

- 不做缩略图/预览图加载（P2F2 负责）
- 不做 Mac Photos 浏览视图（P2F3 负责）
- 不做从 Mac Photos 创建普通 Expedition（P2F4 负责）
- 不支持增量索引（当前为全量索引 + 去重）
- 不复制原图

## 用户主路径

1. 用户在设置中点击「连接 Mac Photos」
2. 系统弹出 PhotoKit 授权对话框
3. 授权成功后，Luma 自动索引照片图库
4. 侧栏出现 Mac Photos 入口

## 页面与组件

- 需要新增的页面：无（设置页在 P2F2）
- 需要新增的组件：`PhotoLibraryProvider`、`SystemPhotoLibraryProvider`、`MacPhotosManager`
- 可以复用的组件：`AssetManager.createOrReuseMasterAsset`、`AssetSourceManager`

## 技术约束

- `PHAssetSnapshot` 使用 `latitude: Double?` / `longitude: Double?` 替代 `CLLocationCoordinate2D`（Sendable 兼容）
- `baseName` 格式 `IMG_yyyyMMdd_HHmmss`（来自 creationDate），fallback 为 localIdentifier
- 索引批量大小 500，批间 `Task.yield()` 避免 UI 阻塞
- `enumerateAssets` 超时 120s（大型图库兼容）
- MacPhotosManager 通过 `isDisconnectedByUser` 与 `authorizationStatus` 双重状态判定 `isConnected`

## 文件组织

```
Sources/Luma/
  Services/MacPhotos/
    PhotoLibraryProvider.swift        # 协议 + PHAssetSnapshot + PHCollectionSnapshot
    SystemPhotoLibraryProvider.swift   # 真实 PhotoKit 实现
    MacPhotosManager.swift            # 授权 + 索引 + 状态管理
  Services/Library/
    AssetSourceManager.swift          # 新增 fetchByKind
  App/
    LibraryStore.swift                # Mac Photos 集成入口
Tests/LumaTests/
  MacPhotosManagerTests.swift         # 9 条单测
```

## 验收标准

- [x] PhotoLibraryProvider 协议定义完整，PHAssetSnapshot 满足 Sendable
- [x] MockPhotoLibraryProvider 可用于测试
- [x] connect 后自动创建 Mac Photos AssetSource 和特殊 Expedition
- [x] disconnect 不修改系统授权状态，只标记 isDisconnectedByUser
- [x] 全量索引按 externalIdentifier 去重
- [x] 启动时从 DB 恢复已连接状态
- [x] 9 条单测全部通过
- [x] `swift build` 通过，不破坏现有测试
