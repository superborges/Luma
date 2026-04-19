# Luma Handoff

## Current Focus

当前主线不是继续扩功能，而是把核心链路做稳，并把后续排查成本压低：

- 稳定 `导入 -> 一级分组 -> 二级 BurstSet -> 评分 -> 挑片 -> 导出 / 归档`
- 把主 APP 的交互卡顿、主线程热点、恢复性问题做成可定位、可复盘
- `winner / best` 策略在另一个 thread 讨论，这里不要重复发散

后续开发前仍需同时对照：

- `PRODUCT_SPEC.md`
- `CODEX_PLAN.md`
- `EXECUTION_BASELINE.md`
- `MILESTONE_v0.1.md`

## v0.1 Milestone

### 定位

`v0.1` 定位为：

- 可内测
- 可连续使用
- 不可外发

更具体地说，它不是“功能全了”的版本，而是第一个能让真实用户按完整主链路跑通、且排查成本可控的里程碑。

### 目标

`v0.1` 只要求把下面这条链路做到稳定可验收：

- 导入
- 一级分组
- 二级 BurstSet
- 本地 / 云端评分
- 手动挑片
- 导出 / 归档
- trace / diagnostics 可定位

### In Scope

- 文件夹导入稳定可用
- SD 卡 / iPhone 导入可用，但仍按“实验性”对待
- 一级 `SceneGroup` 与二级 `BurstSet` 语义稳定
- Burst UI 可视化和明细浏览可用
- 本地评分、云端评分主链路可用
- 挑片快捷键和单 / 双页浏览可用
- Folder / Lightroom / Photos App 导出入口可用
- `shrinkKeep` / `archive video` 可用
- 多项目基础管理可用
- trace、diagnostics、trace summary 可用于定位问题

### Out Of Scope

- AI 智能命名
- 把地名命名做到发布级质量
- `PhotosLibraryAdapter`
- 国际化和首启引导
- 真正面向发布的 sandbox / entitlements / 商业化打包
- “全库重复图去重”这类新问题域

### Exit Criteria

达到下面这些，才算 `v0.1`：

1. 真实目录 `100LEICA` 能稳定完成：
  - 导入
  - 分组
  - 挑片
  - 导出 / 归档
2. BurstSet 在已标注样本上不出现明显系统性误并 / 漏并。
3. 主交互卡顿可被 trace 定位，且 `trace-summary-latest.md` 能直接看出热点。
4. `swift build` 稳定通过；测试至少保持“编译通过”，环境允许时跑完整回归。
5. 已知问题被压到“可带着问题进入内测”，而不是“主链路会断”。

### Release Gate

`v0.1` 发布前，至少要人工再过一轮：

- 导入 1 次
- 分组校验 1 次
- Burst 浏览 / 明细 strip 校验 1 次
- 挑片快捷键校验 1 次
- 导出 1 次
- trace summary 校验 1 次

### 当前判断

按今天收敛后的状态，我认为项目已经接近 `v0.1`，但还差最后一段：

- 主 APP 真实交互性能继续收口
- 再做一轮真实样本回归
- 把若干“实验性可用”项压到“内测可用”
- 最新 trace 已确认：
  - `group_selected` 已基本收住
  - 当前剩余主热点是 `single_image_loaded`
  - 如果走“网格先选中，再进单页”路径，`single_image_loaded` 已基本消除
- 导入主链路的最新瓶颈已定位到 `grouping`
  - 其中大头不是 `BurstSet`，而是地点反查命名

## Current State

### 已完成

- macOS SwiftUI 主应用骨架已可用：
  - 三栏界面
  - 设置页 / 命令菜单
  - 项目状态持久化
  - 导入监控与恢复基础版
- 导入主链路已可用：
  - 文件夹导入
  - SD 卡导入
  - iPhone USB 导入
  - 导入会话持久化
  - 暂停 / 恢复
- 一级分组 `SceneGroup` 已重做成“时序活动分段”而不是粗糙聚类：
  - 先按时间排序
  - `30m` 仅作为候选切点，不再硬切
  - `120m` 作为硬切
  - 连续性判定同时看：
    - GPS 邻近
    - DBSCAN 地点簇
    - Vision 场景连续性
  - 同地点 later revisit 仍会保留成新的一级组
- 二级分组 `BurstSet` 已重做成严格顺序分段：
  - 目标语义：短时间、同机位、同拍摄意图、用户大概率只留 1 张
  - 当前规则：
    - `frameGapThreshold = 12s`
    - `burstSpanThreshold = 20s`
    - 横竖必须一致
    - 焦段容差 `15%`
    - `anchorDistanceThreshold = 0.28`
    - `completeDistanceThreshold = 0.35`
  - 对单张起步 burst，允许边界距离放宽到 `complete` 阈值
  - 多图 burst 仍保留严格 anchor 约束，避免链式误并
- Burst UI 已补到可肉眼验证：
  - 一级组内不再纯平铺单图，而是显示 Burst 卡片
  - 多图 burst 显示堆叠缩略图、`xN`、`Best`
  - 标签已改成中文：`连拍组 N`
  - 单张 burst 不显示该标签
  - 点击卡片会展开行内缩略图 strip
  - strip 中可直接切图 / 进单页
  - 右侧详情面板显示当前所属 burst 上下文
- 左侧分组栏已从系统 `List` 改成自绘平面导航：
  - 避免系统 sidebar 的圆角和选中态干扰
  - 三栏容器已换成更可控的 `HSplitView`
- 缓存与性能基础设施已补强：
  - `ThumbnailCache` 的磁盘读取和像素解码已移出主线程关键路径
  - `DisplayImageCache` 和缩略图预热已接入
  - 性能诊断面板可看缓存命中、并发复用、预热、回收等指标
  - `ProjectStore` 已缓存：
    - `visibleAssets`
    - `visibleBurstGroups`
    - `selectedBurstContext`
  - `PhotoGrid` 已去掉 burst 序号的重复全表查找，减少分组切换和浏览时的重复计算
  - Burst 卡片和明细 strip 的预热已改成更局部的策略，不再为每个 cell 反复扫整组可见资产
  - 全图网格 `ThumbnailCell` 已去掉逐 cell 邻域预热，避免滚动时大量重复触发预热扫描
  - 本地评分路径已去掉每张图的 `localRejectedCount` 全量重算
  - `refreshGroupRecommendations()` 已改成 lookup 查表，不再对全量 `assets` 反复 filter
  - `computeSummary()` 已改单遍统计，降低 `derived_state_rebuilt` 的基础成本
  - `RuntimeTrace` 已改成会话内复用文件句柄，避免每条 trace 反复开关文件
  - 单页查看已改成“thumbnail 先出图，display image 异步替换”
  - `DisplayImageCache` 单页显示图上限已收紧到最多 `2400px`
  - 单页缓存预热延迟已从 `60ms` 降到 `10ms`
  - 网格选中后会延迟预热当前照片的 display image，降低“先选中再进单页”的冷启动成本
- trace / log 已从“能写”提升到“能定位”：
  - `runtime-latest.jsonl`
  - 每会话独立归档 trace
  - 会话轮转
  - 每条 trace 带 `sequence`
  - `session_started` 会记录 `latest/session` trace 文件路径
  - 导入链路补了结构化耗时埋点：
    - `import_run_started`
    - `import_source_enumerated`
    - `initial_manifest_built`
    - `preview_copy_completed`
    - `original_copy_completed`
    - `import_grouping_completed`
    - `import_run_completed`
  - 项目 / 交互侧也补了关键 trace：
    - `bootstrap_completed`
    - `last_project_loaded`
    - `project_opened`
    - `group_selected`
    - `single_image_first_paint`
    - `derived_state_rebuilt`
    - `single_image_loaded`
    - 各类用户可见错误
- 诊断工具已补齐两类 CLI：
  - `BurstReviewCLI`
    - 读取真实目录
    - 输出疑似误并 / 漏并 review pack
  - `TraceSummaryCLI`
    - 默认读取 `runtime-latest.jsonl`
    - 输出 markdown/json 摘要
    - 现在支持：
      - 高频事件
      - 慢 metric 聚合
      - `Hotspot Budgets`
      - `Slow Chains`
      - 最近错误
- 导入性能定位这一轮已收敛到可执行结论：
  - `buildInitialManifest` 已去掉重复分组
  - `GroupingEngine` 已补细分埋点：
    - `grouping_scene_split_completed`
    - `grouping_subgrouping_completed`
    - `grouping_location_naming_completed`
    - `grouping_background_location_naming_completed`
  - 已确认 `BurstSet` 不是当前导入瓶颈
  - 已确认 `CLGeocoder` 地点命名才是当前导入主链路的大头
  - 为此已把导入主链路改成：
    - 导入时先按时间名落盘
    - 导入完成后后台补地名
    - 后台补名只更新 `group.name`，不覆盖评分等其他组状态
  - 这版代码已编译通过并启动，但还没做导入后 trace 验证

### 真实样本校准结果

- 基于 `/Users/qinkan/Documents/100LEICA` 做了一轮人工回标
- 结论：
  - Burst 主算法方向是对的
  - 初始 `10s` 时间窗偏紧，已放宽到 `12s`
  - 视觉阈值当前不宜继续放宽
  - review pack 的候选筛选已收紧，避免无意义假阳性
- 当前对这批数据的最新 review pack 已收敛到：
  - `疑似误并 = 0`
  - `疑似漏并 = 0`

## Validation Status

- `swift build` 当前通过
- 最新一轮完整 `swift test`：
  - `60 passed / 2 skipped`
- 真实目录 `/Users/qinkan/Documents/100LEICA` E2E：
  - `RealFolderIntegrationTests` 2/2 通过
  - 导入 `56` 张
  - 一级组 `3` 个
  - `FolderExporter` 导出 `6` 张
  - `shrinkKeep` 归档 `50` 张
  - `archive video` 输出 `3` 个视频文件
- 真实目录 `/Users/qinkan/Documents/luma_test_1` E2E：
  - `RealFolderIntegrationTests` 2/2 通过
  - 导入 `92` 项
  - 一级组 `33` 个
  - `FolderExporter` 导出 `6` 项
  - `shrinkKeep` 归档 `84` 项
  - `archive video` 输出 `33` 个视频文件
- 本轮补了一个测试回归修复：
  - `RuntimeTrace` 改成 `JSONEncoder.withoutEscapingSlashes`
  - 修复 trace 路径断言失败
  - `RealFolderIntegrationTests` 不再假设真实目录只有 `JPG`
  - 现在按 `MediaFileScanner` 的实际可导入项，以及 `shrinkKeep` 的实际可渲染资产做断言
- 最近一轮单页链路 trace：
  - 走“先选中，再进单页”时：
    - `single_image_first_paint` p95 `0.05ms`
    - `single_image_loaded` avg `0.62ms` / p95 `1.10ms`
  - 说明该路径已不再是热点
  - 仍需关注的是“未预热直接进单页”的冷路径，但首屏已由 thumbnail 兜底
- 最近一轮已确认的导入 trace（`/Users/qinkan/Documents/luma_test_1`）：
  - 总导入：`11.91s`
  - 核心导入链路：`9.24s`
  - `import_grouping_completed`：`6.96s`
  - `grouping_scene_split_completed`：`0.66s`
  - `grouping_subgrouping_completed`：`1.53s`
  - `grouping_location_naming_completed`：`6.30s`
  - 结论：导入阶段最大头是地点命名，不是 `BurstSet`
- 当前 HEAD 还有一笔未验收改动：
  - `ImportManager` 导入时调用 `makeGroups(..., resolvesLocationNames: false)`
  - `ProjectStore` 在导入完成 / 打开项目后异步补地名，并回写 manifest
  - 下次接手后第一件事就是重新导入一次，看：
    - `import_grouping_completed`
    - `grouping_background_location_naming_completed`
    - `group_names_refreshed`

真实目录回归仍可用：

- `zsh scripts/run_real_folder_e2e.sh /Users/qinkan/Documents/100LEICA`

## Open Items

### 仍未完成

- 一级组智能命名尚未完成
  - 当前仍是规则命名
  - AI 命名只讨论过方案，尚未接入
- 地点命名链路仍未最终验收
  - `CLGeocoder` 已接入
  - 但刚改成“导入后后台补名”
  - 还缺一轮真实导入 trace 和 UI 验证
- `winner / best` 选择策略正在另一个 thread 讨论
  - 这里不要再改策略层语义，除非那个 thread 明确收敛
- `PhotosLibraryAdapter` 仍未实现
- 云端评分的预算中断 / 恢复还未完全产品化
- 发布准备未做完：
  - `Info.plist`
  - entitlements
  - sandbox / 权限
  - 国际化
  - 首启引导

### 当前风险

- BurstSet 已在 `100LEICA` 上收敛，但还缺更大、更多样的数据集回归
- 地点命名刚从导入主链路移到后台，收益方向明确，但当前 HEAD 还没做最终验证
- trace 已经够定位，但还没有专门的“自动回归基线”对比机制
- 主 APP 的性能优化仍应优先围绕真实交互来做，不要继续沉迷工具本身
- `v0.1` 目前更像“差最后一轮人工 UI 验收”，不是“主链路还没打通”

## Key Files

### 分组 / Burst

- `Sources/Luma/Services/Grouping/GroupingEngine.swift`

### 应用状态 / 交互

- `Sources/Luma/App/ProjectStore.swift`
- `Sources/Luma/Views/MainWindow/PhotoGrid.swift`
- `Sources/Luma/Views/MainWindow/DetailPanel.swift`
- `Sources/Luma/Views/MainWindow/GroupSidebar.swift`
- `Sources/Luma/Views/MainWindow/ContentView.swift`

### 导入

- `Sources/Luma/Services/Import/ImportManager.swift`
- `Sources/Luma/Services/Import/ImportSourceMonitor.swift`
- `Sources/Luma/Services/Import/ImportSessionStore.swift`
- `Sources/Luma/Services/Import/FolderAdapter.swift`
- `Sources/Luma/Services/Import/SDCardAdapter.swift`
- `Sources/Luma/Services/Import/iPhoneAdapter.swift`

### 诊断 / 工具

- `Sources/Luma/Utilities/RuntimeTrace.swift`
- `Sources/Luma/Views/Diagnostics/PerformanceDiagnosticsView.swift`
- `Sources/Luma/App/TraceSummaryCLI.swift`
- `Sources/Luma/App/BurstReviewCLI.swift`

## Useful Commands

- 构建：
  - `HOME=/tmp CLANG_MODULE_CACHE_PATH=/tmp/luma-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/luma-swiftpm-module-cache swift build`
- 测试：
  - `HOME=/tmp CLANG_MODULE_CACHE_PATH=/tmp/luma-clang-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/tmp/luma-swiftpm-module-cache swift test`
- 生成 burst review pack：
  - `.build/arm64-apple-macosx/debug/Luma --burst-review-root /Users/qinkan/Documents/100LEICA`
- 生成 trace summary：
  - `.build/arm64-apple-macosx/debug/Luma --trace-summary`
  - `.build/arm64-apple-macosx/debug/Luma --trace-summary --trace-summary-file /path/to/runtime.jsonl`
- 真实目录 E2E：
  - `zsh scripts/run_real_folder_e2e.sh /Users/qinkan/Documents/100LEICA`

## Diagnostics Paths

- 最新 trace：
  - `/Users/qinkan/Library/Application Support/Luma/Diagnostics/runtime-latest.jsonl`
- Trace 会话归档目录：
  - `/Users/qinkan/Library/Application Support/Luma/Diagnostics/RuntimeSessions`
- 最新 trace 摘要：
  - `Artifacts/trace-summary-latest.md`
  - `Artifacts/trace-summary-latest.json`
- 最新 burst review：
  - `Artifacts/burst-review-latest.md`
  - `Artifacts/burst-review-latest.json`

## Recommended Next Steps

1. ~~`v0.1` Release Gate~~：**已于 2026-04-11 关闭**（记录见 `MILESTONE_v0.1.md` § Release Gate 验收记录）。
2. 第一优先先验收最新“后台补地名”版本：
  - 手动导入 `/Users/qinkan/Documents/luma_test_1`
  - 看 `import_grouping_completed`
  - 看 `grouping_background_location_naming_completed`
  - 看组名是否会在导入后异步变成地点名
3. ~~再补一轮非 `100LEICA` 的真实数据回归~~：`luma_test_1` 已纳入 `run_real_folder_e2e` 常规跑法。
4. 若主链路仍稳定，再进入一级组 AI 命名。
5. `winner / best` 继续在另一个 thread 收敛，不要在这里交叉改动。

## Constraints

- 不要把 `CODEX_PLAN.md` 的阶段文字默认视为已完成，以代码和当前手测结果为准
- 优先做稳定性、性能、恢复和诊断闭环，不要再随意扩展新功能面
- 用户偏好：
  - 沟通专业、简洁、直接
  - 必要时可以直接要求用户配合做样本标注或手测
  - 追求执行效率，不做冗长解释