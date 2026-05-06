# Luma（拾光）— 产品规格说明书

> **文档状态（V4）**  
> 本文档描述 Luma（拾光）从「导入后选片工具」升级为「轻量级照片管理中心」后的最新产品规格。  
>
> V1–V3 已实现的核心能力包括：  
> `Ingest → Group → Score → Cull → Export / Archive` 五阶段管线，以及 SD 卡 / 文件夹 / Photos Library 适配、AI 评分、分组、选片、导出与归档等能力。  
>
> V4 的核心变化是：  
> **Import Session 不再是主工作对象，Expedition 成为 Luma 的核心组织单位；Source 与 Storage Mode 明确分离；Mac Photos 改为全局授权绑定后的系统级特殊 Expedition；V4 仅支持图片资产；V3 已实现的 Mac Photos 相册回写能力升级为 Photos-backed Album 同步能力；Export 模块重构为 Expedition / Album Actions。**

---

## 0. V4 产品方向变更

### 0.1 从选片工具升级为照片管理中心

Luma 最初的核心目标是帮助用户在旅行归来后快速完成一批照片的选片流程。  
随着 V1–V3 的管线能力落地，新的产品方向是：

> **Luma 是一个本地优先、以 Expedition 为核心组织单位的轻量级照片管理与选片中心。**

新的核心心智不再是：

```text
导入一批照片 → 选片 → 导出到 Lightroom
```

而是：

```text
管理照片来源 → 创建 / 进入 Expedition → 添加或引用照片 → 分组与选片 → 构建相册 → 执行 Actions
```

### 0.2 V4 核心变化

1. **Expedition 成为主工作对象**  
   一次旅行、一段时间、一组摄影项目，都会被组织为一个 Expedition。

2. **Import Session 降级为导入记录**  
   Import Session 只记录某次照片进入 Luma 的行为，不再作为长期整理入口。

3. **照片实体全局唯一**  
   多次从 SD 卡、本地目录或 Mac Photos 添加 / 引用的照片，会进入统一的 Luma Library。  
   Expedition 不拥有照片实体，只引用照片，并保存该 Expedition 下的分组、选片、相册和任务状态。

4. **Source 与 Storage Mode 分离**  
   Source 表示照片来自哪里，例如 Mac Photos、SD 卡、本地文件夹。  
   Storage Mode 表示照片如何被 Luma 管理，例如引用外部资源、引用本地原位置、复制到 Luma 托管目录。  
   `Luma Managed Storage` 不是用户可见的 Source，而是内部存储策略。

5. **Mac Photos 是全局绑定后的系统级特殊 Expedition**  
   Mac Photos 不再是“添加照片”的入口。  
   用户只需要在 Luma 中完成一次全局授权绑定，Luma 就会生成一个特殊的 Mac Photos Expedition。  
   该 Expedition 尽量复用 PhotoKit 系统资源，例如 `PHCachingImageManager`、PHAsset 引用和系统相册能力，不默认复制原图。

6. **V4 仅支持图片资产**  
   V4 支持 JPG / JPEG / PNG / HEIC / RAW + JPEG / ProRAW DNG / Live Photo。  
   Live Photo 作为图片资产 + auxiliary MOV 处理。  
   普通视频资产（MOV / MP4 / 相机视频 / iPhone 视频）不作为 V4 的一等资产，留到 V5。

7. **V1-V3 Mac Photos 相册回写能力继续复用**  
   V1-V3 已实现的 Mac 相册回写能力不废弃。  
   在 V4 中，它从“导出到相册”升级为 `Photos-backed Album` 的同步能力。

8. **Export 重构为 Action System**  
   不再以 Lightroom 为默认出口。  
   Luma 自身就是照片整理中心。  
   导出副本、归档、清理、生成视频、创建 / 更新 Photos 相册等都变为 Expedition / Album 上的 Actions。

### 0.3 V4 设计原则

- **照片只存一份，集合只保存引用。**
- **Source 表示来源，Storage Mode 表示存储策略。**
- **Expedition 表达语义，Import Session 表达来源历史。**
- **Mac Photos 全局授权绑定，只引用不导入。**
- **Mac Photos 优先复用系统资源，不默认复制原图。**
- **选片结果属于 Expedition 上下文，而不是全局照片本体。**
- **V4 只处理图片资产，视频作为 V5 规划。**
- **V3 的 Mac Photos 相册回写能力作为 Album Sync 能力复用。**
- **所有破坏性操作必须二次确认。**
- **第一阶段谨慎处理 Mac Photos 删除与清理，不做默认批量删除。**

---

## 1. 产品概述

### 1.1 定位

Luma（拾光）是一款 macOS 原生桌面应用，面向摄影爱好者与重度照片用户，提供本地优先的照片管理、分组、选片、相册构建和归档能力。

它介于 Apple Photos 与 Lightroom 之间：

- 比 Apple Photos 更适合做照片筛选、相似照片分组和旅行整理。
- 比 Lightroom 更轻量、更本地、更聚焦「照片集合管理与选片」。
- 支持 Mac Photos 引用工作流，也支持 SD 卡 / 本地文件夹照片进入 Luma 管理体系。
- 不把 Lightroom 作为默认出口；Luma 本身就是轻量级照片管理中心。

### 1.2 新核心工作流

```text
Library → Source / Storage → Expedition → Group / Cull → Album → Actions
资料库     来源 / 存储策略       旅程/项目       分组/选片       相册      操作
```

### 1.3 目标用户

- 使用相机 + iPhone 拍摄的摄影爱好者
- 一次旅行或活动产生 300–3000 张照片
- 既有 SD 卡 / 本地目录素材，也有大量 Mac Photos 中的 iPhone 照片
- 想要一个比 Photos 更会选片、比 Lightroom 更轻量的个人照片中心
- 不希望每次整理都产生多份原图副本
- 希望在 Mac Photos 上构建更强的相册、分组和精选工作流

### 1.4 核心产品对象

| 概念 | 用户文案 | 说明 |
|---|---|---|
| Library | 资料库 | Luma 的全局照片空间 |
| Asset Source | 照片来源 | Mac Photos、SD 卡、本地文件夹 |
| Storage Mode | 存储方式 | 外部引用、本地引用、Luma 托管 |
| MasterAsset | 照片 | 全局唯一的照片实体或引用 |
| Expedition | 旅程 / 项目 | 一次旅行、一段时间、一组摄影项目 |
| ExpeditionAsset | 旅程中的照片 | 某张照片在某个 Expedition 中的关系与状态 |
| ImportSession | 导入记录 | 一次从 SD 卡 / 文件夹添加照片的历史记录 |
| Album | 相册 | 手动相册、智能相册或 Photos-backed 相册 |
| AlbumSync | 相册同步 | Luma 相册与外部相册系统的同步能力 |
| ActionJob | 任务 | 归档、导出副本、生成视频、写回 Photos 等操作 |

### 1.5 技术栈

- 语言：Swift
- UI 框架：SwiftUI / 必要时使用 AppKit 兜底
- 最低系统要求：macOS 14 Sonoma
- 优先平台：Apple Silicon（M1+）
- 关键系统框架：
  - PhotoKit
  - Vision
  - Core ML
  - Core Image
  - AVFoundation
  - DiskArbitration
  - SQLite / SwiftData（具体实现以当前项目为准）

---

## 2. 资料库、照片来源与存储方式（Library, Sources & Storage）

### 2.1 Luma Library

Luma Library 是全局照片资产池，负责管理所有照片实体或外部照片引用。

用户在左侧导航中可以看到：

```text
资料库
  所有照片
  Mac Photos
  最近添加
  未整理
```

其中：

- **所有照片**：全局 MasterAsset 视图。
- **Mac Photos**：系统照片库引用视图，同时是一个系统级特殊 Expedition。
- **最近添加**：按加入 Luma 的时间排序。
- **未整理**：尚未加入任何 Expedition，或尚未完成整理的照片。

### 2.2 Source 类型

Luma 支持以下照片来源：

| Source | 是否用户可见 | 说明 |
|---|---:|---|
| Mac Photos | 是 | 系统 Photos Library，全局授权绑定后引用 |
| SD 卡 | 是 | 临时外部来源，通常复制到 Luma 托管目录 |
| 本地文件夹 | 是 | 可引用原位置，也可复制到 Luma |
| Luma Managed Storage | 否 | 内部托管存储位置，不是 Source |

### 2.3 Storage Mode

`Storage Mode` 表示照片在 Luma 中如何被管理。

| Storage Mode | 说明 | 典型来源 |
|---|---|---|
| externalReference | 外部系统引用，不复制原图 | Mac Photos |
| referenced | 引用本地原位置 | 本地文件夹 |
| managed | 复制到 Luma 托管目录 | SD 卡 / 用户选择复制的本地文件夹 |

```swift
enum AssetSourceKind: Codable {
    case macPhotos
    case localFolder
    case sdCard
}

enum AssetStorageMode: Codable {
    case externalReference   // 如 Mac Photos PHAsset 引用
    case referenced          // 引用本地原位置
    case managed             // 复制到 Luma 托管目录
}
```

### 2.4 AssetSource 数据结构【推荐】

```swift
struct AssetSource: Identifiable, Codable {
    let id: UUID

    var kind: AssetSourceKind
    var displayName: String
    var rootIdentifier: String

    // 能力声明
    var isMutable: Bool
    var supportsDelete: Bool
    var supportsAlbumWrite: Bool
    var supportsOriginalAccess: Bool

    var createdAt: Date
    var updatedAt: Date
}
```

### 2.5 Source 能力约束

#### Mac Photos

- 使用 `PHAsset.localIdentifier` 作为外部引用。
- 默认不复制原图。
- 可读取缩略图、元数据、相册信息。
- 可创建 / 更新 Photos 相册。
- 删除 Photos 原图属于高风险破坏性操作，v4 第一阶段不默认支持。
- 存储方式为 `externalReference`。

#### SD 卡

- SD 卡会被拔出，不适合长期引用。
- 默认复制到 Luma Managed Storage。
- ImportSession 记录导入过程。
- MasterAsset 记录本地托管路径。
- 存储方式为 `managed`。

#### 本地文件夹

用户添加本地文件夹时，必须选择：

```text
1. 引用原位置
2. 复制到 Luma 管理
```

两种模式区别：

| 模式 | Storage Mode | 优点 | 风险 |
|---|---|---|---|
| 引用原位置 | referenced | 省空间 | 文件移动后引用失效 |
| 复制到 Luma | managed | 稳定可控 | 占用额外空间 |

### 2.6 Source Adapter 协议【推荐】

旧版 `ImportSourceAdapter` 升级为更通用的 `AssetSourceAdapter`。

```swift
protocol AssetSourceAdapter {
    var source: AssetSource { get }
    var displayName: String { get }

    func enumerateAssets(options: SourceEnumerationOptions) async throws -> [DiscoveredAsset]
    func fetchThumbnail(_ asset: DiscoveredAsset, size: CGSize) async throws -> CGImage?
    func fetchPreview(_ asset: DiscoveredAsset) async throws -> URL?
    func fetchOriginal(_ asset: DiscoveredAsset) async throws -> URL?

    func supports(_ capability: SourceCapability) -> Bool
}
```

```swift
enum SourceCapability {
    case read
    case writeAlbum
    case deleteAsset
    case fetchOriginal
    case fetchThumbnail
    case copyToManagedStorage
}
```

---

## 3. Expedition 管理

### 3.1 Expedition 定位

Expedition 是 Luma 的核心工作空间。

它可以表示：

- 一次旅行
- 一个周末拍摄
- 一段时间的照片
- 一个摄影项目
- 一个年度精选
- 一个 Mac Photos 的引用集合

用户实际进入和整理的对象是 Expedition，而不是 ImportSession。

### 3.2 Expedition 创建方式

创建 Expedition 时，需要支持「手动创建」和「智能圈选」两类方式。

#### 方式 A：空 Expedition

```text
创建旅程 → 命名 → 之后手动添加照片
```

适合：

- 用户准备从 SD 卡添加照片
- 用户有明确项目名
- 用户希望后续逐步维护

#### 方式 B：智能创建 Expedition

```text
创建旅程 → 选择规则 → 系统预览匹配照片 → 创建
```

可选规则：

- 从时间范围创建
- 从 Mac Photos 时间范围创建
- 从 Mac Photos 系统相册创建
- 从地点创建（依赖 GPS，后续增强）
- 从最近添加创建
- 从已有照片筛选结果创建

#### V4 MVP 需要支持

- 空 Expedition
- 从 SD 卡 / 文件夹添加照片后创建 Expedition
- 从 Mac Photos 时间范围创建 Expedition

#### V4 暂缓

- 复杂地点圈选
- 复杂智能规则编辑器
- 自动识别“某次旅行”的全自动 Expedition 创建

### 3.3 Expedition 用户能力

用户可以：

- 创建 Expedition
- 智能圈选照片创建 Expedition
- 重命名 Expedition
- 设置封面
- 设置时间范围
- 添加照片
- 从 Expedition 移除照片引用
- 查看 Expedition 摘要
- 进入分组选片工作台
- 创建 Expedition 内相册
- 执行 Expedition Actions
- 删除 Expedition

删除 Expedition 默认只删除集合关系，不删除原图。

### 3.4 Expedition 数据结构【推荐】

```swift
struct Expedition: Identifiable, Codable {
    let id: UUID

    var name: String
    var subtitle: String?
    var description: String?

    var coverAssetId: UUID?

    var startDate: Date?
    var endDate: Date?

    var sourceMode: ExpeditionSourceMode

    var status: ExpeditionStatus

    var createdAt: Date
    var updatedAt: Date
}
```

```swift
enum ExpeditionSourceMode: Codable {
    case managedImport
    case folderReference
    case macPhotosReference
    case mixed
}

enum ExpeditionStatus: Codable {
    case empty
    case importing
    case indexing
    case readyToAnalyze
    case analyzing
    case reviewing
    case completed
    case needsAttention
    case error
}
```

### 3.5 特殊 Expedition：Mac Photos

Mac Photos 在 Luma 中表现为一个全局系统级特殊 Expedition：

```text
Expedition:
  name = "Mac Photos"
  sourceMode = .macPhotosReference
```

其特性：

- 用户不需要手动创建。
- 用户完成全局 Photos 授权绑定后自动出现。
- 不需要导入。
- 首次访问时建立本地索引与轻量缓存。
- 不复制原图。
- Luma 的评分、分组、选片、相册关系保存在本地数据库。
- 可根据 Luma 相册创建或更新系统 Photos 相册。
- 不应作为普通 Expedition 删除。
- 删除 / 清理类操作需独立开关和强确认。

### 3.6 ExpeditionAsset【推荐】

Expedition 不直接拥有照片实体，而是通过 ExpeditionAsset 引用 MasterAsset。

```swift
struct ExpeditionAsset: Identifiable, Codable {
    let id: UUID

    var expeditionId: UUID
    var assetId: UUID

    var addedAt: Date
    var addedBy: AssetAddedBy

    var localOrder: Int?

    // Expedition-scoped 状态
    var decision: Decision
    var rating: Int?
    var colorLabel: String?

    var isRecommended: Bool
    var isBestInGroup: Bool
    var isUserOverride: Bool

    var isArchived: Bool
    var isHiddenInExpedition: Bool

    var updatedAt: Date
}
```

```swift
enum AssetAddedBy: Codable {
    case importSession(UUID)
    case manualAdd
    case smartRule
    case photosAlbumReference(String)
    case macPhotosBinding
}
```

### 3.7 为什么 Decision 属于 ExpeditionAsset

同一张照片在不同 Expedition 中可以有不同意义：

```text
照片 A
  在「日本关西 2026」中：已选
  在「2026 年精选」中：未处理
  在「人像练习」中：不选
```

因此：

- MasterAsset 保存照片本体信息。
- ExpeditionAsset 保存这张照片在当前 Expedition 中的状态。

---

## 4. 添加照片、Mac Photos 绑定与导入记录

### 4.1 交互命名

用户界面中不再突出 “Import Session”。

普通 Expedition 中的主操作是：

```text
添加照片
```

用户可选择：

```text
从 SD 卡添加
从文件夹添加
```

Mac Photos 不放在“添加照片”里，而是一个全局绑定入口：

```text
连接 Mac Photos
```

### 4.2 添加照片的内部流程

从 Expedition 发起添加时，系统执行两件事：

```text
1. 如果照片库中没有这张照片：创建 MasterAsset
2. 将照片加入当前 Expedition：创建 ExpeditionAsset
```

### 4.3 SD 卡添加

```text
SD Card
  ↓ copy
Luma Managed Storage
  ↓ create / reuse MasterAsset
  ↓ create ExpeditionAsset
  ↓ record ImportSession
```

规则：

- 默认复制原图与 JPEG / HEIC 预览到 Luma 管理目录。
- 支持 RAW + JPEG 配对。
- 支持断点续传。
- 支持重复检测。
- SD 卡拔出时任务暂停，重新插入后可继续。

### 4.4 文件夹添加

用户选择文件夹后，必须选择：

```text
引用原位置
复制到 Luma
```

#### 引用原位置

```text
Folder File
  ↓ reference
MasterAsset(originalURL, storageMode: .referenced)
  ↓ ExpeditionAsset
```

#### 复制到 Luma

```text
Folder File
  ↓ copy
Luma Managed Storage
  ↓ MasterAsset(localManagedURL, storageMode: .managed)
  ↓ ExpeditionAsset
```

### 4.5 Mac Photos 全局绑定

Mac Photos 不执行“添加”或“导入”。

正确流程：

```text
首次打开 Luma / 设置中
  ↓
点击「连接 Mac Photos」
  ↓
系统弹出 Photos 权限授权
  ↓
授权成功
  ↓
Luma 建立 PHAsset 引用索引
  ↓
左侧出现「Mac Photos」
  ↓
自动生成特殊 Mac Photos Expedition
```

### 4.6 Mac Photos 存储策略

```text
Mac Photos Storage Policy:
- original: never copy by default
- thumbnail: use PHCachingImageManager
- preview: request on demand
- analysis input: temporary file or in-memory image
- persistent data: only Luma metadata, scores, groups, decisions, albums
```

规则：

- 不默认复制原图。
- 不默认复制全尺寸 preview。
- 缩略图优先使用 `PHCachingImageManager`。
- 可见区域按需请求缩略图。
- 大图预览按需请求。
- AI 分析需要图像数据时，临时请求 image data 或生成临时文件。
- Luma 只持久化自己的元数据、评分、分组、判定和相册关系。

### 4.7 从 Mac Photos 创建普通 Expedition

虽然 Mac Photos 不走“添加”，但用户可以基于 Mac Photos 创建普通 Expedition：

```text
Mac Photos
  ↓
按时间范围 / 系统相册 / 搜索结果选择照片
  ↓
创建 Expedition
  ↓
ExpeditionAsset 引用这些 MasterAsset
```

此时依然不复制原图。

### 4.8 ImportSession【推荐】

ImportSession 只记录 SD 卡 / 文件夹等添加照片的历史。

```swift
struct ImportSession: Identifiable, Codable {
    let id: UUID

    var sourceId: UUID
    var targetExpeditionId: UUID?

    var startedAt: Date
    var completedAt: Date?

    var importedAssetIds: [UUID]
    var skippedAssetIds: [UUID]
    var failedItems: [ImportFailure]

    var status: ImportSessionStatus
}
```

```swift
enum ImportSessionStatus: Codable {
    case pending
    case running
    case paused
    case completed
    case failed
    case cancelled
}
```

ImportSession 用于：

- 恢复导入
- 查看历史
- 排查失败
- 防止重复导入
- 记录来源

它不再作为主要工作台入口。

---

## 5. 全局照片资产模型（MasterAsset）

### 5.1 MasterAsset 定位

MasterAsset 是 Luma 中的全局照片实体或外部照片引用。

一个 MasterAsset 可以属于多个 Expedition / Album，但照片本体只存一份。

### 5.2 MasterAsset 数据结构【推荐】

```swift
struct MasterAsset: Identifiable, Codable {
    let id: UUID

    var sourceId: UUID
    var sourceKind: AssetSourceKind
    var storageMode: AssetStorageMode

    // 外部来源标识
    var externalIdentifier: String?         // 如 PHAsset.localIdentifier
    var originalURL: URL?                   // 引用原位置
    var localManagedURL: URL?               // Luma 管理目录中的原图

    // 配对文件
    var previewURL: URL?
    var rawURL: URL?
    var livePhotoVideoURL: URL?

    // 缓存
    var thumbnailCacheURL: URL?
    var previewCacheURL: URL?

    // 去重与定位
    var fingerprint: String?
    var contentHash: String?

    // 元数据
    var baseName: String
    var metadata: EXIFData?
    var mediaType: MediaType

    var createdAt: Date
    var updatedAt: Date
}
```

### 5.3 MediaType

v4 只支持图片资产。  
Live Photo 作为图片资产 + auxiliary MOV 处理。  
普通视频资产不作为一等资产。

```swift
enum MediaType: Codable {
    case photo
    case rawPlusJpeg
    case livePhoto
    case portrait
    case unknown
}
```

### 5.4 V4 支持的文件类型

V4 支持：

- JPG / JPEG
- PNG
- HEIC
- RAW + JPEG 配对
- ProRAW DNG
- Live Photo（HEIC + MOV 辅助资源）

V4 不支持作为一等资产：

- MOV
- MP4
- 相机视频
- iPhone 普通视频
- 视频选片
- 视频归档
- 视频与照片混合 Expedition

### 5.5 EXIFData【推荐】

```swift
struct EXIFData: Codable {
    let captureDate: Date?
    let gpsCoordinate: Coordinate?
    let focalLength: Double?
    let aperture: Double?
    let shutterSpeed: String?
    let iso: Int?
    let cameraModel: String?
    let lensModel: String?
    let imageWidth: Int?
    let imageHeight: Int?
}
```

### 5.6 全局去重规则

为了避免多次导入产生多份照片，Luma 应维护全局去重策略：

优先级：

1. Mac Photos：`PHAsset.localIdentifier`
2. Luma managed / folder：内容 hash
3. RAW + JPEG：baseName + captureDate + file size / EXIF
4. 视觉相似度：仅用于提示，不自动判定为同一实体

### 5.7 存储原则

硬规则：

```text
MasterAsset owns file/reference.
ImportSession owns import history.
Expedition owns meaning.
ExpeditionAsset owns per-expedition decision state.
Source tells where the asset came from.
StorageMode tells how Luma stores or references it.
```

---

## 6. 智能分组模块（Group）

### 6.1 Group 的上下文变化

旧版分组基于 Import Session。  
v4 起，分组必须基于 Expedition。

同一张照片在多个 Expedition 中可以参与不同分组。

### 6.2 分组层级

```text
Expedition
  └── PhotoGroup
        └── SubGroup
              └── ExpeditionAsset
```

### 6.3 三层分组策略

#### 第一层：时间聚类

- 按 captureDate 排序。
- 相邻照片时间差超过阈值则拆成新组。
- 默认阈值：30 分钟。
- 阈值可根据拍摄密度调整。

#### 第二层：GPS 空间聚类

- 有 GPS 时，在时间组内做空间聚类。
- 解决同一天多个地点的问题。
- 可用于命名，如「清水寺」「伏见稻荷」。

#### 第三层：视觉相似度细分

- 在时间 + 空间组内识别相似构图或连拍。
- 使用 Vision Feature Print 或现有相似度能力。
- 视觉相似子组用于“多选一”的精细选片。

### 6.4 PhotoGroup 数据结构【推荐】

```swift
struct PhotoGroup: Identifiable, Codable {
    let id: UUID

    var expeditionId: UUID

    var name: String
    var assetIds: [UUID]

    var subGroups: [PhotoSubGroup]

    var timeRange: ClosedRange<Date>?
    var location: Coordinate?

    var groupComment: String?
    var recommendedAssetIds: [UUID]

    var reviewed: Bool
    var createdAt: Date
    var updatedAt: Date
}
```

```swift
struct PhotoSubGroup: Identifiable, Codable {
    let id: UUID

    var groupId: UUID
    var assetIds: [UUID]

    var bestAssetId: UUID?
    var recommendedAssetId: UUID?
    var reasonSummary: String?

    var reviewed: Bool
}
```

### 6.5 分组合并与拆分

v4 需要支持基础的分组编辑：

- 合并相邻组
- 拆分组
- 从组中移除照片
- 将照片移动到另一组
- 设定组名
- 设定组封面

这些编辑只影响当前 Expedition，不改变 MasterAsset。

---

## 7. 评分与推荐模块（Score）

### 7.1 Score 的上下文

Luma 的评分分两类：

1. **Asset-level score**  
   和照片本体相关，例如清晰度、曝光、闭眼、技术质量。

2. **Expedition-level recommendation**  
   和当前 Expedition 上下文相关，例如是否适合作为本组最佳、是否值得进入当前旅程精选。

### 7.2 本地评分

本地评分能力保留：

- 模糊检测
- 曝光评估
- 人脸检测
- 闭眼风险
- 视觉特征提取
- 相似度计算

### 7.3 云端评分

云端 Vision API 评分能力保留，但应从“导入后评分”转为“按 Expedition / Group 触发评分”。

触发方式：

- 添加照片后自动轻量评分
- Expedition 分组完成后批量评分
- 用户手动重新评分
- 用户对某个 Group / Album 发起精评
- Mac Photos 资产按需临时请求图像数据进行评分，不持久复制原图

### 7.4 AIScore【推荐】

```swift
struct AIScore: Codable {
    let provider: String
    let scores: PhotoScores
    let overall: Int
    let comment: String
    let recommended: Bool
    let timestamp: Date
}
```

```swift
struct PhotoScores: Codable {
    let composition: Int
    let exposure: Int
    let color: Int
    let sharpness: Int
    let story: Int
}
```

### 7.5 Recommendation【推荐】

新增 Expedition 级推荐结果：

```swift
struct ExpeditionRecommendation: Identifiable, Codable {
    let id: UUID

    var expeditionId: UUID
    var assetId: UUID
    var groupId: UUID?

    var recommendationType: RecommendationType
    var score: Int
    var reason: String

    var createdAt: Date
}
```

```swift
enum RecommendationType: Codable {
    case bestInGroup
    case strongPick
    case rejectCandidate
    case cleanupCandidate
    case albumCandidate
}
```

---

## 8. 人工挑选模块（Cull）

### 8.1 工作台上下文

Cull 工作台绑定 Expedition。

用户进入 Expedition 后，可以在以下视图中整理照片：

- 网格视图
- 分组选片
- 对比视图
- 人脸检查
- 故事浏览

### 8.2 左侧导航

Expedition 内部左侧导航建议：

```text
当前旅程
  全部照片
  AI 推荐
  已选
  未选
  未审
  可清理
  已归档

分组
  清水寺日落
  伏见稻荷
  京都街拍

相册
  精选
  发朋友圈
  待修图
```

### 8.3 三栏界面

| 左栏 | 中栏 | 右栏 |
|---|---|---|
| Expedition 导航、分组、相册 | 照片网格 / 分组选片 / 对比 / 人脸检查 | AI 评分、EXIF、推荐理由、相册关系 |

### 8.4 快捷键

| 快捷键 | 功能 |
|---|---|
| `P` | 标记已选 |
| `X` | 标记未选 |
| `U` | 撤销标记，回到未处理 |
| `→` / `←` | 下一张 / 上一张 |
| `↑` / `↓` | 上一组 / 下一组 |
| `Space` | 放大 / 人脸检查 |
| `1-5` | 星级 |
| `Cmd+A` | 选中当前组 AI 推荐照片 |
| `Tab` | 跳转到下一未审组 |

### 8.5 Decision

```swift
enum Decision: Codable {
    case pending
    case picked
    case rejected
}
```

Decision 存在于 ExpeditionAsset 上。

### 8.6 选片状态规则

- 用户标记 `picked` 后，该照片进入当前 Expedition 的「已选」视图。
- 用户标记 `rejected` 后，该照片进入当前 Expedition 的「未选」视图。
- `pending` 表示未处理。
- AI 推荐不等于最终已选，必须允许用户覆盖。
- 人工覆盖应记录 `isUserOverride = true`。

### 8.7 可清理候选

Luma 可以生成“可清理候选”智能列表，但不直接删除：

- 高度重复
- 模糊
- 闭眼
- 低分
- 已归档
- 用户明确标记未选

第一阶段 UI 文案应使用：

```text
可清理候选
```

避免直接使用：

```text
删除建议
```

---

## 9. Album / Collection 管理

### 9.1 Album 定位

Album 是 Expedition 或 Library 上的照片集合。

它只保存引用，不复制照片。

### 9.2 Album 类型

```swift
enum AlbumKind: Codable {
    case manual
    case smart
    case photosBacked
}
```

#### 手动相册

用户手动创建和维护。

示例：

- 京都精选
- 发朋友圈
- 人像
- 黑白候选

#### 智能相册

按规则自动生成。

示例：

- AI 推荐
- 已选
- 高分照片
- 有人脸
- 可清理
- 未审
- 已归档

#### Photos-backed 相册

对应系统 Photos 中的相册。

示例：

- Luma 精选 2026
- 日本关西 2026 精选
- 家庭合影候选

### 9.3 Album 数据结构

```swift
struct LumaAlbum: Identifiable, Codable {
    let id: UUID

    var expeditionId: UUID?
    var name: String
    var kind: AlbumKind

    var rule: SmartAlbumRule?
    var externalAlbumRef: ExternalAlbumRef?

    var createdAt: Date
    var updatedAt: Date
}
```

```swift
struct AlbumAsset: Identifiable, Codable {
    let id: UUID
    var albumId: UUID
    var assetId: UUID
    var addedAt: Date
    var localOrder: Int?
}
```

### 9.4 ExternalAlbumRef

```swift
struct ExternalAlbumRef: Codable {
    var provider: ExternalAlbumProvider
    var localIdentifier: String
}

enum ExternalAlbumProvider: Codable {
    case macPhotos
}
```

### 9.5 SmartAlbumRule

```swift
struct SmartAlbumRule: Codable {
    var scope: SmartAlbumScope
    var filters: [SmartAlbumFilter]
    var sort: SmartAlbumSort?
}
```

```swift
enum SmartAlbumScope: Codable {
    case library
    case expedition(UUID)
}
```

### 9.6 Album Actions

用户可以在 Album 上执行：

- 导出这个相册副本
- 创建 / 更新 Photos 相册
- 生成视频
- 标记为已完成
- 复制到文件夹

---

## 10. Mac Photos 集成

### 10.1 定位

Mac Photos 是 Luma 中的全局系统 Source，也是特殊 Expedition。

它的原则是：

> **引用系统 Photos，增强组织与选片，不默认复制或破坏系统库。**

### 10.2 权限与绑定

Mac Photos 使用全局授权绑定模式。

需要 Photos Library 权限：

```text
com.apple.security.personal-information.photos-library
```

用户首次点击「连接 Mac Photos」时，系统弹窗授权。  
授权成功后，Luma 自动创建 / 激活特殊 Mac Photos Expedition。

### 10.3 建立索引

首次授权后：

- 枚举 PHAsset。
- 保存 `localIdentifier`。
- 使用 `PHCachingImageManager` 请求缩略图。
- 读取基础元数据。
- 不复制原图。
- 根据需要懒加载预览。
- Luma 只持久化索引、评分、分组、选片状态和相册关系。

### 10.4 Mac Photos 工作流

```text
连接 Mac Photos
  ↓
授权访问
  ↓
Luma 建立引用索引
  ↓
左侧出现 Mac Photos 特殊 Expedition
  ↓
按年份 / 月份 / 地点 / 系统相册浏览
  ↓
在 Luma 内分组、选片、评分
  ↓
创建 Luma 相册
  ↓
同步为系统 Photos 相册
```

### 10.5 支持能力

V4 第一阶段支持：

- 全局连接 Mac Photos
- 读取 Mac Photos 照片
- 使用 PhotoKit / PHCachingImageManager 获取缩略图
- 在 Luma 内保存选片状态
- 在 Luma 内建立分组
- 根据时间范围从 Mac Photos 创建普通 Expedition
- 根据系统 Photos 相册创建普通 Expedition
- 根据 Luma Album 创建 Photos 相册
- 更新 Photos 相册内容
- 打开系统 Photos 查看

V4 第一阶段暂不支持：

- 删除 Mac Photos 原图
- 修改 Mac Photos 原图
- 批量清理系统照片库
- 修改 iCloud 照片同步状态
- 将 Mac Photos 原图长期复制到 Luma

### 10.6 复用 V3 Mac 相册回写能力

V3 已实现的 Mac Photos 相册回写能力应继续复用。  
在 V4 中，该能力不再被定义为“导出到相册”，而是升级为：

```text
Photos-backed Album Sync
```

建议抽象：

```swift
protocol AlbumSyncAdapter {
    var displayName: String { get }

    func createAlbum(name: String) async throws -> ExternalAlbumRef
    func updateAlbum(_ ref: ExternalAlbumRef, assets: [MasterAsset]) async throws
    func removeAssets(_ assets: [MasterAsset], from ref: ExternalAlbumRef) async throws
    func validateAccess() async throws -> Bool
}
```

Photos 实现：

```swift
final class PhotosAlbumSyncAdapter: AlbumSyncAdapter {
    // 复用 V3 PhotoKit album write-back 能力
}
```

### 10.7 Photos-backed Album

当用户将 Luma Album 同步到系统 Photos：

```text
LumaAlbum(kind: .photosBacked)
  ↓
PHAssetCollection
```

规则：

- Luma 保存对应 `PHAssetCollection.localIdentifier`。
- 后续可同步 album 内容。
- 如果 Photos 中相册被删除，Luma 应显示“外部相册已失效”。
- 同步失败时不影响 Luma 本地相册。

---

## 11. Action System（替代 Export）

### 11.1 重构原因

旧版 Export 的核心是将照片输出到 Lightroom 或本地文件夹。  
v4 起，Luma 自身成为照片管理中心，因此 Export 不再是主流程终点。

新的统一概念是：

```text
Action / Task
```

### 11.2 Expedition Actions

Expedition 可执行：

- 生成归档视频
- 压缩未选照片
- 清理未选照片
- 导出副本到文件夹
- 创建 Mac Photos 相册
- 更新 Mac Photos 相册
- 生成分享包
- 写入元数据
- 重新分析照片
- 重新生成分组

### 11.3 Album Actions

Album 可执行：

- 导出相册副本
- 同步到 Mac Photos
- 生成视频
- 复制到文件夹
- 标记为已完成

### 11.4 ActionJob 数据结构

```swift
enum ExpeditionActionKind: Codable {
    case createArchiveVideo
    case shrinkRejected
    case cleanupRejected
    case createAlbum
    case syncAlbumToPhotos
    case exportCopyToFolder
    case generateSharePackage
    case rerunAnalysis
    case regroup
}
```

```swift
struct ExpeditionActionJob: Identifiable, Codable {
    let id: UUID

    var expeditionId: UUID?
    var albumId: UUID?

    var kind: ExpeditionActionKind
    var targetAssetIds: [UUID]

    var status: JobStatus

    var createdAt: Date
    var completedAt: Date?

    var resultURL: URL?
    var errorMessage: String?
}
```

```swift
enum JobStatus: Codable {
    case pending
    case running
    case completed
    case failed
    case cancelled
}
```

### 11.5 破坏性操作规则

以下操作必须二次确认：

- 清理未选照片
- 删除本地托管原图
- 删除 Mac Photos 原图
- 移除大量照片引用
- 覆盖系统 Photos 相册内容

确认文案必须明确说明影响范围：

```text
这会从当前旅程中移除照片引用，不会删除原始文件。
```

或：

```text
这会尝试从系统 Photos 中删除照片。此操作可能影响 iCloud 照片库。
```

v4 第一阶段不默认提供删除 Mac Photos 原图能力。

---

## 12. 归档模块（Archive）

### 12.1 归档定位

归档是 Action System 的一种，不再是 Export 的附属选项。

归档可作用于：

- 当前 Expedition 的未选照片
- 当前 Album
- 当前智能相册
- 可清理候选列表

### 12.2 归档方式

#### 方式 A：归档视频

保留旧版能力：

- 按 PhotoGroup 生成视频
- 每张照片停留 1.5–2 秒
- Ken Burns 效果
- 分组名称 / 日期 / 地点文字
- 输出 H.265 / 1080p

#### 方式 B：低清保留

- 长边 2048px
- JPEG 质量 80%
- 保留基础 EXIF
- 生成 manifest
- 原图是否删除由用户明确选择

#### 方式 C：仅标记已归档

对于 Mac Photos 或引用照片，可仅在 Luma 内标记归档状态，不复制或删除原图。

### 12.3 ArchiveManifest

```swift
struct ArchiveManifest: Codable {
    var id: UUID
    var expeditionId: UUID?
    var albumId: UUID?

    var generatedAt: Date
    var archiveKind: ArchiveKind

    var items: [ArchiveManifestItem]
}
```

```swift
enum ArchiveKind: Codable {
    case video
    case lowresCopy
    case markerOnly
}
```

```swift
struct ArchiveManifestItem: Codable {
    var assetId: UUID
    var originalReference: String
    var archivePath: String?
    var frameIndex: Int?
    var decision: Decision
}
```

---

## 13. 设置与偏好

### 13.1 Library 设置

- Luma Library 位置
- Luma Managed Storage 位置
- 缩略图缓存大小上限
- 缓存清理策略
- 引用失效检测

### 13.2 Source 设置

- Mac Photos 连接状态
- Mac Photos 权限状态
- Mac Photos 索引更新时间
- 本地文件夹引用列表
- SD 卡默认导入行为
- 默认本地文件夹策略：
  - 引用原位置
  - 复制到 Luma

### 13.3 Expedition 默认值

- 默认创建方式
- 默认分组阈值
- 默认是否自动评分
- 默认是否自动推荐
- 默认是否自动生成智能相册

### 13.4 AI 模型配置

保留旧版能力：

- 模型列表
- Endpoint
- API Key（Keychain 加密）
- Model ID
- 测试连接
- 评分策略
- 费用阈值预警

### 13.5 Action 默认值

- 默认归档方式
- 默认低清质量
- 默认视频参数
- 默认分享包目录
- Photos-backed 相册同步策略

---

## 14. 数据库与存储结构

### 14.1 核心原则

```text
照片实体全局唯一。
集合只保存引用。
导入记录只记录来源历史。
选片状态属于 Expedition 上下文。
Source 和 Storage Mode 分离。
```

### 14.2 建议核心表

```text
asset_sources
master_assets
expeditions
expedition_assets
import_sessions
photo_groups
photo_subgroups
asset_scores
expedition_recommendations
albums
album_assets
external_album_refs
action_jobs
archive_manifests
```

### 14.3 关系模型

```text
asset_sources 1 ── * master_assets

master_assets * ── * expeditions
             via expedition_assets

expeditions 1 ── * photo_groups
photo_groups 1 ── * photo_subgroups

expeditions 1 ── * albums
albums * ── * master_assets
          via album_assets

albums 0/1 ── 1 external_album_refs

expeditions 1 ── * action_jobs
```

### 14.4 文件存储建议

```text
~/Library/Application Support/Luma/
  ├── library.db
  ├── thumbnails/
  ├── previews/
  ├── managed-originals/
  ├── archives/
  ├── action-results/
  └── diagnostics/
```

### 14.5 存储规则

- SD 卡导入默认进入 `managed-originals/`。
- 本地文件夹引用不复制原图，只生成缓存。
- Mac Photos 不复制原图，只通过 PhotoKit 请求资源。
- 所有缓存可重建。
- 原图路径或 externalIdentifier 必须可用于恢复引用。
- 引用失效应有 UI 提示。
- Mac Photos 缩略图优先使用系统缓存与 `PHCachingImageManager`，Luma 仅持久化必要轻量索引。

---

## 15. 首页与信息架构

### 15.1 首页左侧导航

建议结构：

```text
资料库
  所有照片
  Mac Photos
  最近添加
  未整理

Expeditions
  日本关西 2026
  周末扫街
  家庭照片整理
  2026 年精选

相册
  Luma 精选
  待修图
  已归档
  可清理

任务
  正在导入
  正在分析
  正在归档
```

### 15.2 首页主区域

首页主区域展示：

- 最近 Expedition
- 最近添加照片
- Mac Photos 连接状态
- 正在进行的任务
- 快速创建 Expedition
- 添加照片入口

### 15.3 Expedition 卡片

每张 Expedition 卡片展示：

- 封面图
- 名称
- 时间范围
- 照片数量
- 分组数量
- 已选数量
- 未审数量
- 状态

### 15.4 Mac Photos 卡片

特殊展示：

```text
Mac Photos
系统照片库 · 引用模式
照片数量 · 已建立索引数量 · 最近同步时间
```

可操作：

- 连接 / 重新授权
- 打开
- 建立 / 更新索引
- 查看权限
- 创建 Luma 精选相册

---

## 16. V4 阶段计划

### 16.1 Phase 1：Source / Storage + Expedition Library 重构

目标：

- 引入 Expedition
- ImportSession 降级为导入记录
- 引入 MasterAsset 全局资产
- 引入 Source / Storage Mode 分离
- ExpeditionAsset 保存集合关系和选片状态
- 工作台绑定 Expedition

必做：

- Expedition 列表
- 创建 / 编辑 Expedition
- 添加照片到 Expedition
- SD 卡 / 文件夹导入时进入全局资产库
- 同一照片避免重复创建 MasterAsset
- 选片状态迁移到 ExpeditionAsset
- 文件夹添加时支持引用 / 复制模式选择

暂缓：

- Mac Photos 删除
- 复杂智能相册
- 视频资产

### 16.2 Phase 2：Mac Photos 全局绑定与特殊 Expedition

目标：

- Mac Photos 作为全局系统 Source / 特殊 Expedition。
- 授权后自动出现。
- 只引用不复制。
- Luma 内部可选片、分组、创建相册。

必做：

- 「连接 Mac Photos」入口
- PhotoKit 授权
- PHAsset 索引
- 复用 `PHCachingImageManager`
- Mac Photos 视图
- Mac Photos Expedition 工作台
- 从 Mac Photos 时间范围创建 Expedition
- 从系统 Photos 相册创建 Expedition
- 创建 Photos-backed Album

暂缓：

- 删除系统 Photos 原图
- 批量清理 Photos
- 修改原图
- 长期复制 Mac Photos 原图

### 16.3 Phase 3：Photos-backed Album Sync + Action System

目标：

- 复用 V3 Mac 相册回写能力。
- 将 Export 重构为统一 Actions。
- Expedition / Album 上直接执行动作。

必做：

- AlbumSyncAdapter
- PhotosAlbumSyncAdapter
- ActionJob 模型
- 生成归档视频
- 导出副本到文件夹
- 低清归档
- 创建 / 更新 Photos 相册
- 任务历史和进度

暂缓：

- 复杂分享包模板
- 高级清理策略
- 自动删除
- 视频归档

### 16.4 V5 规划：视频支持

V5 再支持普通视频作为一等资产：

- 视频 MasterAsset
- 视频缩略图
- 视频预览
- 视频分组
- 视频精选
- 视频归档
- 照片与视频混合 Expedition
- Live Photo 与普通视频的统一体验

---

## 17. 技术约束与注意事项

### 17.1 PhotoKit 风险

- iCloud 原图可能不在本地。
- 用户可能只授权有限照片访问。
- 系统相册写入可能失败。
- Photos 相册被外部删除后，Luma 需要处理失效状态。
- 删除 Photos 原图涉及高风险权限与用户信任问题。
- 需要谨慎处理 `PHImageManager` 返回 degraded image 的场景。

### 17.2 Mac Photos 资源复用

Mac Photos 场景应优先使用系统资源：

- `PHAsset.localIdentifier` 作为稳定引用。
- `PHCachingImageManager` 用于缩略图预取。
- 可见区域按需请求图像。
- AI 分析临时请求图像数据，不持久复制。
- Luma 仅持久化自己的业务数据。

### 17.3 文件引用风险

本地文件夹引用模式下：

- 文件可能被移动。
- 外置硬盘可能未连接。
- 权限可能失效。
- Luma 应提供“重新定位”能力。

### 17.4 数据迁移

从旧版 Import Session 模型迁移到 v4 时，需要：

- 将现有导入批次迁移为 Expedition。
- 将现有 MediaAsset 迁移为 MasterAsset。
- 将 userDecision 迁移为 ExpeditionAsset.decision。
- 将旧导出记录迁移为 ActionJob / ImportSession 历史。
- 将 V3 Mac Photos 相册回写能力迁移为 Photos-backed Album Sync。
- 保证旧项目可打开。

### 17.5 性能目标

| 指标 | 目标 |
|---|---|
| 首页打开 | < 2 秒 |
| Expedition 打开 | < 3 秒 |
| 1000 张照片网格滚动 | 60fps |
| Mac Photos 索引增量更新 | 后台执行，不阻塞 UI |
| 缩略图首次可见 | < 5 秒 |
| 大图预览 | 按需加载 |

### 17.6 错误恢复

- 导入任务支持暂停 / 继续。
- 引用失效支持重新定位。
- Mac Photos 权限失效支持重新授权。
- Action 失败支持重试。
- 数据库迁移失败必须保留备份。
- 缓存损坏可重建。
- Photos-backed Album 外部失效时，应允许重新绑定或转为本地相册。

---

## 18. V4 非目标范围

v4 不追求完整替代 Lightroom。

明确不做：

- 完整 RAW 修图引擎
- 非破坏性调色滑块系统
- 云同步
- 多用户协作
- 移动端同步
- Mac Photos 原图批量删除
- iCloud 照片库管理
- 普通视频资产管理
- 视频选片
- 完整 DAM 系统
- 插件生态
- 复杂打印 / 出版工作流

Luma 的差异化应保持为：

> **比 Apple Photos 更会选片，比 Lightroom 更轻。**

---

## 19. V4 验收标准

### 19.1 Library / Source / Storage

- [ ] 用户能看到全局「所有照片」视图。
- [ ] 用户能看到「Mac Photos」特殊入口。
- [ ] 用户能区分照片来源。
- [ ] Source 类型中不再把 Luma Managed Storage 作为用户可见来源。
- [ ] 用户能理解本地文件夹的「引用原位置」和「复制到 Luma」区别。
- [ ] SD 卡 / 文件夹 / Mac Photos 的处理策略不同且清晰。

### 19.2 Expedition

- [ ] 用户能创建空 Expedition。
- [ ] 用户能从 SD 卡 / 文件夹添加照片创建或补充 Expedition。
- [ ] 用户能从 Mac Photos 时间范围创建 Expedition。
- [ ] Expedition 不复制照片实体，只保存引用关系。
- [ ] Expedition 内能查看全部照片、已选、未选、未审。
- [ ] 删除 Expedition 不删除原图。

### 19.3 ImportSession

- [ ] 导入历史仍被记录。
- [ ] ImportSession 不再作为主工作入口。
- [ ] 多次导入同一照片不会产生多份 MasterAsset。
- [ ] 导入失败 / 跳过 / 重复可追踪。

### 19.4 Mac Photos

- [ ] 用户通过「连接 Mac Photos」完成全局授权绑定。
- [ ] 授权后自动出现特殊 Mac Photos Expedition。
- [ ] Mac Photos 不作为普通「添加照片」入口。
- [ ] Mac Photos 不复制原图。
- [ ] Mac Photos 缩略图优先复用 PhotoKit / PHCachingImageManager。
- [ ] Luma 可在 Mac Photos 照片上保存分组和选片状态。
- [ ] 不默认支持删除系统照片。

### 19.5 图片资产范围

- [ ] v4 支持 JPG / PNG / HEIC / RAW + JPEG / ProRAW DNG。
- [ ] Live Photo 作为图片资产 + auxiliary MOV 处理。
- [ ] 普通视频资产不进入 v4 主流程。
- [ ] 视频支持被明确标记为 V5 规划。

### 19.6 Cull 工作台

- [ ] 工作台以 Expedition 为上下文。
- [ ] 分组选片、网格、对比、人脸检查都可基于 Expedition 运行。
- [ ] Decision 存在于 ExpeditionAsset 上。
- [ ] 人工覆盖 AI 推荐后状态正确。

### 19.7 Album / Photos-backed Album

- [ ] 用户能创建手动相册。
- [ ] 用户能查看智能相册。
- [ ] Album 只保存引用。
- [ ] V3 Mac 相册回写能力被复用。
- [ ] Photos-backed Album 可映射到系统 Photos。
- [ ] Photos-backed Album 外部失效时有提示。

### 19.8 Actions

- [ ] Expedition 可执行归档视频。
- [ ] Expedition 可执行低清归档。
- [ ] Expedition 可导出副本到文件夹。
- [ ] Album 可同步到 Mac Photos。
- [ ] Actions 有进度、有结果、有失败状态。
- [ ] 破坏性操作有二次确认。

### 19.9 数据恢复

- [ ] 重开 App 后 Expedition 状态保留。
- [ ] 重开 App 后选片状态保留。
- [ ] 重开 App 后相册关系保留。
- [ ] 缓存可重建。
- [ ] 引用失效有提示与恢复路径。
