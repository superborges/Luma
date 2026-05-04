# V3 架构设计

# 一、背景

Luma V2 已完成云端 AI 评分管线（多模型/批量评分/修图建议/三档策略/费用追踪），选片核心闭环成熟。V3 补齐四个维度：

1. **导入源**：新增 SD 卡直连导入（DiskArbitration），覆盖相机用户主流工作流
2. **导出层**：新增 Lightroom 导出 + XMP sidecar（含 Camera Raw 修图预设写入），打通后期工具闭环
3. **归档**：未选中照片自动生成 Ken Burns 回忆视频或缩小保留，释放磁盘空间
4. **AI 增强**：跨模型评分校准（μ/σ 线性映射）+ AI 语义组名生成

# 二、目标

**功能目标**
- `SDCardAdapter` 实现 `ImportSourceAdapter`，DiskArbitration 检测 + DCIM 扫描 + RAW/JPEG 配对 + 设备拔出恢复
- `LightroomExporter` 实现 `ExportDestinationAdapter`，输出文件 + XMP sidecar（Rating / Label / Keywords / Description / crs 滑块值）
- `ArchiveVideoGenerator` 用 AVAssetWriter 生成 H.265 1080p Ken Burns 视频
- `ShrinkKeepArchiver` 缩小保留（2048px / JPEG 80%）+ 删除 RAW
- `ScoreCalibrator` 用 20 张参考照计算模型 μ/σ，线性映射归一化写入 `ModelConfig.calibrationOffset`
- `AIGroupNamer` 用云端 Vision API 生成描述性组名

**架构目标**
- **0 新重型依赖**：XMP 用字符串模板生成（不引入 libxml2 / SwiftSoup），视频用 AVFoundation 原生 API
- **数据流向不变**：所有结果通过 `ProjectStore` 写回 manifest，不改现有 schema
- **可测性**：XMP 生成器纯函数（输入 MediaAsset → 输出 XML 字符串）；视频生成 mock AVAssetWriter；校准逻辑独立于网络
- **性能**：SD 卡 500 张 DCIM 扫描 < 3 秒；XMP 生成 500 张 < 5 秒；Ken Burns 视频 50 张 < 30 秒（M1）

# 三、架构设计

## 3.1 整体分层（V3 变更标注）

```
┌──────────────────────────────────────────────────────────────┐
│  Views (SwiftUI / AppKit)                                    │
│  ┌──────────────┐ ┌─────────────┐ ┌─────────────────────┐    │
│  │ Culling      │ │ Export      │ │ Settings - AIModels │    │
│  │ Workspace    │ │ Panel       │ │ Tab                 │    │
│  │ ★ AI 组名    │ │ ★ LR 导出  │ │ ★ 校准评分按钮     │    │
│  │              │ │ ★ 归档选项  │ │                     │    │
│  └──────┬───────┘ └──────┬──────┘ └──────────┬──────────┘    │
│         │                │                    │              │
│  ┌──────┴────────────────┴────────────────────┴──────┐       │
│  │            ProjectStore (@Observable)             │       │
│  │  ★ importFromSDCard()                            │       │
│  │  ★ exportToLightroom(options:)                   │       │
│  │  ★ archiveRejected(mode:)                        │       │
│  │  ★ calibrateModel(configID:)                     │       │
│  │  ★ generateAIGroupNames()                        │       │
│  └──────┬────────────────┬────────────────────┬─────┘        │
├─────────┼────────────────┼────────────────────┼──────────────┤
│  Services / Import ★                                         │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  SDCardAdapter ★                                     │     │
│  │   ├─ DiskArbitrationMonitor (DASessionRef callback) │     │
│  │   ├─ DCIMScanner (FileManager.enumerator)           │     │
│  │   └─ RAWJPEGPairer (文件名匹配 + 内嵌预览提取)       │     │
│  └─────────────────────────────────────────────────────┘     │
├──────────────────────────────────────────────────────────────┤
│  Services / Export ★                                         │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  LightroomExporter ★                                 │     │
│  │   └─ XMPSidecarWriter (字符串模板 XML 生成)         │     │
│  └─────────────────────────────────────────────────────┘     │
├──────────────────────────────────────────────────────────────┤
│  Services / Archive ★                                        │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  ArchiveVideoGenerator ★ (AVAssetWriter + KenBurns) │     │
│  │  ShrinkKeepArchiver ★   (CGImage resize + EXIF)     │     │
│  │  ArchiveManifest ★      (archive_manifest.json)     │     │
│  └─────────────────────────────────────────────────────┘     │
├──────────────────────────────────────────────────────────────┤
│  Services / AI (V2 已有 + V3 新增)                            │
│  ┌─────────────────────────────────────────────────────┐     │
│  │  ScoreCalibrator ★  (20 参考照 → μ/σ → 线性映射)    │     │
│  │  AIGroupNamer ★     (Vision API → 描述性组名)       │     │
│  │  CloudScoringCoordinator (V2, 不动)                 │     │
│  │  VisionModelProvider (V2, 不动)                     │     │
│  └─────────────────────────────────────────────────────┘     │
├──────────────────────────────────────────────────────────────┤
│  Existing: GroupingEngine / LocalMLScorer / ImportManager     │
│  FolderAdapter / PhotosLibraryAdapter / FolderExporter        │
│  (V1/V2 已稳定，V3 不动)                                     │
├──────────────────────────────────────────────────────────────┤
│  Models                                                      │
│  ★ ArchiveManifestEntry (归档清单条目)                        │
│    MediaAsset / PhotoGroup / ExportOptions (已有，V3 扩展)    │
│    ModelConfig.calibrationOffset (V3 实际使用)                │
└──────────────────────────────────────────────────────────────┘
```

★ = V3 新增

## 3.2 模块详细设计

### F1 SDCardAdapter（SD 卡导入）

**位置**：`Sources/Luma/Services/Import/SDCardAdapter.swift`

```swift
final class SDCardAdapter: ImportSourceAdapter {
    var displayName: String { volumeName }
    var connectionState: AsyncStream<ConnectionState>

    func enumerate() async throws -> [DiscoveredItem]
    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage?
    func copyPreview(_ item: DiscoveredItem, to: URL) async throws
    func copyOriginal(_ item: DiscoveredItem, to: URL) async throws
    func copyAuxiliary(_ item: DiscoveredItem, to: URL) async throws
}
```

**子组件**：

- `DiskArbitrationMonitor`：`DASessionRef` + `DARegisterDiskAppearedCallback` / `DARegisterDiskDisappearedCallback` 监听可移除磁盘挂载/卸载。过滤条件：`kDADiskDescriptionMediaRemovableKey == true` 且 `kDADiskDescriptionVolumePathKey` 下存在 `DCIM/` 目录。
- `DCIMScanner`：`FileManager.enumerator(at: volumeURL.appending(path: "DCIM"))` 递归遍历，按 UTType 过滤 JPEG/HEIC/RAW。
- `RAWJPEGPairer`：建立 `[baseName: (jpeg: URL?, raw: URL?)]` 字典，去掉扩展名匹配。仅有 RAW 时通过 `CGImageSourceCreateThumbnailAtIndex` 提取内嵌预览。

**并发控制**：SD 卡拷贝限制 2-3 并发（UHS-I 顺序读最优，随机读降低吞吐）。

**设备拔出**：`connectionState` 发出 `.disconnected`，`ImportManager` 暂停当前 Phase 并持久化进度 JSON，UI 提示"请重新插入 SD 卡"。重新挂载后自动对比进度 JSON 恢复。

### F2 + F3 LightroomExporter + XMPSidecarWriter

**位置**：
- `Sources/Luma/Services/Export/LightroomExporter.swift`
- `Sources/Luma/Services/Export/XMPSidecarWriter.swift`

```swift
struct LightroomExporter: ExportDestinationAdapter {
    var displayName: String { "Lightroom Classic" }
    func export(assets: [MediaAsset], options: ExportOptions) async throws -> ExportResult
    func validateConfiguration() async throws -> Bool
}
```

**导出流程**：
1. 遍历 picked assets
2. 拷贝 RAW（优先）或 JPEG/HEIC 到 `lrAutoImportFolder`
3. 对每个文件调用 `XMPSidecarWriter.generate(asset:options:)` 生成同名 `.xmp` 文件
4. Lightroom Classic 自动导入文件夹检测到新文件后导入

**XMPSidecarWriter**（纯函数，无副作用）：

```swift
struct XMPSidecarWriter {
    static func generate(asset: MediaAsset, options: ExportOptions) -> String
}
```

生成的 XMP XML 包含：

| 数据来源 | XMP 字段 | Lightroom 显示 |
|----------|----------|----------------|
| `aiScore.overall` | `xmp:Rating` (1-5) | 星级 |
| `userDecision` | `xmp:Label` | 颜色标签 Green/Yellow/Red |
| `aiScore.comment` + issues | `dc:subject` | 关键词 |
| group name | `lr:hierarchicalSubject` | 层级关键词 |
| `aiScore.comment` | `dc:description` | 说明字段 |
| `editSuggestions.adjustments` | `crs:Exposure2012` 等 | 修图滑块预设 |
| `editSuggestions.crop` | `crs:CropTop/Bottom/Left/Right` | 裁切预览 |

**评分→星级映射**：90+ → 5 星，75-89 → 4 星，60-74 → 3 星，45-59 → 2 星，<45 → 1 星

**XMP 模板策略**：用 Swift 多行字符串字面量拼接 XML，不引入 XML 库。`crs:` 字段仅在 `options.writeEditSuggestionsToXmp == true` 且 `asset.editSuggestions != nil` 时写入。

### F4 + F5 归档模块

**位置**：
- `Sources/Luma/Services/Archive/ArchiveVideoGenerator.swift`
- `Sources/Luma/Services/Archive/ShrinkKeepArchiver.swift`
- `Sources/Luma/Services/Archive/ArchiveManifest.swift`

#### ArchiveVideoGenerator

```swift
final class ArchiveVideoGenerator {
    func generate(
        group: PhotoGroup,
        assets: [MediaAsset],
        outputDirectory: URL,
        onProgress: @Sendable (Double) -> Void
    ) async throws -> URL
}
```

**生成流程**：
1. `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`
2. 输出参数：H.265 (HEVC), 1920x1080, 30fps, CRF ≈ 28
3. 每张照片：
   - 读取 preview JPEG/HEIC → `CGImage` → 缩放到 1920x1080（letterbox 填充黑色）
   - Ken Burns：随机选起始 rect 和终止 rect（缩放 1.0-1.15×，平移 0-5%），线性插值生成中间帧
   - 停留 1.5-2 秒（45-60 帧）
4. 相邻照片交叉淡入淡出 0.3 秒（9 帧 alpha blend）
5. 文字叠加：`Core Graphics` 在 `CVPixelBuffer` 上绘制组名 + 日期 + 地点（底部半透明条）
6. 每张照片处理完回调 `onProgress`

#### ShrinkKeepArchiver

```swift
struct ShrinkKeepArchiver {
    static func shrink(asset: MediaAsset, outputDirectory: URL) async throws -> URL
}
```

- 读取 preview JPEG/HEIC → `CGImage`
- 缩放到长边 2048px（`CGContext` draw）
- 输出 JPEG 质量 80%，通过 `CGImageDestinationAddImage` 附带原始 EXIF properties
- 成功后删除 RAW 文件（`FileManager.removeItem`）

#### ArchiveManifest

```swift
struct ArchiveManifestEntry: Codable {
    let originalFileName: String
    let captureDate: Date
    let aiScore: Int?
    let archiveMethod: String      // "video" / "shrink" / "discard"
    let archiveOutputPath: String?
}
```

每次归档操作完成后追加写入 `<projectDir>/archive_manifest.json`。

### F6 ScoreCalibrator（评分校准）

**位置**：`Sources/Luma/Services/AI/ScoreCalibrator.swift`

```swift
struct CalibrationResult: Codable {
    let mean: Double      // μ
    let stdDev: Double    // σ
    let sampleCount: Int
}

struct ScoreCalibrator {
    static func calibrate(
        provider: VisionModelProvider,
        referenceImages: [URL]
    ) async throws -> CalibrationResult

    static func normalize(rawScore: Int, calibration: CalibrationResult) -> Int
}
```

**流程**：
1. App bundle 内置 20 张参考照（好 7 / 中 7 / 差 6），覆盖不同场景
2. 调用 `provider.scoreGroup()` 对 20 张评分，收集 `overall` 数组
3. 计算 μ（均值）和 σ（标准差）
4. 归一化公式：`normalized = 50 + (raw - μ) / σ × 15`（目标 μ=50, σ=15）
5. 将 `CalibrationResult` 序列化写入 `ModelConfig`，后续该模型返回的所有评分自动映射

**边界**：σ < 1 时视为模型输出无差异（所有分一样），报警告并跳过归一化。

### F7 AIGroupNamer（AI 组名生成）

**位置**：`Sources/Luma/Services/AI/AIGroupNamer.swift`

```swift
struct AIGroupNamer {
    static func generateName(
        provider: VisionModelProvider,
        representativeImage: ProviderImagePayload,
        currentName: String,
        location: String?
    ) async throws -> String
}
```

**流程**：
1. 取组内最多20张照片作为代表
2. 构造简短 Prompt：给出当前名称和位置信息，要求返回 ≤ 8 个汉字的描述性名称（如"清水寺·日落"）
3. 用 primary 模型发起单次 API 调用
4. 失败时 fallback 到原有的时间+地点规则名称

**调用时机**：在 `startCloudScoring` 完成后（或用户手动触发），对所有组串行调用。

## 3.3 关键时序

### SD 卡导入

```
DiskArbitration ─── volumeAppeared ──→ DiskArbitrationMonitor
                                              │
                                              ▼
                                    SDCardAdapter.enumerate()
                                              │
                                    ┌─────────┴──────────┐
                                    ▼                    ▼
                             DCIMScanner          RAWJPEGPairer
                                    │                    │
                                    └─────────┬──────────┘
                                              ▼
                                      ImportManager
                                    (复用现有三阶段管线)
                                              │
                               volumeDisappeared? ─→ pause + persist progress
```

### Lightroom 导出 + XMP

```
User → ExportPanel ── "导出到 Lightroom" ──→ ProjectStore
                                                │
                                                ▼
                                      LightroomExporter.export()
                                                │
                              ┌──────────────────┤
                              ▼                  ▼
                      copy RAW/JPEG    XMPSidecarWriter.generate()
                      to LR folder       ├─ Rating (overall→1-5)
                                         ├─ Label (decision→color)
                                         ├─ Keywords (issues+comment)
                                         ├─ Description (comment)
                                         ├─ crs:Exposure2012 等
                                         └─ crs:CropTop/Bottom/Left/Right
```

### 归档流程

```
User → ExportPanel ── "处理未选中照片" ──→ ProjectStore
                                                │
                               ┌────────────────┼────────────────┐
                               ▼                ▼                ▼
                        archiveVideo      shrinkKeep          discard
                               │                │                │
                               ▼                ▼                ▼
                  ArchiveVideoGenerator   ShrinkKeepArchiver   FileManager
                  (AVAssetWriter+KB)      (resize+EXIF)       .removeItem
                               │                │
                               └────────┬───────┘
                                        ▼
                              ArchiveManifest.append()
                                        │
                                        ▼
                              archive_manifest.json
```

# 四、评估和验收

## 风险点

| 风险 | 等级 | 缓解 |
|------|------|------|
| DiskArbitration API 在沙盒环境可能受限 | 高 | 需要 `com.apple.security.files.user-selected.read-write` entitlement；测试真机环境 |
| SD 卡热拔插导致文件拷贝中途中断 | 中 | 原子写入（.importing 后缀 → 完成后 rename）；进度 JSON 持久化断点续传 |
| XMP 格式兼容性（Lightroom 版本差异） | 中 | 严格遵循 Adobe XMP SDK 文档；用 Lightroom Classic 2024+ 实机验收 |
| AVAssetWriter H.265 编码在低配机上较慢 | 低 | 归档是低优先级后台任务（`.utility` QoS）；可选降级到 H.264 |
| 校准 20 张参考照的 API 费用 | 低 | 约 $0.01-0.05（一次性）；校准前弹窗告知 |
| AI 组名生成增加 API 调用数 | 低 | 串行调用且每组仅 1 张图；可在设置中关闭 |

## 验收 Checklist

- [ ] 插入 SD 卡后 DiskArbitration 检测并弹出导入提示
- [ ] DCIM 扫描正确识别 JPEG/HEIC/RAW 并完成配对
- [ ] SD 卡拔出后暂停导入，重新插入后断点续传
- [ ] Lightroom 导出生成的 XMP 在 Lightroom Classic 中正确显示星级/标签/关键词/说明
- [ ] XMP 中 crs 滑块值在 Lightroom 修图面板中正确预设
- [ ] Ken Burns 视频 H.265 1080p 可播放，效果流畅
- [ ] 缩小保留后文件尺寸 ≤ 长边 2048px，EXIF 完整，RAW 已删除
- [ ] `archive_manifest.json` 正确记录每张照片的归档方式
- [ ] 校准 20 张参考照后 μ/σ 写入 ModelConfig
- [ ] 校准后评分经线性映射，分布符合预期（μ≈50, σ≈15）
- [ ] AI 组名生成成功后分组列表显示语义名称
- [ ] AI 组名失败 fallback 到时间+地点
- [ ] 全量 `swift test` 通过
- [ ] 不引入新的重型外部依赖
