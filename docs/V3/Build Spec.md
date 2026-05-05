# Build Spec — Luma V3

## 1. 版本信息

- 产品：Luma（拾光）
- 版本：V3 — SD 卡导入、Lightroom 导出、归档模块、AI 增强
- 日期：2026-05

## 2. 本次版本目标

- 本次版本要解决的核心问题：V2 已完成云端 AI 评分与修图建议，但导入仅支持文件夹和照片库，导出仅支持本地文件夹，未选中照片没有归档方案，AI 评分跨模型不一致，分组名称缺乏语义。
- 本次版本最重要的用户任务：让用户能**直接从 SD 卡导入**相机照片；选片完成后**一键导出到 Lightroom**（含 XMP sidecar + 修图建议滑块预设）；未选中照片能**自动生成回忆视频**或**缩小保留**；AI 评分**跨模型归一化**确保分数可比；分组名称**由 AI 生成**更具描述性。
- 本次版本完成后，用户能做到什么：
  - 插入 SD 卡 → 自动检测 → 一键导入全部 RAW+JPEG
  - 选片完成 → 导出到 Lightroom Classic 自动导入文件夹，附带评分/标签/修图建议的 XMP sidecar
  - 未选中照片 → 生成 Ken Burns 回忆视频（H.265 1080p）或缩小保留（2048px JPEG）
  - 首次添加 AI 模型时通过 20 张参考照校准，后续切换模型评分一致
  - 分组列表显示 AI 生成的语义名称（"清水寺·日落"而非"4月3日·下午"）

## 3. 功能范围

### 本次包含

- **F1 SD 卡导入（DiskArbitration）**：`DiskArbitration` 框架检测可移除媒体，`SDCardAdapter` 实现 `ImportSourceAdapter` 协议，DCIM 扫描，RAW/JPEG 配对，设备拔出恢复
- **F2 Lightroom 导出 + XMP sidecar**：`LightroomExporter` 实现 `ExportDestinationAdapter`，生成 XMP sidecar 文件（Rating/Label/Keywords/Description），导出面板新增 Lightroom 选项
- **F3 修图建议写入 XMP 滑块值**：将 V2 的 `EditSuggestions` 写入 XMP `crs:Exposure2012` / `crs:CropTop` 等 Camera Raw 字段，Lightroom 打开即为预设值
- **F4 未选中照片 → Ken Burns 回忆视频**：`AVAssetWriter` 生成 H.265 1080p 视频，每张 1.5-2 秒 + Ken Burns 效果 + 文字标注 + 淡入淡出转场
- **F5 缩小保留方案**：未选中照片降至长边 2048px / JPEG 80% / 保留完整 EXIF，删除 RAW 原文件
- **F6 评分校准（20 张参考照归一化）**：首次配置模型时用内置参考照做 μ/σ 线性映射，确保跨模型评分分布一致
- **F7 AI 组名生成**：用云端 Vision API 分析组内代表照片，生成描述性名称（"清水寺·日落"），替代纯时间+地点规则

### 本次不包含

- 流式响应（SSE）— 继续按整批 await
- 自定义 Prompt 模板 — 默认两套 Prompt 写死
- 导出后通知 / 自动化（Shortcuts）
- 本地大模型特殊优化（Ollama 仍走 `.openAICompatible`）
- 视频格式导入（MOV 仅作为 Live Photo 附属资源）

## 4. 用户主路径

1. 用户进入：插入 SD 卡 → App 自动检测弹出导入提示；或打开已有 Session
2. 用户看到：导入完成进入选片工作区；分组列表显示 AI 生成的语义名称
3. 用户执行：
   - SD 卡导入：自动扫描 DCIM，配对 RAW+JPEG → 渐进式导入 → 进入选片
   - 选片完成后导出：选择 Lightroom 目标 → 配置 XMP 选项（含修图建议写入）→ 开始导出
   - 归档：导出完成后系统提示处理未选中照片 → 选择「生成回忆视频」或「缩小保留」或「丢弃」
   - 校准：设置 → AI 模型 Tab → 添加新模型后弹出「校准评分」引导 → 20 张参考照自动评分 → 保存校准参数
4. 系统反馈：SD 卡检测状态变化实时反映（已连接/拔出/导入中）；导出进度条；视频生成进度条；校准完成后显示 μ/σ 统计
5. 用户完成：导出到 Lightroom 完成 → 在 Lightroom 中看到星级/标签/修图预设全部就绪；归档完成 → 磁盘空间释放

## 5. 页面清单

- Session 列表：不变（继承 V2）
- **选片工作区**：分组列表显示 AI 生成名称（F7）；导出面板新增 Lightroom 选项（F2+F3）
- **SD 卡导入提示弹窗**：自动检测到 SD 卡时弹出（F1）
- **导出面板**：新增 Lightroom 目标 + XMP 选项（F2+F3）；归档选项增加「回忆视频」和「缩小保留」（F4+F5）
- **归档进度页**：视频生成 / 缩小保留进度（F4+F5）
- **设置页 - AI 模型 Tab**：新增「校准评分」按钮与校准结果展示（F6）

## 6. 每页核心任务

### SD 卡导入提示（F1）

- 页面目标：零操作完成 SD 卡照片导入
- 主操作：确认导入 → 自动扫描 DCIM + 配对 + 渐进式拷贝
- 次操作：查看扫描到的文件数 / RAW 格式分布；设备拔出时暂停提示

### 导出面板（F2 + F3）

- 页面目标：一键导出到 Lightroom，附带完整元数据
- 主操作：选 Lightroom 目标 → 选 XMP 选项 → 开始导出
- 次操作：配置自动导入文件夹路径；勾选是否写入修图建议滑块值

### 归档（F4 + F5）

- 页面目标：处理未选中照片，释放磁盘空间
- 主操作：选择归档方式（回忆视频 / 缩小保留 / 丢弃）→ 确认执行
- 次操作：查看视频生成进度；预览生成的视频

### 设置页 - 校准（F6）

- 页面目标：确保跨模型评分一致
- 主操作：点击「校准评分」→ 等待 20 张参考照自动评分 → 保存
- 次操作：查看当前模型的 μ/σ 统计；重新校准

## 7. 关键交互规则

- 默认进入时展示什么：插入 SD 卡时自动弹出导入提示（可在设置中关闭）；分组名称优先显示 AI 生成名称
- 主按钮点击后发生什么：SD 卡导入确认后进入全自动流程；Lightroom 导出开始后后台执行不阻塞 UI；归档确认后按选择方式逐组处理
- 返回逻辑是什么：所有后台任务（导入/导出/归档/校准）支持取消；SD 卡拔出时优雅暂停
- 什么时候自动保存：导入/导出进度持久化（断点续传）；校准参数写入 ModelConfig
- 什么时候要二次确认：归档删除 RAW 前；Lightroom 导出覆盖已有 XMP 前
- 什么时候给提示：SD 卡检测状态变化；校准完成后 μ/σ 与推荐偏移量；视频生成完成

## 8. 状态设计

- 默认状态：无 SD 卡时导入菜单显示灰色；分组名称显示 AI 名称或 fallback 到时间+地点
- 空状态：SD 卡无 DCIM 目录 → 提示"未检测到照片"；校准未完成 → 显示"未校准，使用原始评分"
- 加载状态：SD 卡扫描中显示进度；视频生成显示每帧进度；校准显示 N/20 完成
- 成功状态：导入完成进入选片；导出完成显示 Lightroom 就绪提示；视频生成完成可预览
- 失败状态：SD 卡读取失败（权限/损坏）→ 具体错误 + 重试；XMP 写入失败 → 跳过并标记；视频编码失败 → 日志 + 重试
- 异常状态：SD 卡拔出 → 暂停 + "请重新插入" 提示；校准时 API 调用失败 → 跳过该参考照但显示警告

## 9. 数据与对象

- 核心对象：
  - `SDCardAdapter`（新）— 实现 `ImportSourceAdapter`，`DiskArbitration` 回调驱动
  - `LightroomExporter`（新）— 实现 `ExportDestinationAdapter`，XMP sidecar 生成
  - `XMPSidecarWriter`（新）— 纯函数式 XMP XML 生成器，处理 Rating/Label/Keywords/crs 滑块值/CropTop 等
  - `ArchiveVideoGenerator`（新）— `AVAssetWriter` + Ken Burns 效果 + 文字叠加
  - `ShrinkKeepArchiver`（新）— 缩小保留 + EXIF 保留 + RAW 删除
  - `ScoreCalibrator`（新）— 参考照评分 → μ/σ → 线性映射参数写入 `ModelConfig.calibrationOffset`
  - `AIGroupNamer`（新）— Vision API 分析组内代表照 → 返回描述性名称
- 对象间关系：
  - `SDCardAdapter` → `ImportManager`（复用现有导入管线）
  - `LightroomExporter` → `XMPSidecarWriter`（导出时生成 XMP）
  - `XMPSidecarWriter` ← `MediaAsset.aiScore` + `MediaAsset.editSuggestions`（数据来源）
  - `ArchiveVideoGenerator` ← `PhotoGroup` + `MediaAsset`（按组生成视频）
  - `ScoreCalibrator` → `ModelConfig.calibrationOffset`（写入校准参数）
  - `AIGroupNamer` → `PhotoGroup.name`（覆盖默认名称）
- 用户会修改哪些内容：Lightroom 自动导入路径（设置）、归档方式选择、校准触发、AI 组名开关
- 哪些状态需要持久化：
  - `ModelConfig.calibrationOffset` → UserDefaults
  - `PhotoGroup.name`（AI 生成）→ manifest.json
  - `archive_manifest.json` → 每次归档时写入
  - SD 卡导入进度 → 断点续传 JSON
  - Lightroom 默认路径 → UserDefaults

## 10. 非目标范围

- 这版明确不解决什么：SSE 流式响应、自定义 Prompt、导出后自动化（Shortcuts）
- 哪些想法先不做：SD 卡热拔插后自动恢复（仅做提示，不自动重启）；XMP 写入 HSL 局部调整（crs 不支持完整表达，只写全局滑块）；视频加背景音乐

## 11. 验收标准

- [ ] 插入 SD 卡后 App 能自动检测并弹出导入提示
- [ ] SD 卡导入支持 DCIM 扫描、RAW/JPEG 配对、断点续传
- [ ] 设备拔出时优雅暂停并提示重新插入
- [ ] 导出面板可选 Lightroom 目标，生成 XMP sidecar
- [ ] XMP 包含 Rating（评分映射）、Label（决策映射）、Keywords、Description
- [ ] 勾选"写入修图建议"后 XMP 包含 crs:Exposure2012 等滑块值和 CropTop/Bottom/Left/Right
- [ ] Lightroom Classic 打开后星级/标签/修图预设全部就绪
- [ ] 归档可选"回忆视频"：H.265 1080p，Ken Burns 效果 + 文字标注 + 淡入淡出
- [ ] 归档可选"缩小保留"：长边 2048px / JPEG 80% / EXIF 完整 / RAW 已删
- [ ] 归档生成 `archive_manifest.json` 记录每张照片归档方式
- [ ] 设置中可触发"校准评分"，用 20 张参考照计算 μ/σ 并保存
- [ ] 校准后该模型评分经线性映射归一化
- [ ] 分组列表默认显示 AI 生成的语义名称
- [ ] AI 组名失败时 fallback 到时间+地点规则
- [ ] 所有新功能有对应单测或集成测试
- [ ] 不引入新的重型外部依赖（XMP 用字符串模板生成，不引入第三方 XML 库）
