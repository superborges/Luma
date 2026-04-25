# Luma — 已知问题与工程约定

在 **Swift 6、macOS 26+、SwiftUI、arm64e** 等组合下，部分崩溃与 **MainActor / `swift_task_isCurrentExecutor*`** 相关，多见于系统 SwiftUI/并发 runtime 与 AppKit/ObjC 交界的调用路径，不纯粹是业务逻辑写错。本仓库用下面几条**工程约定**与缓解手段降低概率；**具体代码位置**以 `Package.swift`、`LumaApp.swift`、各模块注释为准。

## 1. 已采用的缓解

| 项 | 作用 |
|----|------|
| `Package.swift` | `swiftLanguageMode(.v5)`；`-disable-actor-data-race-checks` 减少**自研代码**中编译器注入的 runtime isolation 检查（系统预编译的 SwiftUI 等不受此控制）。 |
| 启动时环境变量 | `LumaApp.swift` 在入口前 `setenv`；`Info.plist` 的 `LSEnvironment` 与 `run-luma.sh` 的 `open` 环境便于 Finder / 脚本启动时一致。 |
| `AppActivationDelegate` | **不要**在 delegate 的 `@objc` 入口里同步 `MainActor.assumeIsolated`；用 `Task { @MainActor in … }`；类**不要**标成整类 `@MainActor`，避免与 AppKit 回调的隔离语义冲突。`activateApp()` 内用 **for 循环**代替 `NSApp.windows.first(where:)` 等带 actor 继承的谓词闭包。 |
| Session 列表行 | 主区域用 `NSView` 接点击（`SessionRowOpenHitView`），避免仅依赖 SwiftUI `Button` + 部分系统版本上事件回灌路径。 |
| 从「照片」导入（默认） | 菜单路径为**仅选张数**的 `AppKitPhotosCountOnlyPicker`；`AppKitPhotosImportPicker`（相册/多段控件）仍保留在仓库，**非默认入口**。 |
| 运行方式 | 优先 `./scripts/run-luma.sh` 打 **Luma.app** 再试；TCC/PhotoKit 对裸可执行体与带 Bundle ID 的 app 可能不一致。 |

## 2. 新写代码时建议

- **AppKit 回调**里需要 MainActor 时：优先 `Task { @MainActor in }`，对 `NSView` 的 `mouseDown` 等同理；慎用 `MainActor.assumeIsolated`（在「有主无线程上的 Swift 任务上下文」不成立时可能 **trap**）。  
- **SwiftUI 闭包/手势**里避免叠过多异步与状态机；能放到 **独立 AppKit 模态** 的尽量不放 SwiftUI `sheet`（照片导入已按此做）。  
- 仍遇崩溃：收集 **`~/Library/Logs/DiagnosticReports/Luma-*.ips`** 栈顶、以及 **import-breadcrumb** / runtime trace 最后一行，便于对照**当前**代码。

## 3. 诊断位置（与实现对齐）

- 设置 → **开发** Tab：Trace 路径、导入面包屑路径（见 `AppDirectories`）。  
- 系统崩溃：`.ips` 见上路径。
