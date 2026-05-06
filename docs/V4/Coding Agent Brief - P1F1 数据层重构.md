## 背景

当前要实现的是 V4 Phase 1 的数据层重构（P1F1），目标是将 Luma 的持久化方案从单文件 JSON manifest 迁移到 GRDB (SQLite)，建立支持 Expedition、全局资产、多对多关系的数据库 schema 和 Repository 访问层。这是 V4 全部功能的基石，后续所有模块都依赖此数据层。

## 本次只做

- **引入 GRDB 依赖**：在 `Package.swift` 中添加 `GRDB.swift` SPM 依赖
- **`LumaDatabase`**：数据库管理器，负责创建/打开 `library.db`，配置 WAL 模式，管理 `DatabaseMigrator`
- **Schema 定义**（`DatabaseMigrator` v1 migration）：
  - `asset_sources` 表：`id TEXT PK`, `kind TEXT`, `displayName TEXT`, `rootIdentifier TEXT`, `isMutable BOOL`, `supportsDelete BOOL`, `supportsAlbumWrite BOOL`, `supportsOriginalAccess BOOL`, `createdAt REAL`, `updatedAt REAL`
  - `master_assets` 表：`id TEXT PK`, `sourceId TEXT FK(asset_sources)`, `sourceKind TEXT`, `storageMode TEXT`, `externalIdentifier TEXT`, `originalURL TEXT`, `localManagedURL TEXT`, `previewURL TEXT`, `rawURL TEXT`, `livePhotoVideoURL TEXT`, `thumbnailCacheURL TEXT`, `previewCacheURL TEXT`, `fingerprint TEXT`, `contentHash TEXT`, `baseName TEXT`, `mediaType TEXT`, `captureDate REAL`, `latitude REAL`, `longitude REAL`, `focalLength REAL`, `aperture REAL`, `shutterSpeed TEXT`, `iso INT`, `cameraModel TEXT`, `lensModel TEXT`, `imageWidth INT`, `imageHeight INT`, `createdAt REAL`, `updatedAt REAL`
  - `expeditions` 表：`id TEXT PK`, `name TEXT`, `subtitle TEXT`, `description TEXT`, `coverAssetId TEXT`, `startDate REAL`, `endDate REAL`, `sourceMode TEXT`, `status TEXT`, `isMacPhotos BOOL DEFAULT 0`, `createdAt REAL`, `updatedAt REAL`
  - `expedition_assets` 表：`id TEXT PK`, `expeditionId TEXT FK`, `assetId TEXT FK`, `addedAt REAL`, `addedBy TEXT`, `localOrder INT`, `decision TEXT DEFAULT 'pending'`, `rating INT`, `colorLabel TEXT`, `isRecommended BOOL DEFAULT 0`, `isBestInGroup BOOL DEFAULT 0`, `isUserOverride BOOL DEFAULT 0`, `isArchived BOOL DEFAULT 0`, `isHiddenInExpedition BOOL DEFAULT 0`, `updatedAt REAL`；唯一约束 `(expeditionId, assetId)`
  - `photo_groups` 表：`id TEXT PK`, `expeditionId TEXT FK`, `name TEXT`, `coverAssetId TEXT`, `groupComment TEXT`, `timeRangeStart REAL`, `timeRangeEnd REAL`, `latitude REAL`, `longitude REAL`, `reviewed BOOL DEFAULT 0`, `createdAt REAL`, `updatedAt REAL`
  - `photo_group_assets` 表：`groupId TEXT FK`, `assetId TEXT FK`, `isRecommended BOOL DEFAULT 0`；PK `(groupId, assetId)`
  - `photo_subgroups` 表：`id TEXT PK`, `groupId TEXT FK`, `bestAssetId TEXT`, `recommendedAssetId TEXT`, `reasonSummary TEXT`, `reviewed BOOL DEFAULT 0`
  - `photo_subgroup_assets` 表：`subgroupId TEXT FK`, `assetId TEXT FK`；PK `(subgroupId, assetId)`
  - `asset_scores` 表：`id TEXT PK`, `assetId TEXT FK`, `provider TEXT`, `composition INT`, `exposure INT`, `color INT`, `sharpness INT`, `story INT`, `overall INT`, `comment TEXT`, `recommended BOOL`, `timestamp REAL`
  - `import_sessions` 表：`id TEXT PK`, `sourceId TEXT FK`, `targetExpeditionId TEXT FK`, `startedAt REAL`, `completedAt REAL`, `status TEXT`, `totalItems INT`, `importedCount INT`, `skippedCount INT`, `failedItems TEXT`（JSON array）
  - `albums` 表：`id TEXT PK`, `expeditionId TEXT FK`, `name TEXT`, `kind TEXT`, `ruleJSON TEXT`, `createdAt REAL`, `updatedAt REAL`
  - `album_assets` 表：`albumId TEXT FK`, `assetId TEXT FK`, `addedAt REAL`, `localOrder INT`；PK `(albumId, assetId)`
  - `external_album_refs` 表：`albumId TEXT PK FK`, `provider TEXT`, `localIdentifier TEXT`
  - `expedition_recommendations` 表：`id TEXT PK`, `expeditionId TEXT FK`, `assetId TEXT FK`, `groupId TEXT FK`, `recommendationType TEXT`, `score INT`, `reason TEXT`, `createdAt REAL`
  - `archive_manifests` 表：`id TEXT PK`, `expeditionId TEXT FK`, `albumId TEXT FK`, `generatedAt REAL`, `archiveKind TEXT`, `itemsJSON TEXT`（JSON array of ArchiveManifestItem）
  - `action_jobs` 表：`id TEXT PK`, `expeditionId TEXT FK`, `albumId TEXT FK`, `kind TEXT`, `targetAssetIdsJSON TEXT`, `status TEXT`, `createdAt REAL`, `completedAt REAL`, `resultURL TEXT`, `errorMessage TEXT`
  - 索引：`master_assets(sourceId)`、`master_assets(contentHash)`、`master_assets(externalIdentifier)`、`expedition_assets(expeditionId)`、`expedition_assets(assetId)`、`expedition_assets(decision)`、`photo_groups(expeditionId)`、`asset_scores(assetId)`、`import_sessions(targetExpeditionId)`、`albums(expeditionId)`、`expedition_recommendations(expeditionId)`、`expedition_recommendations(assetId)`
- **Swift 数据模型 Records**（GRDB `FetchableRecord` + `PersistableRecord`）：
  - `MasterAssetRecord`、`ExpeditionRecord`、`ExpeditionAssetRecord`、`PhotoGroupRecord`、`PhotoGroupAssetRecord`、`PhotoSubGroupRecord`、`PhotoSubGroupAssetRecord`、`AssetScoreRecord`、`AssetSourceRecord`、`ImportSessionRecord`、`AlbumRecord`、`AlbumAssetRecord`、`ExternalAlbumRefRecord`、`ActionJobRecord`、`ExpeditionRecommendationRecord`、`ArchiveManifestRecord`
- **Repository 协议与实现**：
  - `MasterAssetRepository`：`insert/update/delete/fetchById/fetchByContentHash/fetchByExternalId/fetchAll/fetchCount`
  - `ExpeditionRepository`：`insert/update/delete/fetchById/fetchAll/fetchNonMacPhotos/fetchMacPhotos`
  - `ExpeditionAssetRepository`：`insert/update/delete/fetchByExpedition/fetchByAsset/fetchByExpeditionAndDecision/setDecision/exists(expeditionId:assetId:)`
  - `PhotoGroupRepository`：`insert/update/delete/fetchByExpedition/addAsset/removeAsset/fetchAssetsForGroup`
  - `AssetScoreRepository`：`insert/update/fetchByAsset/fetchLatestByAsset`
  - `ImportSessionRepository`：`insert/update/fetchByExpedition/fetchPending`
  - `AlbumRepository`：`insert/update/delete/fetchByExpedition/fetchAll/addAsset/removeAsset`
  - `ActionJobRepository`：`insert/update/fetchByExpedition/fetchPending/fetchCompleted`
  - `ExpeditionRecommendationRepository`：`insert/update/delete/fetchByExpedition/fetchByAsset`
  - `ArchiveManifestRepository`：`insert/update/delete/fetchByExpedition/fetchByAlbum`
- **单测**：每个 Repository 的基础 CRUD 测试（用内存数据库 `:memory:`）

## 本次明确不做

- 不改现有 `Session`、`MediaAsset`、`SessionManifest` 类型（留给 P1F2/P1F6）
- 不改 UI 层
- 不改导入/导出/评分流程
- 不做 V3 → V4 数据迁移（P1F6 负责）
- 不引入 SwiftData 或 Core Data

## 用户主路径

本模块为纯基础设施，用户无直接交互。后续模块通过 Repository 层读写数据。

## 页面与组件

- 需要新增的页面：无
- 需要新增的组件：`LumaDatabase`、所有 Record 类型、所有 Repository
- 可以复用的组件：现有 `EXIFData`（字段映射）、`Coordinate`（拆为 lat/lng 列）

## 交互要求

无 UI 交互（纯数据层）。

## UI 要求

无 UI 变更。

## 技术约束

- 技术栈：GRDB.swift（SPM 依赖）
- 数据库位置：`AppDirectories.lumaSupport / "library.db"`
- WAL 模式：`var config = Configuration(); config.prepareDatabase { db in try db.execute(sql: "PRAGMA journal_mode = WAL") }`
- UUID 存储：TEXT 格式（`UUID().uuidString`），而非 BLOB
- Date 存储：REAL（`timeIntervalSinceReferenceDate`），GRDB 默认行为
- URL 存储：TEXT（`absoluteString`）
- 枚举存储：TEXT（rawValue 字符串）
- JSON 字段（`failedItems`、`targetAssetIdsJSON`、`ruleJSON`）：TEXT 列存 JSON 字符串
- Repository 方法全部为同步（在 GRDB `dbQueue.read/write` 内执行），调用方按需 `Task.detached`
- 不要顺手重构无关模块
- 不要擅自引入其他大型依赖

## 输出顺序

1. 先在 `Package.swift` 添加 GRDB 依赖
2. 搭 `LumaDatabase`（创建/打开数据库 + migration v1）
3. 搭所有 Record 类型（与表对应的 Swift struct）
4. 搭 Repository 协议与 GRDB 实现
5. 最后补单测（内存数据库 CRUD）

## 文件组织建议

```
Sources/Luma/
  Database/
    LumaDatabase.swift
    Records/
      MasterAssetRecord.swift
      ExpeditionRecord.swift
      ExpeditionAssetRecord.swift
      PhotoGroupRecord.swift
      AssetSourceRecord.swift
      AssetScoreRecord.swift
      ImportSessionRecord.swift
      AlbumRecord.swift
      ActionJobRecord.swift
      ExpeditionRecommendationRecord.swift
      ArchiveManifestRecord.swift
    Repositories/
      MasterAssetRepository.swift
      ExpeditionRepository.swift
      ExpeditionAssetRepository.swift
      PhotoGroupRepository.swift
      AssetScoreRepository.swift
      ImportSessionRepository.swift
      AlbumRepository.swift
      ActionJobRepository.swift
      ExpeditionRecommendationRepository.swift
      ArchiveManifestRepository.swift
```

## 验收标准

- [ ] `Package.swift` 正确引入 GRDB 依赖，`swift build` 通过
- [ ] `LumaDatabase` 能在 `~/Library/Application Support/Luma/` 创建 `library.db`
- [ ] 所有核心表（13 张）正确创建，含外键、唯一约束、索引
- [ ] 每个 Record 类型能序列化/反序列化到对应表
- [ ] 每个 Repository 的 `insert/fetch/update/delete` 通过单测
- [ ] `ExpeditionAssetRepository.exists(expeditionId:assetId:)` 正确判定唯一约束
- [ ] `MasterAssetRepository.fetchByContentHash` 和 `fetchByExternalId` 能用于去重
- [ ] 内存数据库单测全部通过
- [ ] 不破坏现有编译（`Session`/`MediaAsset` 等旧类型不动）
