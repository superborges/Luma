# Luma（拾光）— codex 开发计划

> 本文档是配合 PRODUCT_SPEC.md 使用的分阶段开发指南。
> 每个阶段都产出一个可运行的增量版本，建议按顺序执行。

---

## 开发原则

1. **增量交付**：每个 Phase 结束后都是可运行的 App
2. **先跑通再优化**：V1 用最简单的方式实现，后续迭代优化
3. **PRODUCT_SPEC.md 是权威参考**：所有数据模型、协议定义、Prompt 设计以该文档为准
4. **测试友好**：每个模块都有明确的输入输出，便于用模拟数据测试

---

## Phase 0：项目脚手架（预计 30 分钟）

### 目标
创建 Xcode 项目基础结构，确保能编译运行。

### codex Prompt
```
创建一个 macOS SwiftUI App 项目 "Luma"，使用 Swift 和 SwiftUI，targets macOS 14+。

项目结构：
Luma/
├── LumaApp.swift                   # App 入口
├── Models/                         # 数据模型
│   ├── MediaAsset.swift
│   ├── PhotoGroup.swift
│   ├── AIScore.swift
│   ├── EditSuggestions.swift
│   └── ExportOptions.swift
├── Services/                       # 业务逻辑
│   ├── Import/
│   │   ├── ImportSourceAdapter.swift    # 协议定义
│   │   ├── SDCardAdapter.swift
│   │   ├── FolderAdapter.swift
│   │   └── ImportManager.swift
│   ├── Grouping/
│   │   └── GroupingEngine.swift
│   ├── AI/
│   │   ├── VisionModelProvider.swift    # 协议定义
│   │   ├── OpenAICompatibleProvider.swift
│   │   ├── GeminiProvider.swift
│   │   ├── AnthropicProvider.swift
│   │   ├── LocalMLScorer.swift
│   │   ├── BatchScheduler.swift
│   │   └── ResponseNormalizer.swift
│   ├── Export/
│   │   ├── ExportDestinationAdapter.swift  # 协议定义
│   │   ├── PhotosAppExporter.swift
│   │   ├── LightroomExporter.swift
│   │   ├── FolderExporter.swift
│   │   └── XMPWriter.swift
│   └── Archive/
│       └── VideoArchiver.swift
├── Views/
│   ├── MainWindow/
│   │   ├── ContentView.swift           # 三栏主布局
│   │   ├── GroupSidebar.swift          # 左栏：分组列表
│   │   ├── PhotoGrid.swift            # 中栏：照片网格
│   │   └── DetailPanel.swift          # 右栏：评分+修图建议
│   ├── Import/
│   │   └── ImportProgressView.swift
│   ├── Export/
│   │   └── ExportPanelView.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── AIModelConfigView.swift
├── Utilities/
│   ├── ThumbnailCache.swift
│   ├── EXIFParser.swift
│   ├── KeychainHelper.swift
│   └── CostTracker.swift
└── Resources/
    └── Assets.xcassets

请按照 PRODUCT_SPEC.md 中定义的数据模型创建所有 Models/ 下的 Swift 文件，
包含完整的 struct/enum 定义、Codable 遵循和必要的计算属性。

所有 Services/ 下的文件先创建协议定义和空实现（方法体写 fatalError("TODO")），
确保项目能编译通过。

Views/ 先用 placeholder 文本，确保三栏布局框架搭建完成。
```

### 验收标准
- [x] Xcode 项目能编译运行
- [x] 显示三栏布局的空壳窗口
- [x] 所有数据模型定义完整

---

## Phase 1：文件夹导入 + 缩略图浏览（预计 2-3 小时）

### 目标
实现最基础的导入能力：手动选择一个包含照片的文件夹，扫描 JPEG/HEIC 文件，显示缩略图网格。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "2. 导入模块" 部分，实现 FolderAdapter 和基础浏览功能。

具体任务：
1. 实现 FolderAdapter：
   - 使用 NSOpenPanel 让用户选择文件夹
   - 递归扫描 .jpg/.jpeg/.heic/.heif/.arw/.cr3/.nef/.raf/.dng 文件
   - 按文件名（去掉扩展名）做 RAW+JPEG 配对
   - 如果只有 RAW 没有 JPEG，用 CGImageSource 从 RAW 提取内嵌预览
   - 返回 [MediaAsset] 数组

2. 实现缩略图提取（ThumbnailCache）：
   - 使用 CGImageSourceCreateThumbnailAtIndex 提取 400px 缩略图
   - 内存缓存（NSCache，最多 500 张）+ 磁盘缓存（thumbnails/ 目录）
   - 异步加载，先显示占位色块再替换为真实缩略图

3. 实现 EXIF 解析（EXIFParser）：
   - CGImageSourceCopyPropertiesAtIndex 提取元数据
   - 解析字段：captureDate, gpsCoordinate, focalLength, aperture, 
     shutterSpeed, iso, cameraModel, lensModel, imageWidth, imageHeight
   - 缩略图提取和 EXIF 解析在同一次 CGImageSource 打开中完成

4. 实现照片网格视图（PhotoGrid）：
   - SwiftUI LazyVGrid，4 列
   - 每张照片显示缩略图 + 文件名
   - 点击选中（蓝色边框高亮）
   - 双击或 Space 键切换放大/网格视图
   - 放大视图加载全尺寸 JPEG（如果已拷贝本地）或更大缩略图

5. 实现右栏 EXIF 面板（DetailPanel）：
   - 选中照片时显示 EXIF 信息表格
   - 显示：相机、焦距、光圈、快门、ISO、拍摄时间

测试方式：用一个包含 20-50 张 JPEG 的文件夹测试。
```

### 验收标准
- [x] 点击"导入文件夹"可选择目录并扫描照片
- [x] 缩略图网格流畅显示（60fps 滚动）
- [x] 点击照片显示 EXIF 信息
- [x] 支持 JPEG 和 HEIC 格式
- [x] RAW+JPEG 能正确配对

---

## Phase 2：智能分组（预计 1-2 小时）

### 目标
导入后自动按时间和视觉相似度分组。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "4. 智能分组模块" 部分，实现 GroupingEngine。

具体任务：
1. 第一层 - 时间聚类：
   - 按 captureDate 排序
   - 相邻照片时间差 > 30 分钟则拆为新组
   - 生成 PhotoGroup 数组

2. 第二层 - GPS 空间聚类（有 GPS 数据时）：
   - 在时间组内执行简单的距离聚类
   - 两张照片距离 > 200 米则拆分
   - 使用 CLLocation.distance(from:) 计算

3. 第三层 - 视觉相似度聚类：
   - 使用 Vision 框架 VNGenerateImageFeaturePrintRequest 提取特征向量
   - 组内两两计算 featurePrint.computeDistance()（返回欧氏距离，值域约 0–4+）
   - 距离 < **0.8** 的归为同一 SubGroup
   - 这一步基于 400px 缩略图执行，不需要原图

4. 分组命名：
   - 有 GPS → CLGeocoder 反向编码获取地名（异步，先显示"组1"再替换）
   - 无 GPS → 日期 + 时间段（"4月3日·下午"）

5. 左栏 GroupSidebar 视图：
   - 列表显示每个组：名称、照片数量
   - 点击组 → 中栏显示该组照片
   - 当前选中组高亮

注意：VNGenerateImageFeaturePrintRequest 在 macOS 14+ 可用。
特征提取对 500 张缩略图大约需要 1-2 分钟，用后台队列异步执行，
提取完成后再计算相似度和子分组。分组过程中 UI 保持可用。
```

### 验收标准
- [x] 导入后自动按时间分组
- [x] 左栏显示分组列表，点击切换
- [x] 有 GPS 数据的照片能按地理位置细分
- [x] 视觉相似的照片在同一子组内

---

## Phase 3：本地 Core ML 初筛（预计 1-2 小时）

### 目标
用 Apple 原生框架做技术质量评估，自动淘汰废片。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "5.2 本地 Core ML 评估" 部分，实现 LocalMLScorer。

具体任务：
1. 模糊检测：
   - 将缩略图转为灰度 CIImage
   - 应用 CIFilter "CILaplacian" 卷积
   - 计算结果图像的方差（variance）
   - 方差 < 阈值（建议 100）→ 标记为模糊
   - 或者使用更简单的方式：先用 Core Image 做拉普拉斯，再算标准差

2. 曝光评估：
   - 计算 RGB 直方图（CIImage → CIFilter "CIAreaHistogram"）
   - 高光区域（>240）占比 > 30% → 标记过曝
   - 暗部区域（<15）占比 > 40% → 标记欠曝

3. 人脸检测 + 闭眼检测：
   - VNDetectFaceLandmarksRequest 检测人脸
   - 如果检测到人脸，检查 leftEye/rightEye landmarks
   - 使用 VNDetectFaceCaptureQualityRequest 获取 faceCaptureQuality 分数
   - quality < 0.3 且有人脸 → 标记为闭眼/表情问题

4. 综合本地评分：
   - 非废片照片获得基础分（50分起步）
   - 模糊/过曝/欠曝/闭眼 → 标记为废片，分数设为 0-30
   - 将本地评分存入 MediaAsset.aiScore（provider = "local-coreml"）

5. UI 标记：
   - 废片在网格中显示半透明 + 红色标签（"模糊"/"过曝"/"闭眼"）
   - 左栏分组进度条：绿色=已评/灰色=待评/红色=废片
   - 状态栏显示：正在评估 x/500... 淘汰 y 张废片

性能要求：500 张 400px 缩略图在 M1 上 < 3 分钟。
使用 OperationQueue 并发执行，maxConcurrentOperationCount = 4。
```

### 验收标准
- [x] 导入后自动开始本地评估
- [x] 模糊/过曝/闭眼照片被正确标记
- [x] 废片在 UI 上有明显的视觉区分
- [x] 处理速度满足性能要求

---

## Phase 4：多模型云端 AI 评分（预计 3-4 小时）

### 目标
接入多个 Vision API 进行美学评分和修图建议，支持用户自定义配置。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "5. AI 评分模块" 部分，实现完整的多模型 AI 评分系统。

具体任务：

1. 模型配置系统：
   a. ModelConfig 数据模型（参考 spec 5.3.2）
   b. API Key 使用 KeychainHelper 加密存储（基于 Security.framework）
   c. 配置持久化到 UserDefaults（敏感信息除外）
   d. 设置界面 AIModelConfigView：
      - 已配置模型列表（显示名称、协议、状态、费用）
      - "当前使用"标记 + 切换
      - 添加新模型表单：协议选择(下拉) + Endpoint + Model ID + API Key
      - "测试连接"按钮（发送一张示例图片验证）
      - 评分策略选择（省钱/均衡/最佳质量）

2. 三种 API 协议实现（都实现 VisionModelProvider 协议）：

   a. OpenAICompatibleProvider：
      - POST {endpoint}/chat/completions
      - Headers: Authorization: Bearer {apiKey}
      - Body: model, messages (含 image_url type=base64), response_format=json_object
      - 兼容：GPT-4o, GPT-4o-mini, DeepSeek-VL2, 通义千问VL, GLM-4V, Ollama

   b. GeminiProvider：
      - POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={apiKey}
      - Body: contents 中使用 inlineData (base64 image) + text parts
      - 不支持 json_object response_format，在 prompt 中强调 JSON only

   c. AnthropicProvider：
      - POST {endpoint} (默认 https://api.anthropic.com/v1/messages)
      - Headers: x-api-key: {apiKey}, anthropic-version: 2023-06-01
      - Body: model, messages 中使用 image type source=base64
      - 响应取 content[0].text

3. 图片预处理（发送前）：
   - 将 JPEG/HEIC 缩放到长边 1024px
   - JPEG 压缩质量 85%
   - 转为 base64 字符串
   - 计算预估 token 数（base64 长度 / 4 * 3 / 750 ≈ image tokens）

4. Prompt 管理：
   - 使用 PRODUCT_SPEC.md 中定义的两套 Prompt 模板
   - Prompt 1（组内批量评分）：传入同组 5-8 张照片，返回评分数组
   - Prompt 2（单张精评+修图建议）：传入单张照片+EXIF，返回 EditSuggestions
   - 模板变量替换：{n}, {group_name}, {camera_model}, {lens}, {time_range} 等

5. ResponseNormalizer：
   - 从三种 API 响应中提取 text content
   - 清除 markdown 代码块标记（```json ... ```）
   - JSON.parse → 映射到 AIScore / EditSuggestions 模型
   - 容错处理：字段缺失用默认值，解析失败标记为 .scoreFailed

6. BatchScheduler：
   - 输入：所有技术合格的 MediaAsset（本地评分非废片的）
   - 按 PhotoGroup 打包批次
   - 根据评分策略决定：
     - 省钱模式：primary 模型全量，无 Prompt 2
     - 均衡模式：primary 全量 + premiumFallback 仅 Top 20%（用 Prompt 2）
     - 最佳质量：premiumFallback 全量（Prompt 1 + Prompt 2）
   - 并发控制：OperationQueue, maxConcurrent = ModelConfig.maxConcurrency
   - 重试策略：指数退避（1s, 2s, 4s），最多 3 次
   - 实时费用追踪（CostTracker）：累计 token 消耗 × 单价

7. CostTracker：
   - 记录每次 API 调用的 input/output tokens 和费用
   - 状态栏实时显示 "AI 评分中 78% · 已花费 $0.34"
   - 费用超过阈值（UserDefaults 中配置，默认 $5）→ 弹窗暂停

8. DetailPanel 扩展：
   - 显示 AI 综合评分（大字号）
   - 五维评分条（构图/曝光/色彩/锐度/故事性）
   - AI 评语文字
   - 修图建议卡片（如果有 Prompt 2 结果）：
     - 裁切建议：缩略图上叠加裁切框 + 三分法网格
     - 滤镜风格推荐
     - 参数调整可视化（偏移条形图）
     - 局部调整列表
     - 修图叙述

注意：
- 所有网络请求使用 URLSession，超时 60 秒
- API Key 测试连接时发送一张 256px 的纯色测试图片，验证返回格式
- 所有 Prompt 的 comment/narrative 字段要求中文回复
```

### 验收标准
- [x] 能配置至少 2 个不同模型（如 Gemini + DeepSeek）
- [x] 测试连接功能正常工作
- [x] 批量评分能按组发送并正确解析结果
- [x] 费用追踪显示准确
- [x] 右栏显示完整评分和修图建议（如果有）
- [x] 切换模型后评分能正常工作

---

## Phase 5：人工挑选交互（预计 1-2 小时）

### 目标
实现完整的快捷键标记和挑选交互。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "6. 人工挑选模块" 部分，实现 Cull 交互。

具体任务：

1. 快捷键系统：
   - P → 标记当前选中照片为 .picked，自动跳下一张
   - X → 标记为 .rejected，自动跳下一张
   - U → 撤销标记，回到 .pending
   - ← / → → 上一张 / 下一张
   - Space → 切换网格/放大视图
   - 1-5 → 手动设置星级（覆盖 AI 分数映射）
   - Cmd+A → 选中当前组所有 AI 推荐照片（recommended=true）
   - Tab → 跳到下一个组
   
   使用 SwiftUI .onKeyPress 或 NSEvent 键盘监听实现。
   快捷键仅在主窗口聚焦时生效。

2. 网格视图增强：
   - AI 推荐照片：蓝色 2px 边框 + 左上角 "AI 推荐" 蓝色标签
   - picked 照片：绿色 2px 边框 + 左下角 ★ 标记
   - rejected 照片：半透明 (opacity 0.5)
   - 废片（本地淘汰）：半透明 + 红色标签显示原因
   - 右下角显示 AI 分数
   - 照片决策状态变化时有轻微动画

3. 状态栏（顶部）：
   - 项目名称 + 总数 + 组数
   - AI 评分进度条（百分比 + 动画）
   - 统计：已选 X 张 · 已拒 Y 张 · 待定 Z 张
   - "导出选中" 按钮 + "归档未选" 按钮

4. 左栏分组进度条：
   - 每个组下方显示三色进度条
   - 绿色段 = picked 比例
   - 灰色段 = pending 比例
   - 红色段 = rejected 比例（含废片）
   - 显示 "推荐 N 张" 文字

5. Cmd+Z 撤销支持：
   - 使用 UndoManager 记录标记操作
   - 支持多步撤销

6. 放大视图：
   - 显示全尺寸 JPEG/HEIC（如果 Phase 2 已拷贝完成）
   - 双指缩放 + 拖拽平移
   - 底部显示快捷键提示栏
   - 左右滑动切换照片
```

### 验收标准
- [x] 所有快捷键正常工作
- [x] P/X 标记后自动跳下一张
- [x] Cmd+A 批量选中 AI 推荐
- [x] 状态栏实时更新统计
- [x] Cmd+Z 撤销正常工作

---

## Phase 6：导出模块（预计 3-4 小时）

### 目标
实现三种导出目标和完整的导出面板。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "7. 导出模块" 部分，实现完整导出功能。

具体任务：

1. ExportPanelView 导出面板（模态窗口）：
   - 三种导出目标单选：Mac 照片 App / Lightroom Classic / 本地文件夹
   - 根据选择显示对应的子选项
   - Mac 照片 App 选项：创建相册、合并RAW+JPEG、保留Live Photo、写入AI评语
   - Lightroom 选项：自动导入文件夹路径选择、写入XMP、写入修图建议
   - 文件夹选项：目录模板选择（按日期/按场景/按星级）、输出路径
   - 未选中照片处理：归档视频 / 缩小保留 / 直接丢弃
   - 底部：警告提示 + 取消/导出按钮
   - 导出按钮显示 "导出 X 张 + 归档 Y 张"

2. PhotosAppExporter：
   - 请求 PHPhotoLibrary.requestAuthorization(.readWrite)
   - PHPhotoLibrary.shared().performChanges {
       对每个 picked 的 MediaAsset：
       a. let creation = PHAssetCreationRequest.forAsset()
       b. 如果有 RAW/DNG → addResource(.photo, fileURL:)          ← 主资源
       c. 如果有 JPEG/HEIC → addResource(.alternatePhoto, fileURL:) ← 预览资源
          （注意：RAW 是 .photo 主资源，JPEG 是 .alternatePhoto 预览资源，
            顺序不可颠倒；照片 App 默认显示 JPEG 但编辑时可切换 RAW）
       d. 如果是 Live Photo → addResource(.pairedVideo, fileURL:)
       e. creation.creationDate = asset.metadata.captureDate
       f. creation.location = CLLocation(from: asset.metadata.gpsCoordinate)
     }
   - 如果 createAlbumPerGroup 开启：
     对每个 PhotoGroup 创建 PHAssetCollectionChangeRequest
     把该组的 assets 加入相册
   - 进度回调：每完成一个 asset 更新进度条

3. XMPWriter：
   - 生成标准 XMP sidecar XML 文件
   - 写入字段（参考 PRODUCT_SPEC.md 7.3.1 的字段映射表）：
     a. xmp:Rating → overall 分数映射到 1-5 星
     b. xmp:Label → decision 映射到颜色（Green/Yellow/Red）
     c. dc:subject → AI 生成的关键词标签数组
     d. lr:hierarchicalSubject → 分组层级（旅行|京都|清水寺）
     e. dc:description → AI 评语
   - 如果 writeEditSuggestionsToXmp 开启：
     f. crs:Exposure2012 → adjustments.exposure
     g. crs:Contrast2012 → adjustments.contrast
     h. crs:Highlights2012 → adjustments.highlights
     i. crs:Shadows2012 → adjustments.shadows
     j. crs:Temperature → adjustments.temperature (需转为绝对值，基准 5500 + 偏移)
     k. crs:Saturation → adjustments.saturation
     l. crs:Vibrance → adjustments.vibrance
     m. crs:HasCrop / CropTop / CropBottom / CropLeft / CropRight → crop 建议
   - XMP 文件与照片同名但扩展名为 .xmp

4. LightroomExporter：
   - 将选中照片的 RAW 原文件拷贝到自动导入文件夹
   - 同时生成 XMP sidecar（使用 XMPWriter）
   - 按用户选择的目录模板组织子目录：
     - byDate: YYYY-MM-DD/
     - byGroup: 01_组名/
     - byRating: 5star_精选/ 4star_优秀/ ...

5. FolderExporter：
   - 与 LightroomExporter 类似，但输出到用户选择的任意目录
   - 可选是否附带 XMP

6. 导出进度视图：
   - 模态进度窗口，显示：当前进度 / 总数、速度、预计剩余时间
   - 支持取消
   - 完成后显示汇总：导出 X 张到 [目标]，归档 Y 张
```

### 验收标准
- [x] 三种导出目标都能正常工作
- [x] 照片 App 导出后照片出现在正确的时间线位置
- [x] Lightroom XMP 包含评分、标签、关键词
- [x] 修图建议能正确写入 XMP 滑块值
- [x] RAW+JPEG 在照片 App 中合并为单个素材

---

## Phase 7：视频归档（预计 1-2 小时）

### 目标
将未选中照片按组生成回忆视频。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "8. 归档模块" 部分，实现 VideoArchiver。

具体任务：

1. VideoArchiver 核心逻辑：
   使用 AVAssetWriter 生成 H.265 1080p 视频。
   
   对每个 PhotoGroup 中的 rejected 照片：
   a. 读取 JPEG/HEIC 预览图
   b. 缩放到 1920x1080（保持比例，不足部分黑边或高斯模糊背景填充）
   c. 每张照片停留 1.5 秒
   d. Ken Burns 效果：随机选择（向左平移 / 向右平移 / 缓慢放大 / 缓慢缩小）
      - 平移幅度：画面宽度的 5-8%
      - 缩放幅度：1.0 → 1.08
      - 使用 Core Image CIAffineTransform 实现
   e. 相邻照片之间 0.3 秒交叉溶解（crossfade）
   f. 视频开头叠加文字标注：组名 + 日期 + 地点（白色文字 + 半透明黑色背景条）
   
   AVAssetWriter 配置：
   - outputFileType: .mp4
   - videoSettings: H.265 (kCMVideoCodecType_HEVC)
   - 分辨率: 1920x1080
   - 帧率: 30fps
   - 码率: ~8 Mbps (质量与文件大小的平衡)

2. 进度追踪：
   - 每完成一个组的视频生成，更新整体进度
   - 显示：正在生成 "清水寺·日落" 归档视频 (3/12 组)

3. 归档清单 (archive_manifest.json)：
   - 每个视频的：文件名、组名、包含照片数量、时长、文件大小
   - 每张归档照片的：原始文件名、拍摄时间、AI评分、在视频中的起止时间
   - 便于未来检索

4. 缩小保留方案（备选处理方式）：
   - 如果用户选择 "缩小保留" 而非 "归档视频"
   - 将 JPEG/HEIC 缩放到长边 2048px，JPEG 质量 80%
   - 保留完整 EXIF 元数据（使用 CGImageDestination 写入）
   - 存储到 archives/shrunk/ 目录
   - 删除对应的 RAW 原文件

5. 存储路径：
   ~/Library/Application Support/Luma/archives/
     └── {batch_name}/
         ├── 01_清水寺_日落_archive.mp4
         ├── 02_伏见稻荷_archive.mp4
         └── archive_manifest.json
```

### 验收标准
- [x] 每组生成一个 MP4 归档视频
- [x] Ken Burns 效果自然流畅
- [x] 视频开头有组名文字标注
- [x] archive_manifest.json 记录完整

---

## Phase 8：SD 卡 + iPhone 导入（预计 2-3 小时）

### 目标
实现真正的 SD 卡自动检测和 iPhone USB 直连导入。

### codex Prompt
```
参考 PRODUCT_SPEC.md 的 "2.2.1 SD 卡导入" 和 "2.2.2 iPhone USB 直连" 部分。

具体任务：

1. SDCardAdapter：
   a. 使用 DispatchSource.makeFileSystemObjectSource 监控 /Volumes/ 目录
   b. 新卷出现时，检查是否包含 DCIM/ 目录（SD 卡特征）
   c. 扫描文件树，执行 RAW+JPEG 配对（复用 FolderAdapter 逻辑）
   d. 三阶段异步拷贝：
      - Phase 1：提取 EXIF 缩略图（主线程级别）
      - Phase 2：拷贝 JPEG/HEIC（.userInitiated 队列，并发 2-3 个文件）
      - Phase 3：拷贝 RAW（.utility 队列，可中断可恢复）
   e. 拷贝写入 .importing 临时文件，完成后原子重命名
   f. 进度记录持久化到 manifest.json，支持断点续传
   g. 设备拔出时优雅暂停 + 提示用户

2. iPhoneAdapter：
   a. 使用 ImageCaptureCore 框架
   b. ICDeviceBrowser 监听设备连接
   c. 连接后 requestOpenSession()
   d. 枚举 ICCameraItem 列表
   e. 缩略图：requestThumbnail() 获取
   f. 文件下载：requestDownloadFile() 逐个下载到本地
   g. Live Photo 配对：
      - 遍历所有 item，找到 .mov 和 .heic 文件
      - 从 HEIC 的 EXIF MakerNote 中提取 ContentIdentifier
      - 从 MOV metadata 中提取相同的 ContentIdentifier
      - 匹配成对
   h. ProRAW 识别：.dng 扩展名 + EXIF 中 Make="Apple"
   
   注意：需要在 Info.plist 添加 com.apple.security.device.camera entitlement
   注意：iPhone 需要用户在手机上点击"信任此电脑"

3. ImportManager（统一管理）：
   a. 维护活跃的 ImportSourceAdapter 列表
   b. 自动检测：SD 卡插入 / iPhone 连接 → 弹窗提示 "检测到 [设备名]，是否导入？"
   c. 用户确认后创建导入批次，调用 adapter.enumerate() → 进入导入流程
   d. 支持同时导入多个来源（如 SD 卡 + iPhone）
   e. 导入完成后自动触发分组 + 本地 AI 评估

4. ImportProgressView：
   - 显示三个阶段的进度
   - Phase 1 完成后立即切换到主浏览界面
   - Phase 2/3 在后台继续，状态栏显示进度
```

### 验收标准
- [x] 插入 SD 卡自动弹窗提示导入
- [x] iPhone USB 连接后能枚举并导入照片
- [x] Live Photo 正确配对
- [x] 三阶段导入体验流畅（缩略图秒级可见）
- [x] 设备拔出能优雅处理

---

## Phase 9：打磨与优化（预计 2-3 小时）

### 目标
优化性能、完善 UI 细节、处理边界情况。

### codex Prompt
```
对 Luma 进行全面打磨，参考 PRODUCT_SPEC.md 的性能目标和错误恢复要求。

具体任务：

1. 性能优化：
   - LazyVGrid 照片网格：实现 PHCachingImageManager 风格的预加载
     （预加载可见区域 ± 2 屏的缩略图，释放远离区域的缩略图）
   - 确保网格滚动 60fps（Profile with Instruments）
   - 大批量照片（1000+）的内存控制 < 500MB

2. 错误恢复：
   - manifest.json 每次状态变更后保存（使用 debounce 500ms 避免频繁写入）
   - App 启动时检查未完成的导入任务，提示用户是否继续
   - API 调用失败后的 UI 提示和重试选项

3. UI 细节：
   - App 图标设计（可以用 SF Symbols 组合）
   - 窗口标题栏显示当前项目名
   - Dark mode 完整适配
   - 菜单栏：文件(导入/导出) / 编辑(撤销/标记) / 视图(网格/放大/面板切换)
   - 首次启动引导（简单的欢迎页）

4. 数据管理：
   - "项目"概念：每次导入创建一个项目，支持多项目切换
   - 项目列表页面（启动时显示，或菜单中选择）
   - 删除项目功能（清理所有缓存和拷贝文件）

5. 国际化基础：
   - 所有 UI 文字使用 String(localized:) 
   - 创建 zh-Hans 和 en 两套 Localizable 文件
   - AI prompt 中的语言偏好跟随 App 语言设置
```

### 验收标准
- [x] 1000 张照片流畅浏览无卡顿
- [x] App 崩溃后重启能恢复工作状态
- [x] Dark mode 显示正常
- [x] 多项目管理可用

---

## 里程碑总览

| Phase | 内容 | 预估时间 | 核心依赖 |
|-------|------|---------|---------|
| 0 | 项目脚手架 | 30min | 无 |
| 1 | 文件夹导入 + 缩略图浏览 | 2-3h | Phase 0 |
| 2 | 智能分组 | 1-2h | Phase 1 |
| 3 | 本地 Core ML 初筛 | 1-2h | Phase 1 |
| 4 | 多模型云端 AI 评分 | 3-4h | Phase 2, 3 |
| 5 | 人工挑选交互 | 1-2h | Phase 4 |
| 6 | 导出模块 | 3-4h | Phase 5 |
| 7 | 视频归档 | 1-2h | Phase 5 |
| 8 | SD 卡 + iPhone 导入 | 2-3h | Phase 1 |
| 9 | 打磨优化 | 2-3h | All |

**总预估**：约 18-26 小时（codex 辅助开发时间）

**建议执行顺序**：0 → 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 → 9

Phase 8（SD卡+iPhone）和 Phase 6-7（导出+归档）可以并行开发，因为它们依赖的是不同模块。

---

## 给 codex 的全局指令

在开始每个 Phase 之前，建议在 codex 中设置以下全局上下文：

```
你正在开发一个 macOS 原生应用 Luma（拾光）。
请始终参考项目根目录下的 PRODUCT_SPEC.md 作为权威设计文档。

技术约束：
- 语言：Swift, SwiftUI
- 最低系统：macOS 14 Sonoma
- 优先使用 Apple 原生框架，避免第三方依赖
- 所有异步操作使用 Swift Concurrency (async/await)
- UI 状态管理使用 @Observable (Observation 框架，macOS 14+)
- 避免使用 Combine，优先 AsyncStream
- 文件操作使用 FileManager，网络请求使用 URLSession
- 敏感信息（API Key）使用 Keychain 存储

代码风格：
- 每个文件开头写清文件作用的注释
- 协议定义和实现分离到不同文件
- 错误处理使用 Swift typed throws 或 Result
- 日志使用 os.Logger
```

---

## 常见问题预防

### Q: CGImageSource 不支持某种 RAW 格式怎么办？
A: macOS 14 原生支持主流 RAW 格式。如遇到不支持的（极少数），fallback 到显示文件名占位图 + 标记为 "unsupported format"。

### Q: Vision API 返回的 JSON 格式不稳定怎么办？
A: ResponseNormalizer 中做宽松解析：尝试完整解析 → 失败则尝试提取部分字段 → 全部失败则标记 .scoreFailed，UI 上显示"评分失败，点击重试"。

### Q: 照片库导入大量照片时内存溢出？
A: 使用 autoreleasepool 包裹每张照片的处理逻辑，缩略图缓存使用 NSCache（自动在内存压力时释放），LazyVGrid 天然只渲染可见区域。

### Q: Lightroom 不读取 XMP？
A: 确认 Lightroom 设置中开启了"自动从 XMP 读取元数据"（Catalog Settings → Metadata → Automatically read changes into XMP）。在 App 文档中提示用户检查此设置。
