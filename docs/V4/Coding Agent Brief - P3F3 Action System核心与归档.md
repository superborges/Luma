## 背景

当前要实现的是 V4 Phase 3 Feature 3（P3F3）— Action System 核心与归档 Actions。V4 将 Export 概念重构为统一的 Action System，归档是其中最重要的 Action 类别。GRDB 表 `action_jobs` 和 `archive_manifests` 及其 Record/Repository 在 P1 已预建。V3 的 `VideoArchiver` 当前接受 `MediaAsset`，需要适配到 `MasterAsset`。

## 本次只做

- **域模型**：
  - `ActionJob`（从 `ActionJobRecord` 映射）：包含 `id`, `expeditionId`, `albumId`, `kind`, `targetAssetIds`, `status`, `createdAt`, `completedAt`, `resultURL`, `errorMessage`
  - `ActionKind` 枚举：`.archiveVideo` / `.archiveLowres` / `.archiveMarkerOnly` / `.exportToFolder` / `.syncAlbumToPhotos`
  - `JobStatus` 枚举：`.pending` / `.running` / `.completed` / `.failed` / `.cancelled`
  - `ArchiveManifest`（从 `ArchiveManifestRecord` 映射）：包含 `id`, `expeditionId`, `albumId`, `generatedAt`, `archiveKind`, `items`
  - `ArchiveKind` 枚举：`.video` / `.lowresCopy` / `.markerOnly`
  - `ArchiveManifestItem`：`assetId`, `originalReference`, `archivePath?`, `frameIndex?`, `decision`
- **ActionJobRepository 扩展**：
  - `fetchOne(id:) throws -> ActionJobRecord?`
  - `fetchByStatus(_ status: String) throws -> [ActionJobRecord]`
  - `fetchByExpeditionAndStatus(expeditionId:status:) throws -> [ActionJobRecord]`
- **ActionRunner 服务**（`@MainActor`）：
  - `func submit(kind:expeditionId:albumId:targetAssetIds:) throws -> ActionJob`：创建 pending job → 写入 DB
  - `func run(job: ActionJob) async throws`：调度到具体 handler，更新 status running → completed/failed
  - `func cancel(jobId:) throws`：设 status = cancelled
  - 进度回调通过 `ActionRunnerDelegate` 协议或 observable 属性传递
  - 每种 ActionKind 的 handler 函数
- **VideoArchiver 适配**（从 `MediaAsset` → `MasterAsset`）：
  - 新增 `func archive(masterAssets:title:outputURL:onProgress:) async throws -> ArchiveResult`
  - 新增 `func shrinkKeep(masterAssets:outputDirectory:onProgress:) async throws -> ArchiveResult`
  - 内部转换逻辑：`MasterAsset.existingImageFileURL` 或通过 PhotoKit 临时获取图像
  - `externalReference` 资产：通过 `AssetImageProviderFactory` 获取临时图像数据写入临时文件
  - 核心视频生成/缩小算法保持不变
- **MarkerOnly 归档**（新）：
  - 仅将目标 `ExpeditionAsset.isArchived` 设为 `true`
  - 不复制文件、不删除文件
  - 生成 `ArchiveManifest(archiveKind: .markerOnly)`
- **ArchiveManifest 生成**：
  - 归档完成后创建 `ArchiveManifest` + items → 写入 `archive_manifests` 表
- **ExpeditionWorkspaceStore 集成**：
  - `archiveableAssets: [ExpeditionAssetWithMaster]` 计算属性（未选且未归档的资产）
  - `runArchiveAction(kind:) async throws`
- **LibraryStore 集成**：
  - `activeActionJobs: [ActionJob]` / `completedActionJobs: [ActionJob]` observable 状态
  - `refreshActionJobs()`
- **枚举统一**：V3 迁移写入的 `action_jobs.status` 使用 `ExportJobStatus` 枚举值（`queued`/`running`/`completed`/`failed`），需要与新的 `JobStatus`（`pending`/`running`/`completed`/`failed`/`cancelled`）统一。在 Repository fetch 时兼容 `queued` → `pending` 映射。
- **单元测试**：
  - `ActionRunnerTests`（8-10 条：submit/run/cancel/progress/complete/fail）
  - `MarkerOnlyArchiveTests`（2-3 条：标记逻辑 + manifest 生成）

## 本次明确不做

- 不做 UI 面板（P3F4 负责 Action Panel UI）
- 不做导出到文件夹的执行逻辑（P3F4 负责 FolderExporter 适配）
- 不做同步相册到 Photos 的执行逻辑（P3F4 负责包装 P3F2 adapter）
- 不做 Lightroom 导出
- 不做删除本地原图或 Mac Photos 原图

## 用户主路径

（P3F3 主要是服务层，用户交互在 P3F4 中实现）

1. 后台：ActionRunner 接收归档请求 → 创建 ActionJob
2. 后台：按 kind 调度到 archive/shrinkKeep/markerOnly handler
3. 后台：更新进度 → 完成后写入结果 + ArchiveManifest

## 页面与组件

- 需要新增的页面：无（UI 在 P3F4）
- 需要新增的组件：`ActionJob`、`ActionKind`、`JobStatus`、`ArchiveManifest`、`ArchiveKind`、`ArchiveManifestItem`、`ActionRunner`
- 可以复用的组件：`VideoArchiver`（适配接口）、`ActionJobRepository`、`ArchiveManifestRepository`、`AssetImageProviderFactory`

## 技术约束

- `VideoArchiver` 的 `archive`/`shrinkKeep` 方法在 `Task.detached(priority: .utility)` 中执行，不阻塞主线程
- `externalReference` 资产归档视频/缩小保留时，需临时请求图像数据：通过 `AssetImageProviderFactory.provider(for: .externalReference).preview()` 获取 NSImage → 写入临时文件 → 传给 VideoArchiver
- `markerOnly` 归档需要批量更新 `ExpeditionAssetRecord.isArchived`，应在单个 `dbQueue.write` 事务中完成
- `ActionJobRecord.targetAssetIdsJSON` 存储 `[UUID]` 的 JSON 数组字符串
- `ArchiveManifestRecord.itemsJSON` 存储 `[ArchiveManifestItem]` 的 JSON 数组字符串
- `ActionRunner` 同时只允许一个 job 运行（串行调度），防止磁盘/CPU 资源竞争

## 文件组织

```
Sources/Luma/
  Models/
    ActionJob.swift               # 域模型 + ActionKind + JobStatus
    ArchiveManifest.swift         # 域模型 + ArchiveKind + ArchiveManifestItem
  Services/Action/
    ActionRunner.swift            # 调度服务
  Services/Archive/
    VideoArchiver.swift           # 扩展 MasterAsset 适配方法
  Database/Repositories/
    ActionJobRepository.swift     # 扩展查询方法
  App/
    ExpeditionWorkspaceStore.swift # archiveableAssets + runArchiveAction
    LibraryStore.swift            # ActionJob 状态管理
Tests/LumaTests/
  ActionRunnerTests.swift         # 8-10 条
  MarkerOnlyArchiveTests.swift    # 2-3 条
```

## 验收标准

- [ ] ActionJob 域模型完整，ActionKind 覆盖 5 种 Action
- [ ] ArchiveKind 枚举覆盖 video / lowresCopy / markerOnly
- [ ] ActionRunner 能创建/运行/取消 ActionJob
- [ ] VideoArchiver 能接受 MasterAsset 输入执行归档视频
- [ ] VideoArchiver 能接受 MasterAsset 输入执行缩小保留
- [ ] MarkerOnly 归档正确设置 isArchived 标志并生成 manifest
- [ ] 归档完成后 ArchiveManifest 写入 DB
- [ ] V3 迁移的 action_jobs（status=queued）能被正确读取
- [ ] 10-13 条单测全部通过
- [ ] `swift build` 通过，不破坏现有测试
