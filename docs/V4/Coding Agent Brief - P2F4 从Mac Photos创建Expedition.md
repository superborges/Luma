## 背景

当前要实现的是 V4 Phase 2 Feature 4（P2F4）— 从 Mac Photos 创建普通 Expedition，目标是让用户能够从已索引的 Mac Photos 资产中按时间范围或系统相册选择照片，创建一个普通 Expedition 进行选片工作。创建后 ExpeditionAsset 引用已有 MasterAsset，不复制原图。

## 本次只做

- **创建 Expedition 入口**：
  - 在 MacPhotosBrowseView 中添加「从 Mac Photos 创建旅程」按钮
  - 在 CreateExpeditionSheet 中添加 Mac Photos 来源选项（当已连接时）
- **时间范围选择器**：
  - 日期范围 picker（起止日期）
  - 预览选中范围内的照片数量
- **系统相册选择**：
  - 列出 Mac Photos 系统相册（通过 `MacPhotosManager.fetchCollections()`）
  - 勾选一个或多个相册
  - 预览选中相册内的照片数量
- **创建流程**：
  - 根据选择条件查询符合的 MasterAsset
  - 创建普通 Expedition（sourceMode = .macPhotos，但 isMacPhotos = false）
  - 批量创建 ExpeditionAsset 引用
  - 自动打开新建的 Expedition
- **LibraryStore 方法**：
  - `createExpeditionFromMacPhotos(name:assetIds:)` → 创建 Expedition + 批量 ExpeditionAsset
  - `fetchMacPhotosAssetsByDateRange(from:to:)` → 按时间范围查询
  - `fetchMacPhotosAssetsByCollections(collectionIds:)` → 按相册查询

## 本次明确不做

- 不做搜索/关键词筛选
- 不做 GPS 地点圈选
- 不做拖拽选择
- 不复制原图到 managed 存储
- 不支持跨来源混合创建（仅 Mac Photos → Expedition）

## 用户主路径

1. 用户在 MacPhotosBrowseView 点击「创建旅程」
2. 弹出创建面板，选择创建方式：按时间范围 / 按系统相册
3. 设置时间范围或勾选相册，实时预览照片数量
4. 输入旅程名称，点击「创建」
5. 系统创建 Expedition + ExpeditionAsset，自动跳转到新旅程

## 页面与组件

- 需要新增的页面：`MacPhotosExpeditionCreatorSheet`
- 需要新增的组件：日期范围选择器、相册列表多选
- 可以复用的组件：`CreateExpeditionSheet`（可扩展）、`MacPhotosManager.fetchCollections()`
- 需要修改的组件：`MacPhotosBrowseView`（添加入口）、`LibraryStore`（新增方法）

## 交互要求

- 默认状态：选择创建方式（时间范围 / 系统相册），默认时间范围为最近 30 天
- 主按钮行为：「创建旅程」→ 创建 + 跳转
- 次按钮行为：「取消」→ 关闭 sheet
- 空状态：当选择范围内无照片时禁用创建按钮，提示「所选范围内无照片」
- 错误状态：创建失败时显示错误提示

## UI 要求

- 暗色主题，遵循 StitchTheme
- Sheet 形式弹出，宽度约 500pt
- 实时照片数量预览使用大字体醒目显示
- 相册列表带缩略图（可选）和照片数量

## 技术约束

- ExpeditionAsset 创建使用事务批量写入（GRDB transaction）
- 时间范围查询走 `captureDate` 列索引
- 系统相册查询通过 `MacPhotosManager.assetIdentifiers(in:)` 获取 localIdentifier，再匹配 MasterAsset.externalIdentifier
- 新建 Expedition 的 sourceMode 为 `.macPhotos`，但 `isMacPhotos = false`（区别于系统级特殊 Expedition）
- `storageMode` 保持 `.externalReference`（不复制原图）

## 文件组织

```
Sources/Luma/
  Views/Library/
    MacPhotosExpeditionCreatorSheet.swift  # 新建：创建面板
    MacPhotosBrowseView.swift              # 修改：添加创建入口
  Database/Repositories/
    MasterAssetRepository.swift            # 新增按时间范围/externalId 批量查询
  App/
    LibraryStore.swift                     # 新增 createExpeditionFromMacPhotos 等方法
```

## 验收标准

- [x] 从 MacPhotosBrowseView 可打开创建面板
- [x] 按时间范围筛选照片数量实时预览
- [x] 按系统相册筛选照片数量实时预览
- [x] 创建后生成正确的 Expedition + ExpeditionAsset
- [x] 新建 Expedition 不标记 isMacPhotos（可正常删除）
- [x] 创建后自动跳转到新旅程
- [x] 空选择时禁用创建按钮
- [x] `swift build` 通过，341 测试全部通过
