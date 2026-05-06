## 背景

当前要实现的是 V4 Phase 1 的 V3 数据自动迁移模块（P1F6），目标是在用户首次启动 V4 版本时，自动将所有旧版 Session 数据（JSON manifest）迁移到新的 SQLite 数据库，确保用户无缝过渡到 Expedition 架构。迁移过程需要保留所有选片状态、评分、分组和文件引用。

**前置依赖**：P1F1（数据层）+ P1F2（Expedition/资产管理）已完成。可与 P1F3-P1F5 并行开发。

## 本次只做

- **`V3MigrationManager`**（迁移管理器）：
  - `needsMigration() -> Bool`：检查是否存在旧版数据且尚未迁移
    - 扫描 `~/Library/Application Support/Luma/` 下所有包含 `manifest.json` 的项目目录
    - 检查 `migration_completed_v4` 标记文件是否存在
  - `performMigration(onProgress:) async throws`：执行完整迁移
  - `estimateMigrationScope() -> MigrationEstimate`：预估迁移量（Session 数、照片数）
- **迁移流程**（`performMigration` 内部）：
  1. **备份**：将所有旧项目目录的 `manifest.json` 复制到 `migration-backup/` 目录
  2. **遍历每个 Session**：
     a. 读取 `manifest.json` → 解码为 `SessionManifest`（复用现有解码器，含 v0/v1/v2 兼容）
     b. 注册 `AssetSource`：
        - 根据 Session 内 `MediaAsset.source` 类型推断：
          - `.folder(path:)` → `AssetSourceKind.localFolder`，`storageMode = .managed`
          - `.sdCard(volumePath:)` → `AssetSourceKind.sdCard`，`storageMode = .managed`
          - `.photosLibrary(localIdentifier:)` → `AssetSourceKind.macPhotos`，`storageMode = .externalReference`
        - 同一来源路径复用已注册的 `AssetSource`
     c. 创建 `Expedition`：
        - `name = session.name`
        - `sourceMode`：根据 Session 内资产来源推断（全部同一来源 → 对应模式；混合 → `.mixed`）
        - `status = .completed`（已完成选片的 Session）或 `.reviewing`（有未处理资产）
        - `startDate / endDate`：从资产 EXIF captureDate 推算
        - `coverAssetId`：`session.coverAssetID`
        - `createdAt = session.createdAt`
     d. 迁移 `MediaAsset` → `MasterAsset`：
        - `id`：保持不变（直接复用 `MediaAsset.id`）
        - `sourceId`：关联对应 `AssetSource`
        - `sourceKind / storageMode`：根据 `MediaAsset.source` 映射
        - `externalIdentifier`：`.photosLibrary(localIdentifier)` → `localIdentifier`
        - `originalURL`：`.folder` 源 → `MediaAsset.rawURL` 或推断原始路径
        - `localManagedURL`：`.sdCard` / `.managed` → `MediaAsset.rawURL`
        - `previewURL / rawURL / livePhotoVideoURL / thumbnailCacheURL`：直接映射
        - `baseName / metadata / mediaType`：直接映射
        - `contentHash`：迁移时计算（前 4KB SHA-256 + 文件大小）；文件不存在则置 nil
        - `fingerprint`：暂不迁移（后续增量计算）
        - **去重检测**：对同一 `contentHash` 的资产，只创建一个 `MasterAsset`，多个 ExpeditionAsset 引用同一个
     e. 创建 `ExpeditionAsset`：
        - `expeditionId`：当前迁移的 Expedition
        - `assetId`：对应 `MasterAsset.id`
        - `decision`：`MediaAsset.userDecision`
        - `rating`：`MediaAsset.userRating`
        - `isRecommended`：`MediaAsset.aiScore?.recommended ?? false`
        - `addedBy`：`.importSession(importSession.id)` 或 `.manualAdd`
     f. 迁移 `AIScore` → `asset_scores` 表：
        - 每个 `MediaAsset.aiScore` 插入 `AssetScoreRecord`
     g. 迁移 `PhotoGroup` → `photo_groups` + `photo_group_assets`：
        - `expeditionId` 关联当前 Expedition
        - `assets` UUID 列表 → `photo_group_assets` 关系
        - `subGroups` → `photo_subgroups` + `photo_subgroup_assets`
     h. 迁移 `ImportSession`（历史记录）→ `import_sessions` 表
     i. 迁移 `ExportJob`（历史记录）→ `action_jobs` 表（`kind = .exportCopyToFolder`）
  3. **写入迁移标记**：在 Luma 目录写入 `migration_completed_v4` 文件，包含迁移时间和统计
  4. **进度回调**：`MigrationProgress`（`currentSession`/`totalSessions`/`currentAsset`/`totalAssets`/`phase`）
- **`MigrationEstimate`**：
  ```swift
  struct MigrationEstimate {
      let sessionCount: Int
      let totalAssetCount: Int
      let estimatedTimeSeconds: Int
  }
  ```
- **迁移 UI**：
  - 首次启动 V4 时，如果 `needsMigration() == true`，显示迁移提示 Sheet
  - 文案：「检测到旧版数据，正在迁移到新格式…」
  - 进度条：显示当前迁移进度
  - 不可取消（数据完整性保证）
  - 完成后自动关闭，进入首页
  - 迁移失败 → 显示错误 + 「重试」按钮，旧数据从备份恢复
- **App 启动集成**：在 `LumaApp` 或 `ContentView` 的 `onAppear` 中检查 `needsMigration()`，阻塞式执行迁移

## 本次明确不做

- 不做增量迁移（一次性全量迁移）
- 不删除旧 manifest.json（保留在原位作为额外备份）
- 不迁移 `EditingSession`（V4 不再使用该概念）
- 不迁移 `editSuggestions`（V4 Phase 1 不需要，后续可补）
- 不处理 Mac Photos 增量索引（Phase 2）
- 不处理 `scoring_job.json`（云端评分任务临时状态，不迁移）

## 用户主路径

1. 用户进入：首次启动 V4 版本
2. 用户看到：迁移提示「正在将旧数据迁移到新格式」+ 进度条
3. 系统反馈：逐个 Session 迁移，进度条更新
4. 用户完成：迁移完成 → 首页显示所有 Expedition（来自旧 Session）

## 页面与组件

- 需要新增的页面：`MigrationProgressView`（迁移进度弹窗）
- 需要新增的组件：`V3MigrationManager`、`MigrationEstimate`、`MigrationProgress`
- 可以复用的组件：`SessionManifest`（旧格式解码器）、`AppDirectories`（路径查找）、P1F2 的 `AssetManager`/`ExpeditionManager`

## 交互要求

- 默认状态：迁移检测发生在 App 启动时，用户无需手动触发
- 主按钮行为：无（自动迁移）
- 返回行为：迁移不可取消
- 空状态：无旧数据 → 跳过迁移，直接进入首页
- 错误状态：迁移失败 → 显示错误详情 + 重试按钮；旧数据有备份保障安全

## UI 要求

- 风格方向：简洁的全屏/sheet 迁移进度页，深色主题
- 内容：Luma 图标 + 迁移说明文案 + 进度条 + 当前迁移的 Session 名称
- 迁移完成后短暂显示成功统计（迁移了 N 个旅程、M 张照片），然后自动关闭

## 技术约束

- `SessionManifest` 解码器已经支持 v0（flat）/ v1（expedition）/ v2（session）三种格式，直接复用
- UUID 保持稳定：`MediaAsset.id` → `MasterAsset.id`，确保文件路径引用不断裂
- 跨 Session 去重：如果多个 Session 包含同一照片（同一 contentHash），只创建一个 MasterAsset，多个 ExpeditionAsset 分别引用
- 文件路径不变：旧项目目录结构（`thumbnails/`、`previews/` 等）保留不动，`MasterAsset` 的 URL 字段指向原位置
- 迁移在主线程阻塞 UI（通过 Sheet 遮罩），防止用户在迁移中操作
- 迁移事务：每个 Session 的迁移在一个 GRDB `write` 事务内完成，失败可回滚该 Session
- `migration-backup/` 目录结构：`<sessionName>_<sessionId>/manifest.json`
- 迁移标记文件格式：JSON `{ "migratedAt": "...", "sessionCount": N, "assetCount": M, "version": "4.0" }`
- 不要顺手重构无关模块

## 输出顺序

1. 先搭 `V3MigrationManager`（`needsMigration` + `estimateMigrationScope`）
2. 搭迁移核心逻辑（`performMigration`：备份 → 遍历 → 写 DB → 标记）
3. 搭 `MigrationProgressView`（进度 UI）
4. 集成到 `LumaApp` / `ContentView` 启动流程
5. 补单测（用构造的旧 manifest.json 测迁移正确性）

## 文件组织建议

```
Sources/Luma/
  Services/
    Migration/
      V3MigrationManager.swift
  Views/
    Migration/
      MigrationProgressView.swift
```

## 验收标准

- [ ] 首次启动 V4 时自动检测到旧 Session 数据
- [ ] 迁移前自动备份所有 `manifest.json` 到 `migration-backup/`
- [ ] 每个旧 Session 正确迁移为一个 Expedition
- [ ] 每个 `MediaAsset` 正确迁移为 `MasterAsset` + `ExpeditionAsset`
- [ ] `userDecision` 正确迁移到 `ExpeditionAsset.decision`
- [ ] `userRating` 正确迁移到 `ExpeditionAsset.rating`
- [ ] `aiScore` 正确迁移到 `asset_scores` 表
- [ ] `PhotoGroup` 正确迁移到 `photo_groups` + `photo_group_assets`
- [ ] `SubGroup` 正确迁移到 `photo_subgroups` + `photo_subgroup_assets`
- [ ] `ImportSession` 历史正确迁移到 `import_sessions` 表
- [ ] 跨 Session 相同照片（同 contentHash）只创建一个 MasterAsset
- [ ] 文件路径引用不断裂（缩略图/预览图/原图仍可访问）
- [ ] 迁移完成后写入标记文件，二次启动不再迁移
- [ ] 迁移失败可重试，旧数据不损坏
- [ ] 迁移进度 UI 正确显示
- [ ] 无旧数据时跳过迁移，直接进入首页
