# V1 架构设计

# 一、背景

Luma MVP 已跑通「多源导入 → 智能分组 → 本地评分 → 选片 → 导出/归档」闭环。V1 在 MVP 基础上做体验增强：选片右栏展示 AI 评分与废片标签、快捷键补齐、照片导入筛选从「仅张数」升级为完整筛选面板、导出增加文件命名规则、设置页增加分组阈值等可配项。不引入云端依赖，不改变核心数据模型结构。

# 二、目标

**功能目标**
- 选片右栏消费已有 `aiScore` / `issues` 数据，零新增模型字段
- 照片导入切换为 `AppKitPhotosImportPicker`（已存在，未接入默认菜单）
- 导出选项新增 `fileNamingRule` 字段；分组阈值、缓存上限等用户可配

**架构目标**
- View 层与配置层为主要变更范围；Import 层 `PhotosImportPlan` / `PhotosImportPlanner` / `PhotosLibraryAdapter` 因照片导入重构有较大改动，但核心 `GroupingEngine` 算法不变
- `ExportOptions` 扩展保持 Codable 向后兼容（新字段有默认值）
- 设置项通过 UserDefaults 传递，GroupingEngine / ThumbnailCache 在初始化或下次导入时读取
- 性能：右栏评分渲染不引入额外 I/O；月份选择器使用 count-only PhotoKit 查询 + 翻页 UI，不阻塞主线程

# 三、架构设计

## 3.1 整体分层（V1 变更标注）

```
┌─────────────────────────────────────────────────┐
│  Views (SwiftUI / AppKit)                       │
│  ┌─────────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ CullingWork │ │ AppKit   │ │ ExportPanel  │  │
│  │ spaceView   │ │ Photos   │ │ View         │  │
│  │ ★ 右栏增强  │ │ Import   │ │ ★ 命名规则  │  │
│  │ ★ 快捷键   │ │ Picker   │ │              │  │
│  │             │ │ ★ 接入   │ │              │  │
│  └──────┬──────┘ └────┬─────┘ └──────┬───────┘  │
│         │             │              │           │
│  ┌──────┴─────────────┴──────────────┴───────┐  │
│  │         ProjectStore (@Observable)         │  │
│  │  ★ 读取 UserDefaults 配置项               │  │
│  └──────┬─────────────┬──────────────┬───────┘  │
├─────────┼─────────────┼──────────────┼───────────┤
│  Services / Utilities                            │
│  ┌─────────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ Grouping    │ │ Photos   │ │ FolderExp    │  │
│  │ Engine      │ │ Import   │ │ orter        │  │
│  │ ★ 阈值可配 │ │ Planner  │ │ ★ 命名逻辑  │  │
│  └─────────────┘ └──────────┘ └──────────────┘  │
├──────────────────────────────────────────────────┤
│  Models                                          │
│  ExportOptions ★ fileNamingRule                  │
│  MediaAsset.aiScore / .issues (已有，无变更)     │
│  PhotosImportPlan ★ MonthSlot 月份选择模型       │
└──────────────────────────────────────────────────┘
```

★ = V1 新增或变更

## 3.2 模块详细设计

### F1 选片右栏增强

**变更范围**：仅 `CullingWorkspaceView` 右栏区域。

数据流：`ProjectStore.assets[selectedIndex].aiScore` / `.issues` → View 直接读取渲染。

```
MediaAsset.aiScore ──► AIScoreCardView (新组件)
   ├─ overall: Int          → 大号数字 + 色彩等级
   ├─ sharpness/composition → 横条 Bar
   └─ comment: String?      → 文案

MediaAsset.issues ──► IssueTagsView (新组件)
   └─ [AssetIssue]          → 小标签列表
```

不涉及数据写入或网络。评分数据在导入后由 `LocalMLScorer` 已填充。

### F2 快捷键补齐

**变更范围**：`ContentView` 的 `handleKeyEvent` 分支。

| 键 | 行为 | 实现 |
|----|------|------|
| `U` / `Space` | 清除决策回待定（不跳转下一张） | `ProjectStore.clearSelectionDecision()` |
| `G` | 切换 `viewMode`（网格/单张） | `ProjectStore.toggleViewMode()` → `viewModeToggleTick` 触发 UI |
| 连拍「采纳推荐」 | 将 `burst.bestAsset` Pick，其余 Reject | `ProjectStore.acceptBurstRecommendation(for: BurstSelectionContext)` |

### F3 照片导入筛选（月份选择器）

**变更范围**：`ProjectStore.presentPhotosImportPicker()` 完全重写；`PhotosImportPlan` 数据模型重构；`PhotosImportPlanner` 新增 `monthlyStats()`。

**设计决策**：原方案（时间/相册/类型/去重/预估）在实际使用中遇到多次 PhotoKit 崩溃和性能问题。最终重构为**纯月份选择器**，去掉相册维度，更稳定、更直观。

```
ProjectStore
  └─ presentPhotosImportPicker()
       ├─ 授权检查
       ├─ PhotosImportPlanner.monthlyStats() ← 后台线程，count-only 查询
       │    └─ PhotoKitSafetyWrapper.withTimeout(15s)
       ├─ AppKitPhotosImportPicker.presentBlocking(monthlyStats:)
       │    └─ 按年翻页 UI（◀/▶ 切换年份，每页≤12月）
       └─ confirmPhotosImport(plan, excludedLocalIdentifiers:)
            └─ ImportManager → PhotosLibraryAdapter(dateRanges:)
```

**关键实现细节**：
- `PhotosImportPlan` 改为 `selectedMonths: [MonthSlot]`，去掉 `DatePreset`/`SmartAlbum`/相册字段
- `PhotosImportPlanner.monthlyStats()` 不标 `@MainActor`，用 `PHFetchResult.count`（O(1) SQLite COUNT）逐月查询
- `PhotosLibraryAdapter` 接收 `dateRanges: [ClosedRange<Date>]`，用 OR 谓词支持非连续月份
- `PhotoKitSafetyWrapper.withTimeout` 超时立即返回 fallback 并取消挂起任务
- `NSApp.activate(ignoringOtherApps: true)` 确保弹窗不被主窗口遮挡

### F4 导出文件命名

**变更范围**：`ExportOptions` + `FolderExporter` + `LightroomExporter`。

```swift
// ExportOptions 新增
enum FileNamingRule: String, Codable, Hashable, CaseIterable {
    case original       // IMG_1234.jpg
    case datePrefix     // 2026-01-15_IMG_1234.jpg
    case custom         // 用户模板
}
var fileNamingRule: FileNamingRule = .original
var customNamingTemplate: String = "{date}_{original}"
```

命名逻辑封装为独立函数：

```swift
func resolvedFileName(
    for asset: MediaAsset,
    rule: FileNamingRule,
    template: String,
    groupName: String,
    sequenceInGroup: Int
) -> String
```

被 `FolderExporter.export(...)` 和 `LightroomExporter.export(...)` 在拷贝文件时调用。RAW+JPEG 配对共享主文件名。

Codable 兼容：`CodingKeys` 中 `fileNamingRule` 用 `decodeIfPresent` + 默认 `.original`。

### F5 设置页增强

**变更范围**：`SettingsView` 通用 Tab + UserDefaults。

| 配置项 | UserDefaults 键 | 消费方 |
|--------|-----------------|--------|
| 分组时间阈值 | `Luma.groupingTimeThreshold` | `GroupingEngine`（下次导入读取） |
| 缩略图缓存上限 | `Luma.thumbnailCacheLimit` | `ThumbnailCache.countLimit`（热更新） |
| 默认命名规则 | `Luma.defaultFileNamingRule` | `ExportOptions` 初始化时读取 |

`GroupingEngine` 当前 `timeThreshold` 为常量；V1 改为 init 参数或读 UserDefaults，不改算法。

# 四、评估和验收

## 风险点

| 风险 | 等级 | 缓解 |
|------|------|------|
| F3 PhotoKit 超时/崩溃 | 中 | `PhotoKitSafetyWrapper.withTimeout(15s)` 兜底；count-only 查询避免全量枚举；后台线程避免主线程阻塞 |
| F4 命名冲突 | 低 | 冲突追加 `-2` 后缀；写单测覆盖 |
| F1 大量资产时右栏性能 | 低 | 评分数据已在内存，渲染为轻量 SwiftUI 组件 |

## 验收 Checklist

- [ ] F1：右栏展示总分 + 五维 + 废片标签；无评分时灰色占位
- [ ] F2：U(Space)/G/采纳推荐 快捷键可用
- [ ] F3：默认菜单进入月份选择器；每月照片数 + 容量预估 + 重复/大量告警；0 张时拦截
- [ ] F4：三种命名规则均可用；RAW+JPEG 配对；冲突后缀
- [ ] F5：三项设置持久化且生效（阈值需下次导入验证）
- [ ] 全量 `swift test` 通过（含新增单测）
- [ ] `./scripts/run-v1-contract-tests.sh` 通过
- [ ] 无新增重型外部依赖
