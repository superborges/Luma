## 背景

当前要实现的是归档模块（F4 + F5），目标是让用户在导出选中照片后，对未选中的照片有三种处理方式：生成 Ken Burns 回忆视频、缩小保留（降低分辨率并删除 RAW）、或直接丢弃。同时维护 `archive_manifest.json` 记录每张照片的归档方式，便于未来检索。

## 本次只做

- `ArchiveVideoGenerator`：用 `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor` 生成 H.265 1080p Ken Burns 回忆视频
  - 每张照片停留 1.5-2 秒
  - Ken Burns 效果：随机起始/终止 rect（缩放 1.0-1.15×，平移 0-5%），线性插值
  - 淡入淡出转场 0.3 秒（alpha blend）
  - 文字叠加：组名 + 日期 + 地点（底部半透明条）
  - 按 PhotoGroup 分组生成（每组一个视频）
- `ShrinkKeepArchiver`：缩小保留
  - 长边缩至 2048px（CGContext draw）
  - JPEG 质量 80%
  - 保留完整 EXIF（CGImageDestinationAddImage 附带原始 properties）
  - 成功后删除 RAW 文件
- `ArchiveManifest`：归档清单
  - `archive_manifest.json` 记录每张照片的原始文件名、拍摄时间、AI 评分、归档方式、输出路径
  - 每次归档操作完成后追加写入
- 导出面板 UI：归档选项 Section（三选一：回忆视频 / 缩小保留 / 丢弃）
- 归档进度 UI：进度条显示当前处理的组/照片
- 单测：ShrinkKeepArchiver（尺寸/EXIF/质量验证）、ArchiveManifest（序列化/反序列化）

## 本次明确不做

- 视频加背景音乐
- 视频可配置帧率/分辨率/编码格式（固定 H.265 1080p 30fps）
- Ken Burns 方向用户可自定义（固定随机）
- 归档视频预览播放器（用系统默认播放器）
- 修改导入或评分模块

## 用户主路径

1. 用户进入：导出完成后（或手动触发）→ 系统提示处理未选中照片
2. 用户操作：选择归档方式（回忆视频 / 缩小保留 / 丢弃）→ 二次确认
3. 系统反馈：后台按组处理 → 进度条 → 完成后显示释放的磁盘空间
4. 用户完成：回忆视频在 `archives/` 目录可查看；`archive_manifest.json` 可检索

## 页面与组件

- 需要新增的页面：归档确认弹窗（二次确认 + 方式选择）
- 需要新增的组件：`ArchiveVideoGenerator`、`ShrinkKeepArchiver`、`ArchiveManifest`、归档进度条
- 可以复用的组件：`EXIFParser`（EXIF 读写）、`ThumbnailCache`（读取预览图）、进度条样式参考 `ScoringProgressBar`

## 交互要求

- 默认状态：导出完成后出现"处理未选中照片"入口（非强制）
- 主按钮行为："开始归档"→ 后台执行，显示进度条
- 次按钮行为："跳过"→ 未选中照片保留不动
- 返回行为：归档进行中可取消，已处理的保留
- 空状态：无未选中照片 → 归档入口不显示
- 错误状态：视频编码失败 → 跳过该组继续；缩小保留写入失败 → 保留原文件不删 RAW

## UI 要求

- 风格方向：与现有导出面板一致（深色主题）
- 必须保留的现有风格：ExportPanelView 结构不变
- 可以自由发挥的范围：归档 Section 布局（三选一 Picker + 磁盘空间预估 + 进度条）
- 不要为了"好看"增加复杂装饰

## 技术约束

- 技术栈：`AVFoundation`（`AVAssetWriter` / `AVAssetWriterInputPixelBufferAdaptor`）、`Core Graphics`（图片缩放 + 文字绘制）、`CVPixelBuffer`
- 状态管理方式：归档进度通过 `ProjectStore` 的 `@Published` 属性驱动 UI
- 数据先用 mock 还是真接口：`ArchiveVideoGenerator` 可 mock AVAssetWriter 做单元测试；`ShrinkKeepArchiver` 用真实文件系统
- 不要顺手重构无关模块
- 不要擅自引入新的大型依赖
- 视频输出参数固定：H.265 (HEVC), 1920x1080, 30fps, 码率约 CRF 28
- 缩小保留使用 `CGImageDestinationCreateWithURL` + `UTType.jpeg`
- 归档目录结构：`<projectDir>/archives/<groupName>_archive.mp4`
- 归档是低优先级任务：QoS `.utility`
- 删除 RAW 前必须确认缩小保留成功（原子性保障）

## 输出顺序

1. 先搭 `ShrinkKeepArchiver`（简单，纯图片处理）
2. 再搭 `ArchiveManifest`（数据模型 + 序列化）
3. 再搭 `ArchiveVideoGenerator`（核心复杂度：AVAssetWriter + Ken Burns + 文字叠加）
4. 再搭归档 UI（导出面板 Section + 进度条 + 确认弹窗）
5. 最后补集成到 ProjectStore + 单测

## 验收标准

- [ ] 归档可选"回忆视频"：生成 H.265 1080p .mp4 文件
- [ ] Ken Burns 效果可见（缓慢平移 + 缩放）
- [ ] 淡入淡出转场 0.3 秒
- [ ] 文字叠加显示组名 + 日期 + 地点
- [ ] 归档可选"缩小保留"：输出 ≤ 2048px 长边 JPEG
- [ ] 缩小保留后 EXIF 完整（拍摄日期/GPS/相机型号等）
- [ ] 缩小保留成功后 RAW 文件已删除
- [ ] 归档可选"丢弃"：直接删除未选中照片
- [ ] 删除前有二次确认弹窗
- [ ] `archive_manifest.json` 正确记录每张照片的归档方式和输出路径
- [ ] 进度条显示当前处理进度
- [ ] 编码/写入失败时跳过该项并保留原文件
- [ ] 单测覆盖 ShrinkKeepArchiver / ArchiveManifest
- [ ] 没有大面积改坏其他模块
