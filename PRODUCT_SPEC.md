# Luma（拾光）— 产品规格说明书

## 1. 产品概述

### 1.1 定位
Luma（拾光）是一款 macOS 原生桌面应用，专为摄影爱好者设计，解决旅行归来后"选片焦虑"的痛点。核心理念是 **"JPEG 做决策，RAW 做交付"**，通过混合 AI 管线（本地 Core ML + 云端 Vision API）实现智能照片筛选、评分、修图建议和归档。

### 1.2 核心工作流（五阶段管线）
```
Ingest → Group → Score → Cull → Export / Archive
导入     分组     评分     挑选    导出 / 归档
```

### 1.3 目标用户
- 使用相机（Sony/Canon/Nikon/Fuji）+ iPhone 拍照的摄影爱好者
- 一次旅行产生 300-1000 张照片
- 拍摄格式：RAW + JPEG（相机）/ HEIC + ProRAW DNG（iPhone）
- 后期工具：Lightroom Classic / Mac 照片 App

### 1.4 技术栈
- 语言：Swift
- UI 框架：SwiftUI（macOS 14+）
- 最低系统要求：macOS 14 Sonoma, Apple Silicon（M1+）优先
- 关键系统框架：Vision, Core ML, Core Image, ImageCaptureCore, PhotoKit, AVFoundation, DiskArbitration

---

## 2. 导入模块（Ingest）

### 2.1 架构核心：ImportSourceAdapter 协议

所有导入源实现统一协议，下游管线完全不感知数据来源。

```swift
protocol ImportSourceAdapter {
    var displayName: String { get }
    func enumerate() async throws -> [DiscoveredItem]
    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage?
    func copyPreview(_ item: DiscoveredItem, to: URL) async throws
    func copyOriginal(_ item: DiscoveredItem, to: URL) async throws
    func copyAuxiliary(_ item: DiscoveredItem, to: URL) async throws
    var connectionState: AsyncStream<ConnectionState> { get }
}
```

### 2.2 四种导入源

#### 2.2.1 SD 卡导入（SDCardAdapter）
- **检测方式**：V1 使用 `DispatchSource.makeFileSystemObjectSource` 监控 `/Volumes/`；V2 迁移到 `DiskArbitration` 框架过滤可移除媒体
- **文件扫描**：`FileManager.enumerator(at:)` 递归遍历 `DCIM/` 目录
- **RAW/JPEG 配对**：按文件名（去掉扩展名）匹配，忽略子目录路径差异
- **支持的 RAW 格式**：`.arw`(Sony), `.cr3`(Canon), `.nef`(Nikon), `.raf`(Fuji), `.dng`, `.orf`(Olympus), `.rw2`(Panasonic)
- **边界情况处理**：
  - 仅有 RAW 无 JPEG → 从 RAW 内嵌预览提取（CGImageSource 原生支持）
  - 多个同名 JPEG → 取最新修改时间的
  - 相机将 RAW/JPEG 分放不同子目录 → 全局文件名匹配

#### 2.2.2 iPhone USB 直连（iPhoneAdapter）
- **框架**：ImageCaptureCore
- **检测方式**：`ICDeviceBrowser` 设置 delegate，监听 `didAdd device` 回调
- **文件访问**：通过 PTP 协议，必须用 `ICCameraDevice.requestDownloadFile()` 下载，不能直接访问路径
- **权限要求**：`Info.plist` 声明 `com.apple.security.device.camera` entitlement
- **格式处理**：
  - 普通照片：HEIC 格式（10-bit 色深）
  - ProRAW：标准 DNG 格式，25-50MB/张，内嵌全尺寸预览
  - Live Photo：HEIC + MOV 配对，通过 EXIF MakerNote 中的 `ContentIdentifier` 关联
  - 人像模式：附带 `AVDepthData` 景深数据

#### 2.2.3 文件夹导入（FolderAdapter）
- **触发方式**：`NSOpenPanel` 手动选择 / 监控 `~/Downloads/` 检测 AirDrop 文件
- **文件夹监控**：`DispatchSource.makeFileSystemObjectSource` 检测新 HEIC/DNG 文件，弹窗提示导入
- **Live Photo 配对**：扫描同目录下的 MOV 文件，通过 ContentIdentifier 匹配

#### 2.2.4 照片库导入（PhotosLibraryAdapter）
- **框架**：PhotoKit (`PHPhotoLibrary`)
- **用途**：整理历年 iPhone 旧照片
- **枚举方式**：`PHFetchResult` 按日期范围/相册筛选
- **缩略图获取**：`PHCachingImageManager` 预加载可见区域
- **权限要求**：Photos Library 读写权限（系统弹窗授权）
- **优先级**：V2 功能

### 2.3 三阶段渐进式导入

核心原则：**不让用户等**。

| 阶段 | 内容 | 速度 | 线程优先级 | 用户可做 |
|------|------|------|-----------|---------|
| Phase 1 | 扫描文件列表 + 提取 EXIF 缩略图（~15KB/张）+ 解析元数据 | 500张 → 3-5秒 | 主线程 | 浏览缩略图网格 |
| Phase 2 | 异步拷贝全尺寸 JPEG/HEIC | 500张 → 30-60秒 | .userInitiated | 放大查看 + 触发 AI 评分 |
| Phase 3 | 低优先级拷贝 RAW/DNG | 500张 → 5-8分钟 | .utility | 仅导出选中照片时需要 |

**技术要点**：
- 缩略图统一缩放到 400px 长边（500张 ≈ 200-300MB 内存）
- 缩略图提取使用 `CGImageSourceCreateThumbnailAtIndex`，EXIF 解析使用 `CGImageSourceCopyPropertiesAtIndex`，同一次 CGImageSource 打开中完成
- SD 卡文件拷贝并发数限制 2-3（避免随机读取降低 UHS-I/II 吞吐）
- 拷贝写入临时文件（`.importing` 后缀），完成后原子性重命名
- 维护持久化拷贝进度记录（JSON），支持断点续传
- 设备拔出时优雅暂停，提示用户重新插入后继续

### 2.4 HEIC 处理策略

采用 **全程保留 HEIC 原生格式**，仅在发送 Vision API 时临时转码为 JPEG。理由：
- macOS CGImageSource / Core ML 原生支持 HEIC 解码
- 保留 10-bit 色深和 HDR 信息
- 减少导入时的 CPU 开销

### 2.5 本地存储结构
```
~/Library/Application Support/Luma/
  └── 2026-04-03_kyoto/           ← 按日期+地点自动命名
      ├── manifest.json            ← 所有 MediaAsset 完整状态
      ├── thumbnails/              ← 400px 缩略图缓存
      ├── preview/                 ← 全尺寸 JPEG/HEIC
      ├── raw/                     ← RAW/DNG 原始文件
      └── auxiliary/               ← Live Photo MOV 等附属资源
```

---

## 3. 数据模型

### 3.1 核心模型

```swift
struct MediaAsset: Identifiable, Codable {
    let id: UUID
    let baseName: String                    // "DSC_0042" 或 "IMG_1234"
    let source: ImportSource

    // 文件引用
    var previewURL: URL?                    // JPEG 或 HEIC
    var rawURL: URL?                        // ARW/CR3/NEF/DNG 等
    var livePhotoVideoURL: URL?             // MOV（仅 Live Photo）
    var depthData: Bool                     // 是否包含景深数据

    // 缓存
    var thumbnailURL: URL?                  // 400px 缩略图本地路径

    // 元数据
    let metadata: EXIFData
    let mediaType: MediaType

    // 状态
    var importState: ImportState
    var aiScore: AIScore?
    var editSuggestions: EditSuggestions?    // 修图建议
    var userDecision: Decision
}

enum ImportSource: Codable {
    case sdCard(volumePath: String)
    case iPhone(deviceID: String)
    case folder(path: String)
    case photosLibrary(localIdentifier: String)
}

enum MediaType: Codable {
    case photo                              // 普通 JPEG/HEIC + RAW
    case livePhoto                          // HEIC + MOV 配对
    case portrait                           // 人像模式（含景深）
}

enum ImportState: Codable {
    case discovered
    case thumbnailReady
    case previewCopied
    case rawCopied
    case complete
}

enum Decision: Codable {
    case pending
    case picked                             // → 导出 RAW 原图
    case rejected                           // → 归档视频 / 缩小保留 / 丢弃
}
```

### 3.2 EXIF 数据

```swift
struct EXIFData: Codable {
    let captureDate: Date
    let gpsCoordinate: Coordinate?          // CLLocationCoordinate2D 不 Codable，自定义
    let focalLength: Double?                // mm
    let aperture: Double?                   // f值
    let shutterSpeed: String?               // "1/250"
    let iso: Int?
    let cameraModel: String?
    let lensModel: String?
    let imageWidth: Int
    let imageHeight: Int
}
```

### 3.3 AI 评分结果

```swift
struct AIScore: Codable {
    let provider: String                    // "gemini-2.0-flash" / "claude-sonnet"
    let scores: PhotoScores
    let overall: Int                        // 0-100
    let comment: String                     // 中文一句话评价
    let recommended: Bool
    let timestamp: Date
}

struct PhotoScores: Codable {
    let composition: Int                    // 构图 0-100
    let exposure: Int                       // 曝光 0-100
    let color: Int                          // 色彩 0-100
    let sharpness: Int                      // 锐度 0-100
    let story: Int                          // 故事性/情绪 0-100
}
```

### 3.4 修图建议

```swift
struct EditSuggestions: Codable {
    let crop: CropSuggestion?
    let filterStyle: FilterSuggestion?
    let adjustments: AdjustmentValues?
    let hslAdjustments: [HSLAdjustment]?
    let localEdits: [LocalEdit]?
    let narrative: String                   // 完整修图思路
}

struct CropSuggestion: Codable {
    let needed: Bool
    let ratio: String                       // "16:9" / "4:5" / "1:1"
    let direction: String                   // "向左裁切约15%..."
    let rule: String                        // "rule_of_thirds" / "golden_ratio" / "center"
}

struct FilterSuggestion: Codable {
    let primary: String                     // "warm_golden_hour"
    let reference: String                   // "VSCO A6 或 Fuji Velvia 风格"
    let mood: String                        // "温暖怀旧"
}

struct AdjustmentValues: Codable {
    let exposure: Double?                   // EV: -3.0 ~ +3.0
    let contrast: Int?                      // -100 ~ +100
    let highlights: Int?
    let shadows: Int?
    let temperature: Int?                   // 色温 K 值偏移
    let tint: Int?
    let saturation: Int?
    let vibrance: Int?
    let clarity: Int?
    let dehaze: Int?
}

struct HSLAdjustment: Codable {
    let color: String                       // "orange" / "blue" / "green" ...
    let hue: Int?
    let saturation: Int?
    let luminance: Int?
}

struct LocalEdit: Codable {
    let area: String                        // "天空区域" / "前景主体"
    let action: String                      // "压暗高光，增加蓝色饱和度"
}
```

---

## 4. 智能分组模块（Group）

### 4.1 两层聚类策略

#### 第一层：时间聚类（粗分组）
- 按 `captureDate` 排序，相邻照片时间差 > 30 分钟则拆为新组
- 阈值可配置（密集拍摄场景可降至 15 分钟）

#### 第二层：GPS 空间聚类（增强分组，仅有 GPS 数据时）
- 在时间组内叠加 DBSCAN 空间聚类
- epsilon ≈ 200 米，min_samples = 3
- 解决"同一天内多个地点"的分组问题（如京都清水寺 vs 伏见稻荷）

#### 第三层：视觉相似度（组内细分）
- 在每个时间+空间组内，用视觉相似度识别"同一构图的连拍"
- Apple Vision 框架提取特征向量（VNFeaturePrintObservation）
- `featurePrint.computeDistance()` 返回欧氏距离，阈值 < **0.8** → 归为同一子组
- 子组内的照片是"选一张最佳"的候选集

### 4.2 分组命名
- 有 GPS → 反向地理编码获取地点名（`CLGeocoder`）
- 无 GPS → 使用日期 + 时间段（"4月3日·下午"）
- 可选：用 AI 根据照片内容生成描述性名称（"清水寺·日落"）

### 4.3 分组数据结构

```swift
struct PhotoGroup: Identifiable, Codable {
    let id: UUID
    var name: String                        // "清水寺·日落"
    var assets: [UUID]                      // MediaAsset IDs
    var subGroups: [SubGroup]               // 视觉相似的细分组
    let timeRange: ClosedRange<Date>
    let location: Coordinate?
    var groupComment: String?               // AI 整组点评
    var recommendedAssets: [UUID]           // AI 推荐的照片
}

struct SubGroup: Identifiable, Codable {
    let id: UUID
    var assets: [UUID]                      // 视觉相似的照片集
    var bestAsset: UUID?                    // AI 推荐的最佳一张
}
```

---

## 5. AI 评分模块（Score）

### 5.1 混合管线架构

```
全部照片 → [本地 Core ML 初筛] → 技术合格照片 → [云端 Vision API 评分]
              ↓ 淘汰 15-25%                        ↓
           标记：模糊/闭眼/过曝                 评分 + 修图建议
```

### 5.2 本地 Core ML 评估（Phase A，免费离线）

在 Phase 2（JPEG 拷贝完成）后立即触发，基于 JPEG/HEIC 推理：
- **模糊检测**：拉普拉斯方差法（快速）或轻量级 Core ML 分类模型
- **曝光评估**：RGB 直方图分析，检测过曝（>95% 区域占比 > 30%）和欠曝
- **人脸检测 + 闭眼检测**：Apple Vision 框架 `VNDetectFaceLandmarksRequest` 原生支持
- **视觉特征提取**：`VNGenerateImageFeaturePrintRequest` 用于分组阶段的相似度计算

预期处理速度：500 张 JPEG → 2-3 分钟（M1 芯片）

### 5.3 多模型云端评分（Phase B）

#### 5.3.1 VisionModelProvider 协议

```swift
protocol VisionModelProvider {
    var id: String { get }
    var displayName: String { get }
    var apiProtocol: APIProtocol { get }
    var costPer100Images: Double { get }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult
    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult
    func testConnection() async throws -> Bool
}

enum APIProtocol: Codable {
    case openAICompatible                   // GPT-4o / DeepSeek / 通义千问 / GLM-4V / Ollama
    case googleGemini                       // Gemini Flash / Pro
    case anthropicMessages                  // Claude Sonnet / Opus
}
```

#### 5.3.2 模型配置（用户可自定义）

```swift
struct ModelConfig: Codable, Identifiable {
    let id: UUID
    var name: String                        // "Gemini 2.0 Flash"
    var apiProtocol: APIProtocol
    var endpoint: String                    // "https://generativelanguage.googleapis.com"
    var apiKey: String                      // 加密存储在 Keychain
    var modelId: String                     // "gemini-2.0-flash"
    var isActive: Bool
    var role: ModelRole                     // .primary / .premiumFallback
    var maxConcurrency: Int                 // 并发请求数限制
    var costPerInputToken: Double?          // 可选：用于费用追踪
    var costPerOutputToken: Double?
    var calibrationOffset: Double           // 评分校准偏移量
}

enum ModelRole: Codable {
    case primary                            // 全量评分（便宜模型）
    case premiumFallback                    // 仅精评 Top 20%（贵模型）
}
```

#### 5.3.3 评分策略

| 策略 | 说明 | 预估费用（500张） |
|------|------|------------------|
| 省钱模式 | 本地 Core ML + 便宜模型，无精评 | ~$0.15 |
| 均衡模式 | 便宜模型全量 + 贵模型仅 Top 20% | ~$1.00 |
| 最佳质量 | 贵模型全量 + 修图建议 | ~$4.50 |

#### 5.3.4 BatchScheduler

- 按 PhotoGroup 打包（一组 5-8 张一次 API 调用）
- 并发控制（根据模型配置的 maxConcurrency）
- 指数退避重试（最多 3 次）
- 实时费用追踪（token 消耗 × 单价），超阈值弹窗暂停
- 发送前将 JPEG 缩放到 **长边 1024px，JPEG 质量 85%**，减少 60-70% token 消耗

#### 5.3.5 评分校准

首次配置模型时，用 20 张参考照片（好/中/差各覆盖）做校准测试，记录该模型的评分均值和标准差，后续用线性映射归一化，确保切换模型后评分一致。

### 5.4 Prompt 设计

#### Prompt 1：组内批量评分（用于 primary 模型）

```
System:
You are a professional photo editor evaluating a group of similar photos
taken at the same scene. Score each photo and recommend the best ones.
Respond ONLY in JSON format. No markdown fences, no preamble.
All comments must be in Chinese (简体中文).

User:
Here are {n} photos from scene: "{group_name}".
Camera: {camera_model} | Lens: {lens} | Time range: {time_range}

[image_1] [image_2] ... [image_n]

Return JSON:
{
  "photos": [
    {
      "index": 1,
      "scores": {
        "composition": 0-100,
        "exposure": 0-100,
        "color": 0-100,
        "sharpness": 0-100,
        "story": 0-100
      },
      "overall": 0-100,
      "comment": "一句话中文评价",
      "recommended": true/false
    }
  ],
  "group_best": [1, 5],
  "group_comment": "整组中文点评"
}
```

#### Prompt 2：单张精评+修图建议（用于 premiumFallback 模型或最佳质量模式）

```
System:
You are a master photographer and retouching expert. Analyze this photo
and provide detailed editing suggestions with specific values.
Respond ONLY in JSON format. No markdown fences, no preamble.
All text fields must be in Chinese (简体中文).

User:
[image] | EXIF: {aperture}, {shutter}, {iso}, {focal_length}mm
Scene: {group_name} | Initial score: {overall}/100

Return JSON:
{
  "crop": {
    "needed": true/false,
    "ratio": "16:9",
    "direction": "裁切方向描述",
    "rule": "rule_of_thirds | golden_ratio | center | leading_lines",
    "top": 0.0,
    "bottom": 1.0,
    "left": 0.0,
    "right": 1.0
  },
  "filter_style": {
    "primary": "warm_golden_hour | cool_cinematic | moody_dark | clean_minimal | vintage_film",
    "reference": "具体参考滤镜名（如 VSCO A6、Fuji Velvia）",
    "mood": "氛围描述"
  },
  "adjustments": {
    "exposure": -3.0 to +3.0,
    "contrast": -100 to +100,
    "highlights": -100 to +100,
    "shadows": -100 to +100,
    "temperature": -2000 to +2000 (K值偏移),
    "tint": -100 to +100,
    "saturation": -100 to +100,
    "vibrance": -100 to +100,
    "clarity": -100 to +100,
    "dehaze": -100 to +100
  },
  "hsl": [
    {"color": "orange", "hue": -20 to +20, "sat": -100 to +100, "lum": -100 to +100}
  ],
  "local_edits": [
    {"area": "区域名", "action": "具体操作描述"}
  ],
  "narrative": "完整修图思路，2-3句话"
}
```

### 5.5 ResponseNormalizer

不同 API 协议的响应格式不同，需要统一归一化：
- OpenAI 兼容：`response.choices[0].message.content` → parse JSON
- Gemini：`response.candidates[0].content.parts[0].text` → parse JSON
- Anthropic：`response.content[0].text` → parse JSON
- 清除可能的 markdown 代码块标记（````json ... ```）后再 JSON.parse

---

## 6. 人工挑选模块（Cull）

### 6.1 界面布局：三栏设计

| 左栏（200px） | 中栏（弹性宽度） | 右栏（220px） |
|--------------|-----------------|--------------|
| 分组列表 | 照片网格 / 单张放大 | AI 评分 + 修图建议 |
| 每组显示：名称、数量、进度条 | 4列网格，AI推荐蓝色边框 | 五维评分条 |
| 进度条：绿=选中 灰=待定 红=拒绝 | 废片半透明 + 原因标签 | 修图参数可视化 |

### 6.2 快捷键

| 快捷键 | 功能 |
|--------|------|
| `P` | 标记选中（Picked） |
| `X` | 标记拒绝（Rejected） |
| `U` | 撤销标记，回到待定 |
| `→` / `←` | 下一张 / 上一张 |
| `Space` | 切换放大/网格视图 |
| `1-5` | 手动设置星级（覆盖AI评分） |
| `Cmd+A` | 选中当前组 AI 推荐的所有照片 |
| `Tab` | 跳转到下一组 |

### 6.3 交互细节
- 网格模式：4列瀑布流，每张照片显示 AI 评分角标
- 放大模式：单张全屏预览，支持手势缩放和拖拽
- AI 推荐照片显示蓝色边框 + "AI 推荐" 标签
- 被本地 Core ML 淘汰的废片显示半透明 + 红色标签（"模糊" / "过曝" / "闭眼"）
- 顶部状态栏显示：总数、已处理、选中数、拒绝数、AI 评分进度

---

## 7. 导出模块（Export）

### 7.1 导出目标适配器协议

```swift
protocol ExportDestinationAdapter {
    var displayName: String { get }
    func export(assets: [MediaAsset], options: ExportOptions) async throws -> ExportResult
    func validateConfiguration() async throws -> Bool
}
```

### 7.2 Mac 照片 App 导出（PhotosAppExporter）

**框架**：PhotoKit (`PHPhotoLibrary`)

**关键能力**：
- **RAW+JPEG 合并素材**：`PHAssetCreationRequest.addResource` 同时添加 `.photo`(RAW/DNG 主资源) 和 `.alternatePhoto`(JPEG/HEIC 预览资源)，顺序不可颠倒
- **Live Photo 完整还原**：`.addResource(with: .photo)` + `.addResource(with: .pairedVideo)`，ContentIdentifier 必须匹配
- **保留拍摄日期**：设置 `creationDate` 为原始 EXIF 时间（否则会显示为导入日期）
- **保留 GPS 位置**：设置 `location` 属性
- **自动创建相册**：`PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle:)` 按分组创建
- **可选写入 AI 评语**：作为照片描述（`PHAssetChangeRequest.creationRequest.comment`）

**注意事项**：
- 需要 Photos Library 写入权限
- 写入不可撤回 → 导出前必须做确认界面
- 沙盒 App 需要 `com.apple.security.personal-information.photos-library` entitlement

### 7.3 Lightroom 导出（LightroomExporter）

#### 7.3.1 Lightroom Classic（推荐方式：自动导入文件夹）
- 用户在 App 设置中配置 Lightroom 的自动导入文件夹路径
- 导出时将选中照片拷贝到该文件夹
- **同时生成 XMP sidecar 文件**，写入以下字段：

| App 数据 | XMP 字段 | Lightroom 显示 |
|----------|----------|---------------|
| overall 评分 | `xmp:Rating` (1-5) | 星级评分 |
| userDecision | `xmp:Label` | 颜色标签（Green/Yellow/Red） |
| AI 标签 | `dc:subject` | 关键词面板 |
| 分组层级 | `lr:hierarchicalSubject` | 层级关键词（旅行\|京都\|清水寺） |
| AI 评语 | `dc:description` | 元数据"说明"字段 |
| 修图建议参数 | `crs:Exposure2012`, `crs:Contrast2012` 等 | **Lightroom 修图滑块预设值** |
| 裁切建议 | `crs:CropTop/Bottom/Left/Right`, `crs:CropAngle` | Lightroom 裁切预览 |

**评分到星级映射**：90+→5星, 75-89→4星, 60-74→3星, 45-59→2星, <45→1星

**修图建议写入 XMP 的关键字段对应**：
```xml
<!-- 基础调整 -->
<crs:Exposure2012>+0.30</crs:Exposure2012>
<crs:Contrast2012>+10</crs:Contrast2012>
<crs:Highlights2012>-20</crs:Highlights2012>
<crs:Shadows2012>+15</crs:Shadows2012>
<crs:Temperature>5500</crs:Temperature>       <!-- 绝对色温值 -->
<crs:Saturation>+5</crs:Saturation>
<crs:Vibrance>+10</crs:Vibrance>
<!-- 裁切 -->
<crs:CropTop>0.05</crs:CropTop>               <!-- 0-1 百分比 -->
<crs:CropBottom>0.95</crs:CropBottom>
<crs:CropLeft>0.0</crs:CropLeft>
<crs:CropRight>0.85</crs:CropRight>
<crs:HasCrop>True</crs:HasCrop>
```

#### 7.3.2 Lightroom CC
- 导出到本地文件夹，用户手动导入
- XMP 中 Rating 和 Keywords 可被 CC 读取

### 7.4 本地文件夹导出（FolderExporter）

三种目录组织模板可选：
- **按日期**：`Trip_Name/2026-04-01/DSC_0001.ARW`
- **按场景分组**：`Trip_Name/01_清水寺_日落/DSC_0001.ARW`
- **按星级分层**：`Trip_Name/5star_精选/DSC_0001.ARW`

可选附带 XMP sidecar 文件。

### 7.5 导出选项界面

```swift
struct ExportOptions {
    var destination: ExportDestination       // .photosApp / .lightroom / .folder
    // 照片 App 选项
    var createAlbumPerGroup: Bool            // 按分组创建相册
    var mergeRawAndJpeg: Bool               // RAW+JPEG 合并为单素材
    var preserveLivePhoto: Bool             // 保留 Live Photo
    var includeAICommentAsDescription: Bool  // AI 评语写入描述
    // Lightroom 选项
    var lrAutoImportFolder: URL?            // 自动导入文件夹路径
    var writeXmpSidecar: Bool               // 生成 XMP
    var writeEditSuggestionsToXmp: Bool     // 修图建议写入 XMP 滑块值
    // 文件夹选项
    var folderTemplate: FolderTemplate      // .byDate / .byGroup / .byRating
    var outputPath: URL
    // 通用
    var rejectedHandling: RejectedHandling  // .archiveVideo / .shrinkKeep / .discard
}
```

---

## 8. 归档模块（Archive）

### 8.1 未选中照片 → 回忆视频

**框架**：AVFoundation (`AVAssetWriter`)

**生成流程**：
1. 按 PhotoGroup 分组生成（每组一个视频）
2. 每张照片停留 1.5-2 秒
3. 叠加 Ken Burns 效果（缓慢平移 + 缩放，随机方向）
4. 添加文字标注（分组名称 + 日期 + 地点）
5. 淡入淡出转场（0.3 秒）
6. 输出编码：H.265 (HEVC), 1080p, CRF 28

**文件组织**：
```
~/Library/Application Support/Luma/archives/
  └── 2026-04-03_kyoto/
      ├── 01_清水寺_日落_archive.mp4
      ├── 02_伏见稻荷_鸟居_archive.mp4
      └── archive_manifest.json        ← 记录每帧对应的原始文件名
```

### 8.2 缩小保留方案（备选）
- 降至长边 2048px
- JPEG 质量 80%
- 保留完整 EXIF
- 删除 RAW 原文件，仅保留缩小后的 JPEG

### 8.3 归档清单
- 生成 `archive_manifest.json` 记录每张归档照片的原始文件名、拍摄时间、AI评分、归档方式
- 便于未来如需找回某张具体照片时检索

---

## 9. 设置与偏好

### 9.1 通用设置
- 默认导入目录
- 缩略图缓存大小上限
- 语言偏好（中文/英文/跟随系统）

### 9.2 AI 模型配置
- 模型列表（增删改）
- 每个模型：协议、Endpoint、API Key（Keychain 加密存储）、Model ID
- API Key 测试连接验证
- 评分策略选择（省钱/均衡/最佳质量）
- 费用阈值预警（默认 $5 / 批次）

### 9.3 导出默认值
- 默认导出目标
- Lightroom 自动导入文件夹路径
- 默认文件夹组织模板
- 默认未选中处理方式

---

## 10. 技术约束与注意事项

### 10.1 沙盒与权限
| 权限 | 用途 | entitlement |
|------|------|-------------|
| 相机设备 | iPhone USB 访问 | `com.apple.security.device.camera` |
| 照片库 | 导出到照片 App / 从照片库导入 | `com.apple.security.personal-information.photos-library` |
| 文件访问 | SD 卡读取、文件夹导出 | `com.apple.security.files.user-selected.read-write` |
| 网络 | API 调用 | `com.apple.security.network.client` |
| Keychain | API Key 安全存储 | 默认可用 |

### 10.2 性能目标
| 指标 | 目标值 |
|------|--------|
| 缩略图首次可见 | < 5 秒（500张） |
| 网格滚动帧率 | 60fps（LazyVGrid + 缩略图缓存） |
| 本地 Core ML 评估 | < 3 分钟（500张，M1） |
| 内存占用（浏览中） | < 500MB |

### 10.3 错误恢复
- 所有导入/导出任务支持断点续传
- API 调用失败：指数退避重试，3 次失败后跳过并标记
- 设备意外断开：暂停任务，重连后自动恢复
- App 崩溃恢复：通过 manifest.json 恢复完整工作状态
