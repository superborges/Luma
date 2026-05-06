## 背景

当前要实现的是 V4 Phase 3 Feature 4（P3F4）— 导出 Action 与 Action 面板 UI。这是 Phase 3 的最后一个 Feature，负责将 V3 `ExportPanelView` 重构为统一的 Action 面板，迁移文件夹导出逻辑到 `MasterAsset`，并整合 P3F2（Photos 同步）和 P3F3（归档）的能力到统一 UI 中。

## 本次只做

- **FolderExporter 适配**（从 `MediaAsset` → `MasterAsset`）：
  - 新增 `func export(masterAssets:groups:outputPath:options:onProgress:) async throws -> ExportResult`
  - 文件命名规则（`FileNamingResolver`）保持不变
  - 目录模板保持（byDate / byGroup / byRating）
  - `externalReference` 资产：通过 PhotoKit 获取图像数据 → 写入目标目录
  - 可选 XMP sidecar（`XMPWriter` 适配到 `MasterAsset` 的 EXIF 数据）
- **SyncAlbumToPhotos Action handler**（在 `ActionRunner` 中注册）：
  - 调用 P3F2 `PhotosAlbumSyncAdapter.createAlbum/updateAlbum`
  - 通过 `AlbumManager` 读取相册资产 → 传给 adapter
- **Action 面板 UI**（替代 V3 `ExportPanelView`）：
  - `ActionPanelView`（NavigationStack + Form）：
    - Action 类型选择器：归档视频 / 低清保留 / 仅标记归档 / 导出到文件夹 / 同步相册到 Photos
    - 各类型配置区域：
      - 归档视频：输出目录、视频标题
      - 低清保留：输出目录、质量参数
      - 仅标记归档：无额外配置，显示说明文字
      - 导出到文件夹：输出目录、目录模板、命名规则、XMP 开关
      - 同步相册：选择目标相册
    - 预览统计：目标资产数、预估输出大小
    - 「执行」按钮
  - `ActionProgressView`：执行中的实时进度（进度条 + 当前处理文件名 + 已完成/总数）
  - `ActionResultView`：完成摘要（成功数 / 失败数 / 输出路径 + 「在 Finder 中显示」按钮）
- **破坏性操作确认对话框**：
  - 「清理未选照片」→ 确认弹窗："这会从当前旅程中移除照片引用，不会删除原始文件。"
  - 「覆盖 Photos 相册内容」→ 确认弹窗
  - 使用 `.confirmationDialog` 或 `.alert` 实现
- **集成**：
  - `ExpeditionCullingView` 工具栏增加「Actions」入口按钮 → 弹出 ActionPanelView sheet
  - `ContentView` 绑定 Action 面板 sheet
  - 侧栏 `LibrarySidebar`「任务」section 显示进行中/已完成的 ActionJob 列表
  - `ActionJobListView`：任务列表视图（状态图标 + 名称 + 进度/结果）
- **单元测试**：
  - `FolderExporterV4Tests`（3-4 条：MasterAsset 导出 + 目录模板 + XMP）
  - `ActionPanelIntegrationTests`（2-3 条：状态流转）

## 本次明确不做

- 不做 Lightroom 导出（Build Spec P3 验收未包含）
- 不做删除 Mac Photos 原图
- 不做生成分享包（Build Spec 暂缓）
- 不做 rerunAnalysis / regroup Action（可后续加入）
- 不做自动触发的 Action（只支持手动触发）

## 用户主路径

1. 用户在 Expedition 工作台点击工具栏「Actions」按钮
2. Action 面板弹出，选择操作类型
3. 配置参数（如输出目录、质量等）
4. 查看预览统计，点击「执行」
5. 破坏性操作弹出确认对话框
6. 执行中显示进度
7. 完成后显示结果摘要，可在 Finder 中打开输出目录
8. 侧栏「任务」section 可查看历史 Action

## 页面与组件

- 需要新增的页面：`ActionPanelView`、`ActionProgressView`、`ActionResultView`、`ActionJobListView`
- 需要修改的页面：`ExpeditionCullingView`（工具栏）、`ContentView`（sheet 绑定）、`LibrarySidebar`（任务 section）
- 可以复用的组件：`FolderExporter`（适配）、`XMPWriter`（适配）、`FileNamingResolver`、`ActionRunner`（P3F3）、`PhotosAlbumSyncAdapter`（P3F2）

## 技术约束

- `ActionPanelView` 通过 `ExpeditionWorkspaceStore` 获取当前 Expedition 上下文和可操作资产
- 进度更新使用 `@Observable` 状态驱动 UI，`ActionRunner` 的进度回调在主线程分发
- 导出文件夹选择使用 `NSOpenPanel`（macOS 标准选择面板）
- 「在 Finder 中显示」使用 `NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath:)`
- `FolderExporter` 适配后保持 `Sendable`，文件 I/O 在后台线程
- `externalReference` 资产导出时需临时获取原图数据（通过 PhotoKit `requestImageDataAndOrientation`）
- Action 面板的配置项尽量复用 V3 `ExportOptions` 中的字段定义，避免重复定义

## 文件组织

```
Sources/Luma/
  Services/Export/
    FolderExporter.swift          # 扩展 MasterAsset 适配方法
    XMPWriter.swift               # 扩展 MasterAsset 适配方法
  Services/Action/
    ActionRunner.swift            # 扩展 exportToFolder + syncAlbumToPhotos handler
  Views/Action/
    ActionPanelView.swift         # 统一 Action 面板（替代 ExportPanelView）
    ActionProgressView.swift      # 进度显示
    ActionResultView.swift        # 结果摘要
    ActionJobListView.swift       # 任务列表
  Views/MainWindow/
    ExpeditionCullingView.swift   # 工具栏增加 Actions 入口
    ContentView.swift             # 绑定 ActionPanel sheet
  Views/Library/
    LibrarySidebar.swift          # 增加任务 section
Tests/LumaTests/
  FolderExporterV4Tests.swift     # 3-4 条
  ActionPanelIntegrationTests.swift # 2-3 条
```

## 验收标准

- [ ] FolderExporter 能接受 MasterAsset 输入导出到指定文件夹
- [ ] XMP sidecar 能正确写入 MasterAsset 的 EXIF 数据
- [ ] externalReference 资产能成功导出（通过 PhotoKit 获取图像数据）
- [ ] Action 面板 UI 可选择所有 5 种 Action 类型
- [ ] 各 Action 类型的配置项正确渲染
- [ ] 执行归档/导出时有实时进度显示
- [ ] 完成后显示结果摘要 + 可在 Finder 中打开
- [ ] 破坏性操作弹出二次确认对话框
- [ ] 侧栏「任务」section 显示进行中和已完成的 ActionJob
- [ ] 5-7 条单测全部通过
- [ ] `swift build` 通过，不破坏现有测试
