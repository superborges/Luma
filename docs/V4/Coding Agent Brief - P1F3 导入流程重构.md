## 背景

当前要实现的是 V4 Phase 1 的导入流程重构（P1F3），目标是将旧的「新建 Import Session → 一次性导入」流程改为「在 Expedition 上下文中添加照片」，同时适配新的 MasterAsset + ExpeditionAsset 双写模式。导入时照片进入全局资产池（MasterAsset），同时建立与目标 Expedition 的关系（ExpeditionAsset）。

**前置依赖**：P1F1（数据层）+ P1F2（Expedition/资产管理）已完成。

## 本次只做

- **`AssetSourceAdapter` 协议**（替代旧 `ImportSourceAdapter`）：
  ```swift
  protocol AssetSourceAdapter {
      var source: AssetSource { get }
      var displayName: String { get }
      func enumerateAssets(options: SourceEnumerationOptions) async throws -> [DiscoveredAsset]
      func fetchThumbnail(_ asset: DiscoveredAsset, size: CGSize) async throws -> CGImage?
      func fetchPreview(_ asset: DiscoveredAsset) async throws -> URL?
      func fetchOriginal(_ asset: DiscoveredAsset) async throws -> URL?
      func supports(_ capability: SourceCapability) -> Bool
      var connectionState: AsyncStream<ConnectionState> { get }
  }
  ```
- **`DiscoveredAsset`**（替代旧 `DiscoveredItem`）：
  - `id: UUID`、`baseName: String`、`sourceKind: AssetSourceKind`、`externalIdentifier: String?`
  - `previewFileURL: URL?`、`rawFileURL: URL?`、`auxiliaryFileURL: URL?`
  - `metadata: EXIFData`、`mediaType: MediaType`
  - `suggestedStorageMode: AssetStorageMode`
  - `contentHashHint: String?`（可在枚举阶段预算）
- **`SourceEnumerationOptions`**：`dateRange: ClosedRange<Date>?`、`mediaTypeFilter: Set<MediaType>?`、`excludeIdentifiers: Set<String>?`
- **`SourceCapability` 枚举**：`read`、`writeAlbum`、`deleteAsset`、`fetchOriginal`、`fetchThumbnail`、`copyToManagedStorage`
- **`SDCardSourceAdapter`**（重构自 `SDCardAdapter`）：
  - 实现 `AssetSourceAdapter`
  - `source.kind = .sdCard`，`suggestedStorageMode = .managed`
  - 复用现有 `DCIMScanner` + `RAWJPEGPairer` + `EXIFParser`
  - `connectionState` 保留现有轮询逻辑
- **`FolderSourceAdapter`**（重构自 `FolderAdapter`）：
  - 实现 `AssetSourceAdapter`
  - 初始化时传入 `storageMode: AssetStorageMode`（由用户在 UI 选择 `.referenced` 或 `.managed`）
  - `source.kind = .localFolder`
  - 复用现有 `MediaFileScanner`
- **`ImportPipeline`**（重构自 `ImportManager`）：
  - 核心方法：`addPhotosToExpedition(adapter:expeditionId:onProgress:) async throws -> ImportResult`
  - 流程：
    1. 注册/复用 `AssetSource` → `AssetSourceManager.registerSource`
    2. `adapter.enumerateAssets()` → `[DiscoveredAsset]`
    3. 对每个 `DiscoveredAsset`：
       a. 计算 `contentHash`（managed/referenced 模式）或使用 `externalIdentifier`（Mac Photos）
       b. `AssetManager.createOrReuseMasterAsset()` → 去重，得到 `MasterAsset`
       c. `AssetManager.addAssetToExpedition(assetId:expeditionId:addedBy: .importSession(sessionId))` → 建立关系
    4. 三阶段文件拷贝（复用现有逻辑）：
       a. Phase 1：`fetchThumbnail` → 写入 `thumbnails/`
       b. Phase 2：`fetchPreview` → 写入 `previews/`（或 `managed-originals/` 子目录）
       c. Phase 3：`fetchOriginal` → 写入 `managed-originals/`（仅 `.managed` 模式）
    5. 每阶段完成后更新 `MasterAsset` 的对应 URL 字段
    6. 创建 `ImportSession` 记录
    7. 触发 `GroupingEngine.makeGroups` → 写入 `PhotoGroup`（绑定 Expedition）
  - 进度回调：`ImportProgress`（`phase`、`current`、`total`、`currentFileName`）
  - 断点续传：沿用 `ImportSessionStore` 检查点逻辑
  - 设备拔出：沿用 `ConnectionState` 暂停逻辑
- **重构 `GroupingEngine` 输入**：`makeGroups(from:)` 接受 `[MasterAsset]` 或新建一个适配方法
- **文件夹添加模式选择 UI**：在添加照片弹窗中新增「引用原位置 / 复制到 Luma」选项
- **旧 `ImportSourceAdapter` / `ImportManager` 保留但标记 `@available(*, deprecated)`**

## 本次明确不做

- 不实现 Mac Photos 导入（Phase 2 的 `MacPhotosSourceAdapter`）
- 不改选片工作台 UI（P1F4 负责）
- 不改首页导航（P1F5 负责）
- 不做数据迁移（P1F6 负责）
- 不实现 Album 相关功能

## 用户主路径

1. 用户进入：打开 Expedition → 点击「添加照片」
2. 用户操作：选择来源（SD 卡/文件夹）→ 文件夹模式下选择「引用/复制」→ 确认
3. 系统反馈：扫描文件 → 去重检测 → 三阶段拷贝（进度条）→ 自动分组
4. 用户完成：照片出现在 Expedition 中，MasterAsset 全局可见

## 页面与组件

- 需要新增的组件：`AssetSourceAdapter` 协议、`DiscoveredAsset`、`SourceEnumerationOptions`、`SDCardSourceAdapter`、`FolderSourceAdapter`、`ImportPipeline`
- 需要修改的组件：`GroupingEngine.makeGroups` 参数类型适配
- 可以复用的组件：`DCIMScanner`、`RAWJPEGPairer`、`MediaFileScanner`、`EXIFParser`、`ThumbnailCache`、`ImportSessionStore`（检查点持久化）

## 交互要求

- 默认状态：Expedition 中「添加照片」按钮始终可见
- 主按钮行为：选择来源后自动开始扫描和导入
- 返回行为：导入进行中可取消；SD 卡拔出暂停
- 空状态：来源无照片 → 提示"未检测到照片"
- 错误状态：权限不足/磁盘满/读取失败 → 具体错误 + 重试

## UI 要求

- 风格方向：添加照片弹窗复用现有深色主题 + `StitchTypography`
- 必须保留的现有风格：SD 卡检测弹窗（已有）；进度条样式
- 新增部分：文件夹模式选择（引用/复制）在添加弹窗中用 Picker 展示

## 技术约束

- `ImportPipeline` 三阶段拷贝逻辑大量复用 `ImportManager` 现有代码；差别在于：
  - 旧版写 `SessionManifest`（JSON）→ 新版写 `MasterAssetRepository` + `ExpeditionAssetRepository`（SQLite）
  - 旧版 `MediaAsset` → 新版 `MasterAsset`
  - 旧版所有数据嵌在 `Session` → 新版拆为独立表
- `.referenced` 模式下不执行 Phase 3（不拷贝原图），`MasterAsset.originalURL` 指向原位置
- `.managed` 模式下 Phase 3 拷贝到 `managed-originals/{assetId}/`
- `contentHash` 计算应在枚举阶段做（`DiscoveredAsset.contentHashHint`），避免拷贝后再算
- SD 卡并发限制 2-3（与 V3 一致）
- 原子性写入：`.importing` 临时后缀 → 完成后重命名
- 旧 `ImportManager` 暂不删除，标记 deprecated，待 P1F6 迁移完成后清理
- `GroupingEngine.makeGroups` 需要一个适配层：接受 `[MasterAsset]`，内部转为原有的输入格式（或直接修改签名）

## 输出顺序

1. 先搭 `AssetSourceAdapter` 协议 + `DiscoveredAsset` + `SourceEnumerationOptions`
2. 搭 `SDCardSourceAdapter`（从 `SDCardAdapter` 重构）
3. 搭 `FolderSourceAdapter`（从 `FolderAdapter` 重构）
4. 搭 `ImportPipeline`（核心双写逻辑）
5. 适配 `GroupingEngine` 输入类型
6. 搭文件夹模式选择 UI（简单 Picker）
7. 补单测 + 集成测试

## 文件组织建议

```
Sources/Luma/
  Services/
    Import/
      AssetSourceAdapter.swift       (新协议)
      DiscoveredAsset.swift          (新)
      SDCardSourceAdapter.swift      (重构自 SDCardAdapter.swift)
      FolderSourceAdapter.swift      (重构自 FolderAdapter.swift)
      ImportPipeline.swift           (重构自 ImportManager.swift)
      # 以下保留不动
      DCIMScanner.swift              (复用)
      RAWJPEGPairer.swift            (复用)
      MediaFileScanner.swift         (复用)
      ImportSessionStore.swift       (复用)
      ImportSourceMonitor.swift      (复用)
```

## 验收标准

- [ ] `AssetSourceAdapter` 协议定义完整，`SDCardSourceAdapter` 和 `FolderSourceAdapter` 正确实现
- [ ] `ImportPipeline.addPhotosToExpedition` 能从 SD 卡扫描 → 去重 → 创建 MasterAsset → 创建 ExpeditionAsset → 拷贝文件 → 分组
- [ ] 文件夹 `.referenced` 模式不拷贝原图，`MasterAsset.originalURL` 指向原位置
- [ ] 文件夹 `.managed` 模式拷贝原图到 `managed-originals/`
- [ ] 同一照片二次导入不重复创建 MasterAsset（去重生效）
- [ ] 导入完成后 `PhotoGroup` 正确写入数据库并关联 Expedition
- [ ] SD 卡拔出时暂停，重新插入后恢复
- [ ] 进度回调正确报告阶段和进度
- [ ] 不破坏现有编译（旧 `ImportManager` 标记 deprecated 但可编译）
