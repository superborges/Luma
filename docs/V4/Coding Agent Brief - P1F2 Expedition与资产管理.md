## 背景

当前要实现的是 V4 Phase 1 的 Expedition 与资产管理模块（P1F2），目标是建立 Expedition 作为核心工作空间、MasterAsset 作为全局照片实体、ExpeditionAsset 作为上下文关系的业务层。这是连接数据层（P1F1）和上层 UI/导入/选片模块的桥梁。

**前置依赖**：P1F1（数据层重构，GRDB schema + Repository）已完成。

## 本次只做

- **业务层数据模型**（面向 UI 和服务层的 Swift 类型，区别于 P1F1 的 Database Record）：
  - `MasterAsset`：从旧 `MediaAsset` 演化，去除 `userDecision`/`userRating`/`importState`，新增 `sourceId`/`sourceKind`/`storageMode`/`externalIdentifier`/`localManagedURL`/`contentHash`/`fingerprint`；保留 `baseName`/`metadata(EXIFData)`/`mediaType`/`previewURL`/`rawURL`/`livePhotoVideoURL`/`thumbnailCacheURL`/`existingImageFileURL`（计算属性）
  - `Expedition`：`id`/`name`/`subtitle`/`description`/`coverAssetId`/`startDate`/`endDate`/`sourceMode(ExpeditionSourceMode)`/`status(ExpeditionStatus)`/`isMacPhotos`/`createdAt`/`updatedAt`
  - `ExpeditionAsset`：`id`/`expeditionId`/`assetId`/`addedAt`/`addedBy(AssetAddedBy)`/`localOrder`/`decision(Decision)`/`rating`/`colorLabel`/`isRecommended`/`isBestInGroup`/`isUserOverride`/`isArchived`/`isHiddenInExpedition`
  - `AssetSource`：`id`/`kind(AssetSourceKind)`/`displayName`/`rootIdentifier`/能力布尔字段
  - 枚举：`AssetSourceKind`/`AssetStorageMode`/`ExpeditionSourceMode`/`ExpeditionStatus`/`AssetAddedBy`/`MediaType`（扩展版：photo/rawPlusJpeg/livePhoto/portrait/unknown）
- **Record ↔ 业务模型转换**：每个业务模型提供 `init(record:)` 和 `toRecord()` 方法
- **`ExpeditionManager`**（业务逻辑层）：
  - `createExpedition(name:subtitle:sourceMode:) -> Expedition`
  - `updateExpedition(_:)`
  - `deleteExpedition(_:)`：删除 Expedition + 关联的 ExpeditionAsset + PhotoGroup，不删 MasterAsset
  - `listExpeditions() -> [Expedition]`
  - `fetchExpedition(id:) -> Expedition?`
  - `setExpeditionCover(expeditionId:assetId:)`
  - `updateExpeditionStatus(expeditionId:status:)`
- **`AssetManager`**（全局资产管理）：
  - `createOrReuseMasterAsset(from:storageMode:sourceId:) -> MasterAsset`：核心去重逻辑
    - Mac Photos：按 `externalIdentifier`（PHAsset.localIdentifier）去重
    - SD 卡/文件夹 managed：按 `contentHash` 去重
    - 文件夹 referenced：按 `originalURL` 去重
  - `addAssetToExpedition(assetId:expeditionId:addedBy:) -> ExpeditionAsset`：检查唯一约束
  - `removeAssetFromExpedition(assetId:expeditionId:)`：仅删 ExpeditionAsset，不删 MasterAsset
  - `setDecision(expeditionId:assetId:decision:isUserOverride:)`
  - `setRating(expeditionId:assetId:rating:)`
  - `fetchAssetsForExpedition(expeditionId:decision:) -> [MasterAsset]`
  - `fetchExpeditionAsset(expeditionId:assetId:) -> ExpeditionAsset?`
  - `fetchAllMasterAssets(limit:offset:) -> [MasterAsset]`
  - `computeContentHash(fileURL:) -> String`：SHA-256 前 4KB + 文件大小拼接
- **`AssetSourceManager`**：
  - `registerSource(kind:displayName:rootIdentifier:) -> AssetSource`
  - `fetchSource(id:) -> AssetSource?`
  - `listSources() -> [AssetSource]`
- **`MediaType` 枚举扩展**（对应 Product Spec §5.3）：
  - 当前 V3 的 `MediaType` 需扩展为：`photo`、`rawPlusJpeg`、`livePhoto`、`portrait`、`unknown`
  - `rawPlusJpeg`：RAW+JPEG 配对（同一张照片的 RAW 和 JPEG 文件关联为一个资产）
  - `unknown`：无法识别的文件类型，仅导入不处理
  - V4 只支持图片资产；Live Photo 作为图片资产 + auxiliary MOV 处理；普通视频不作为一等资产
- **重构 `Decision` 枚举**：从 `MediaAsset.swift` 提取为独立文件 `Sources/Luma/Models/Decision.swift`，旧 `MediaAsset` 保留兼容引用
- **单测**：ExpeditionManager CRUD、AssetManager 去重、addAssetToExpedition 唯一约束

## 本次明确不做

- 不改 UI 层（首页/选片工作台等，P1F4/P1F5 负责）
- 不改导入流程（P1F3 负责）
- 不改评分/分组服务（P1F4 会适配）
- 不做数据迁移（P1F6 负责）
- 不实现 Mac Photos 相关逻辑（Phase 2 负责）
- 不实现 Album 管理（Phase 3 负责）

## 用户主路径

本模块为业务逻辑层，用户通过后续 UI 模块间接使用。典型调用链：

1. UI 调用 `ExpeditionManager.createExpedition(name: "日本关西 2026")` → 写入 SQLite
2. 导入模块调用 `AssetManager.createOrReuseMasterAsset(from: discoveredItem)` → 全局去重后写入
3. 导入模块调用 `AssetManager.addAssetToExpedition(assetId:expeditionId:)` → 建立关系
4. 选片模块调用 `AssetManager.setDecision(expeditionId:assetId:decision: .picked)` → 写入 ExpeditionAsset

## 页面与组件

- 需要新增的组件：`MasterAsset`（业务模型）、`Expedition`、`ExpeditionAsset`、`AssetSource`、`ExpeditionManager`、`AssetManager`、`AssetSourceManager`
- 可以复用的组件：`EXIFData`（不变）、`Coordinate`（不变）、`Decision` 枚举（提取后旧代码 typealias）、P1F1 的 Repository 层

## 技术约束

- `ExpeditionManager`/`AssetManager`/`AssetSourceManager` 应为 `@Observable` class（或 actor），持有 `LumaDatabase` 引用
- 去重逻辑 `contentHash`：对文件取 **前 4096 字节 SHA-256 + 文件大小** 拼接为字符串（性能优先，不读全文件）
- `MasterAsset` 不含 `userDecision` / `userRating`——这些属于 `ExpeditionAsset`
- `MasterAsset` 的 `aiScore` 不内嵌，改为通过 `AssetScoreRepository` 单独查询
- 旧 `MediaAsset` 暂不删除（P1F4/P1F6 完成后再清理）
- `ExpeditionAsset` 的 `(expeditionId, assetId)` 唯一约束由数据库保证；业务层 `addAssetToExpedition` 在 `INSERT OR IGNORE` 后检查是否已存在
- 不要顺手重构无关模块
- 不要擅自引入新的大型依赖

## 输出顺序

1. 先搭业务层枚举（`AssetSourceKind`、`AssetStorageMode`、`ExpeditionSourceMode`、`ExpeditionStatus`、`AssetAddedBy`）
2. 搭业务模型（`MasterAsset`、`Expedition`、`ExpeditionAsset`、`AssetSource`）+ Record 转换
3. 搭 `AssetSourceManager`（最简单）
4. 搭 `ExpeditionManager`
5. 搭 `AssetManager`（含去重逻辑）
6. 补单测

## 文件组织建议

```
Sources/Luma/
  Models/
    Decision.swift           (从 MediaAsset.swift 提取)
    MasterAsset.swift        (新)
    Expedition.swift         (新)
    ExpeditionAsset.swift    (新)
    AssetSource.swift        (新)
    AssetEnums.swift         (新：AssetSourceKind, AssetStorageMode, ExpeditionSourceMode, etc.)
  Services/
    Library/
      ExpeditionManager.swift
      AssetManager.swift
      AssetSourceManager.swift
```

## 验收标准

- [ ] `MasterAsset` 不包含 `userDecision`/`userRating`（这些在 `ExpeditionAsset`）
- [ ] `Expedition` 可 CRUD，删除时级联删除 `ExpeditionAsset` 和 `PhotoGroup` 但保留 `MasterAsset`
- [ ] `AssetManager.createOrReuseMasterAsset` 对同一 `contentHash` 不重复创建
- [ ] `AssetManager.createOrReuseMasterAsset` 对同一 `externalIdentifier` 不重复创建
- [ ] `AssetManager.addAssetToExpedition` 对同一 `(expeditionId, assetId)` 不报错（幂等）
- [ ] `AssetManager.setDecision` 正确更新 `ExpeditionAsset.decision`
- [ ] Record ↔ 业务模型双向转换正确
- [ ] 单测覆盖去重、CRUD、级联删除
- [ ] 不破坏现有编译
