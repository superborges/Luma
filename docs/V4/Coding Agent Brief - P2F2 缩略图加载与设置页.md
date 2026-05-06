## 背景

当前要实现的是 V4 Phase 2 Feature 2（P2F2）— 缩略图加载与 Mac Photos 设置页，目标是让 externalReference 类型的 Mac Photos 资产能够在 UI 中正确显示缩略图和预览图，并提供一个设置页面管理 Mac Photos 连接。

## 本次只做

- **AssetImageProvider 协议**：统一图片加载抽象
  - `thumbnail(for:size:)` / `preview(for:size:)` → `NSImage?`
- **LocalFileImageProvider**：从磁盘加载（managed/referenced 资产），文件 I/O 通过 `Task.detached` 移至后台线程
- **PhotoKitImageProvider**：通过 `PhotosKitImageProvider.requestImage` 加载 externalReference 资产
- **AssetImageProviderFactory**：根据 `AssetStorageMode` 自动分发到正确的 provider
- **UI 改造**：
  - `DisplayImageView`：externalReference 资产通过 PhotoKit 加载预览图，显示 ProgressView 等待
  - `ThumbnailView`：externalReference 资产通过 PhotoKit 加载缩略图，显示 ProgressView 等待
  - `AssetThumbnailCell`：同上（用于网格视图）
- **MacPhotosSettingsView**：独立设置页面
  - 未连接：显示连接按钮 + 说明文案 + 错误提示
  - 已连接：显示已索引照片数、最近同步时间、索引进度条、授权状态；提供「更新索引」和「断开连接」按钮
  - 断开连接前弹确认 Alert
- **LibraryStore 封装属性**：`macPhotosIsIndexing` / `macPhotosAuthStatus`，避免 View 直接访问 MacPhotosManager

## 本次明确不做

- 不做按年/月浏览视图（P2F3 负责）
- 不做从 Mac Photos 创建 Expedition（P2F4 负责）
- 不做图片缓存策略（当前按需请求，无持久化缓存）
- 不做 PHCachingImageManager 预热（后续优化）

## 用户主路径

1. 用户点击侧栏 Mac Photos → 看到设置页
2. 连接后，在任何包含 externalReference 资产的视图中看到缩略图
3. 在设置页查看索引状态、更新索引、管理连接

## 页面与组件

- 需要新增的页面：`MacPhotosSettingsView`
- 需要新增的组件：`AssetImageProvider`、`LocalFileImageProvider`、`PhotoKitImageProvider`、`AssetImageProviderFactory`
- 可以复用的组件：`PhotosKitImageProvider`（V3 遗留）、`AssetThumbnailCell`
- 需要修改的组件：`DisplayImageView`、`ThumbnailView`、`ContentView`

## 交互要求

- 缩略图加载中显示 ProgressView（灰底 + 小 spinner）
- 连接按钮点击后显示 loading 状态
- 断开连接前弹确认 Alert
- 索引进行中显示进度条（indexed/total）

## UI 要求

- 设置页风格：暗色主题，遵循 StitchTheme
- 卡片式布局：未连接/已连接各一张卡片
- 不需要复杂装饰，信息清晰可读即可

## 技术约束

- `LocalFileImageProvider` 的 `NSImage(contentsOf:)` 必须在后台线程执行（`Task.detached`）
- `PhotoKitImageProvider` 公共方法消除重复（`loadViaPhotoKit`）
- View 层不直接访问 `macPhotosManager`，通过 `LibraryStore` 计算属性
- `DateFormatter.lumaRelative` 使用 `doesRelativeDateFormatting`

## 文件组织

```
Sources/Luma/
  Services/MacPhotos/
    AssetImageProvider.swift           # 协议 + 3 个实现 + Factory
  Views/Library/
    MacPhotosSettingsView.swift        # 设置页
  Views/MainWindow/
    ExpeditionCullingView.swift        # DisplayImageView / ThumbnailView 改造
  Views/Library/
    AllPhotosGridView.swift            # AssetThumbnailCell 改造
  Views/MainWindow/
    ContentView.swift                  # .macPhotos 路由到设置页
  App/
    LibraryStore.swift                 # 新增封装属性
```

## 验收标准

- [x] externalReference 资产在选片台显示缩略图和预览图
- [x] externalReference 资产在网格视图显示缩略图
- [x] 加载中显示 ProgressView
- [x] MacPhotosSettingsView 连接/断开/索引状态完整
- [x] View 层不直接访问 MacPhotosManager
- [x] `swift build` 通过，341 测试全部通过
