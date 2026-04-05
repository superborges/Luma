# Luma 执行基线

本文件不替代 [PRODUCT_SPEC.md](/Users/qinkan/Documents/codex/Luma/PRODUCT_SPEC.md) 和 [CODEX_PLAN.md](/Users/qinkan/Documents/codex/Luma/CODEX_PLAN.md)。

用途只有两个：
- 记录当前代码的真实完成度
- 记录与原始计划不一致、后续必须持续记住的偏差

## 1. 权威来源

- 产品目标和能力范围：`PRODUCT_SPEC.md`
- 分阶段开发计划：`CODEX_PLAN.md`

后续开发原则：
- 产品方向以 `PRODUCT_SPEC.md` 为准
- 实际执行顺序以当前文件记录的“真实进度”与“偏差清单”为准
- 不再默认 `CODEX_PLAN.md` 中 `Phase 8/9` 的验收项已经成立

## 2. 当前真实进度

### 已基本完成

- `Phase 0` 项目脚手架
- `Phase 1` 文件夹导入 + 缩略图浏览
- `Phase 2` 时间分组 + 基础 GPS 分组
- `Phase 3` 本地质量初筛
- `Phase 4` 多模型云端评分主链路
- `Phase 5` 人工挑片交互
- `Phase 6` 导出模块
- `Phase 7` 归档视频

### 部分完成

- `Phase 8` SD 卡 + iPhone 导入

### 未完成

- `Phase 9` 打磨与优化
- `PhotosLibraryAdapter`（V2）

## 3. 必须记住的偏差

这些偏差都很关键，后续实现时不能忽略：

1. 导入还不是 spec 里的“三阶段渐进式导入”
- 当前只有 `scanning / copying / finalizing`
- 还没有“缩略图先可见、JPEG 后台拷贝、RAW 低优先级拷贝”的完整分层
- 还没有导入任务持久化和断点续传

2. SD 卡和 iPhone 还不是“自动检测并弹窗导入”
- 现在是用户手动点击工具栏或菜单触发
- adapter 里虽然有 `connectionState`，但没有形成持续监控链路

3. 设备拔出暂停、重新连接恢复还没做
- 这属于 `Phase 8` 原始要求的一部分
- 不能把当前状态视为“设备导入体验已完成”

4. 分组没有完成视觉相似度子分组
- 还没有 `VNGenerateImageFeaturePrintRequest`
- 当前 `SubGroup` 不是“连拍候选集”级别的实现

5. 分组命名没有完成地名反查
- 还没有 `CLGeocoder` 反向地理编码
- 目前主要是日期 + 时间段 + 时间窗命名

6. AI 模块有主链路，但未达到 spec 完整度
- 已有 provider、test connection、批量评分、费用记录
- 还没有模型校准流程
- 预算超限也不是中途暂停再恢复的完整行为

7. Photos Library 导入仍未实现
- 当前是明确占位，不要误判为已完成

8. 多项目管理还未完成
- 目前更接近“最近项目自动恢复”
- 还不是完整的项目列表、切换、删除、清理

9. 国际化、首次启动引导、性能验收、打包权限仍未完成
- 没有 `String(localized:)` 全量收口
- 没有完整的 `zh-Hans / en` 资源
- 没有完成 1000 张级别性能验收
- 没有完成 entitlements / sandbox / 打包校验

10. 实机联调仍未完成
- SD 卡真机导入
- iPhone USB 真机导入
- Photos App 真导出
- Ollama / 云端评分真实返回校验

## 4. 后续执行顺序

后续以这个顺序推进：

1. `P0 导入韧性`
- 自动检测导入源
- 导入会话持久化
- 断点续传
- 设备拔出暂停 / 重连恢复

2. `P1 实机联调`
- SD 卡
- iPhone USB
- Photos App
- Ollama

3. `P2 产品化补强`
- 多项目管理
- 性能优化
- 错误恢复

4. `P3 打包与发布准备`
- `Info.plist`
- entitlements
- sandbox / 权限

## 5. 使用方式

每次继续开发前，先同时对照：
- [PRODUCT_SPEC.md](/Users/qinkan/Documents/codex/Luma/PRODUCT_SPEC.md)
- [CODEX_PLAN.md](/Users/qinkan/Documents/codex/Luma/CODEX_PLAN.md)
- [EXECUTION_BASELINE.md](/Users/qinkan/Documents/codex/Luma/EXECUTION_BASELINE.md)

其中：
- 前两份定义“应该做什么”
- 本文件定义“现在真实做到哪里、哪些还没做到”

真实目录回归可直接运行：
- `zsh scripts/run_real_folder_e2e.sh /Users/qinkan/Documents/100LEICA`

## 6. 2026-04-04 当日记录

说明：
- 本节覆盖今天涉及的旧状态；如果与前文某些历史描述冲突，以本节为准
- 重点记录今天的实现、当前剩余优化项，以及仍需和 `PRODUCT_SPEC.md` / `CODEX_PLAN.md` 对齐的缺口

### 今日已完成

- `P0 导入韧性` 基础版已落地：
  - `ImportSourceMonitor` 已接入，能轮询检测 SD 卡和 iPhone，并弹导入提示
  - `ImportSession` / `ImportSessionStore` 已落地，未完成导入可恢复
  - 导入已改成 `scanning -> preparingThumbnails -> copyingPreviews -> copyingOriginals -> finalizing`
  - 设备断开时会暂停并保留恢复点，重新连接后可继续

- `P1` 本机和真实目录验证已补强：
  - `OpenAI-compatible` 已与本地 `Ollama` 做最小兼容联调
  - 新增真实目录 E2E：
    - `导入 -> shrinkKeep 导出`
    - `导入 -> archive video`
  - 真实目录回归脚本已落地：`scripts/run_real_folder_e2e.sh`

- `P2` 基础产品化能力已补：
  - 多项目基础管理已完成：项目列表、打开、切换、删除、关联恢复会话清理
  - 性能优化已落地第一轮：
    - 缩略图缓存并发去重
    - 缩略图邻域预热 / 裁剪
    - 单张显示级图片缓存 / 预热 / 裁剪
    - 选择驱动的主动缓存准备
  - 性能诊断面板已接入，可看缓存命中、生成、回收和进行中任务

- 测试体系已明显补强：
  - 已覆盖分组、响应归一化、媒体编码兼容、文件扫描、导入会话、导出、归档、`ProjectStore`、`ImportManager`、`BatchScheduler`、`ImportSourceMonitor`
  - 真实目录集成测试已补上
  - 当前本地 `swift build` / `swift test` 路径可持续使用

- 今天的 UI / 交互改动：
  - 修复性能诊断弹窗无法关闭
  - 修复中间网格图片重叠
  - 收窄右侧详情列
  - 单页预览改成适屏显示，支持双击放大 / 还原
  - 中间网格选中态改强，AI 推荐与技术问题默认不再直接用大面积蓝框 / 红框
  - 优化网格点击选中卡顿：
    - 选中时不再立即同步做重缓存预热
    - 单击 / 双击手势已拆开，单击可立即切换选中态
  - 快捷键已恢复可用：
    - `P / X / U / 1-5 / Space / Tab / ← → / Cmd+A`
    - 当前做法包含 App 激活和键盘桥接
  - 左侧导航栏已从系统 `List` 改成自绘 `ScrollView + VStack`
    - 去掉系统式圆角选中样式
    - 改成整列平面导航
    - 选中态改成整行满铺底色 + 左侧强调条

- 运行时诊断已落地：
  - 新增结构化 trace，写入：
    - `/Users/qinkan/Library/Application Support/Luma/Diagnostics/runtime-latest.jsonl`
  - 已记录：
    - 项目启动 / 打开
    - 分组切换 / 图片选中 / 单双页切换
    - 挑片 / 评分 / 导入 / 导出 / AI 评分
    - 单页图片加载耗时
    - 用户可见错误

### 待优化

- 缩略图缓存仍是 `@MainActor`；大项目下还应继续把磁盘读取和解码从主线程路径里剥离
- 当前 trace 只写 `runtime-latest.jsonl`，还没有日志轮转、归档和会话保留策略
- App 激活与快捷键方案虽已可用，但还需要验证：
  - 多窗口
  - 弹窗关闭后
  - 长时间运行后
  - 正式打包态
- 左侧导航栏还需要继续打磨：
  - 组与组之间的节奏
  - 总览和分组标题层级
  - 选中底色与分隔线的精细度
- 中间悬浮工具栏还可以继续收：
  - 透明度
  - 密度
  - 和主内容的融合度
- 还没有做 300-1000 张级别的正式性能验收

### 待对齐项

这些仍然是和原始 spec / plan 相比最关键的缺口：

- 视觉相似度子分组仍未完成
  - 还没有 `VNGenerateImageFeaturePrintRequest`

- 地名反查命名仍未完成
  - 还没有 `CLGeocoder`

- `PhotosLibraryAdapter` 仍未实现
  - 保持 V2，不要误判成已完成

- AI 评分仍未完成完整产品语义
  - 模型校准流程未做
  - 预算超限后的中断 / 恢复未做

- 实机联调仍未收口
  - SD 卡真机导入
  - iPhone USB 真机导入
  - Photos App 真导出
  - Ollama 边界兼容

- 发布前能力仍未完成
  - entitlements / sandbox / 权限
  - `Info.plist`
  - 国际化
  - 首次启动引导
  - 正式打包验证
