# Luma — Known Issues / Crash Archive

最近一类核心问题：**Swift 6.2 / SwiftUI 7.3 / macOS 26 / arm64e 上的 `swift_task_isCurrentExecutorWithFlagsImpl` PAC failure**。
所有崩溃栈共同特征：

```
0  swift_getObjectType / objc_msgSend         ← 解引用 PAC tagged 垃圾指针
1  swift_task_isMainExecutorImpl
2  SerialExecutorRef::isMainExecutor() const
3  swift_task_isCurrentExecutorWithFlagsImpl  ← actor isolation check
4  Luma  <某个 closure / @objc method>
...
Exception Subtype: KERN_INVALID_ADDRESS at 0xXXXX -> 0xXXXX (possible pointer authentication failure)
```

根因：苹果在 SerialExecutorRef.identity 上做 PAC 签名，arm64e 在 dispatch 路径上拿到的指针 PAC tag 已损坏，验签失败 → 段错误。
不是我们代码逻辑写错，是 SDK 在 Swift 6 strict concurrency + arm64e 上的退化。

## 全局修复尝试记录

### 尝试 A：环境变量 `SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE=legacy`（失败）

**原理**：Swift runtime `swift_task_isCurrentExecutorWithFlagsImpl` 根据 flags 决定
"executor 不匹配时是 crash 还是 return false"。该环境变量切回 legacy（非 crash）模式。

**落地位置**：`LumaApp.swift` 文件级 `let` + `Info.plist` `LSEnvironment` + `run-luma.sh`。

**结果**：Round 9 崩溃——**无效**。
原因：崩溃不在 "assert on mismatch" 分支，而是在检查过程中走
`SerialExecutor.isMainExecutor.getter` 时跳到 **null 函数指针**（`pc=0x0`）。
环境变量只控制 assert/return 行为，无法绕过 null dereference。

### 尝试 B：编译器 flag `-Xfrontend -disable-actor-data-race-checks`（失败）

**原理**：让编译器不在 Luma 自身代码中生成 `swift_task_isCurrentExecutor` 调用，
从编译期根源消除。

**落地位置**：`Package.swift` → `swiftSettings: [.unsafeFlags(["-Xfrontend", "-disable-actor-data-race-checks"])]`

**结果**：Round 10 崩溃——**无效**。
可能原因：

1. SwiftUI 框架自身（预编译的 `.framework`）在调用我们 view body closure 时也
  会插入 isolation check，这些在系统框架里，我们的编译 flag 管不到。
2. 或者 flag 只禁用了显式 `@MainActor` check，SwiftUI 内部的 dispatch 路径
  上的 check 仍然存在。

### 下一步方向（待尝试）

1. **降级 Swift 语言模式为 5**：`Package.swift` 中 `swiftLanguageMode: .v5`，
  彻底关闭 Swift 6 strict concurrency。这会让编译器不为 closures 生成
   isolation thunks，也会让 SwiftUI runtime 走 Swift 5 兼容路径。
2. **SessionRow → 纯 AppKit**：把 `SessionListView` 整体用
  `NSTableView` / `NSCollectionView` + `NSViewRepresentable` 实现，
   完全绕开 SwiftUI 的 view body closure + actor isolation 机制。
3. **降级 swift-tools-version 到 5.10**：配合语言模式 5，回到
  Swift 5.10 编译器（如果 Xcode 16 CLI 仍可用）。

---

## 历史 Round（按时间倒序）

### Round 10 — 2026-04-23 00:50 — `closure #3 in SessionRow.body.getter`（`-disable-actor-data-race-checks` 无效）

**触发**：app 启动后正常操作，同 Round 9 的崩溃位置。

**关键栈**：与 Round 9 完全相同——`closure #3 in SessionRow.body.getter + 84` → 
`swift_task_isCurrentExecutorWithFlagsImpl` → `SerialExecutor.isMainExecutor.getter`
→ `pc=0x0`。

**诊断**：已应用 `-Xfrontend -disable-actor-data-race-checks` 编译 flag，
但崩溃依旧。flag 只影响 Luma 自身编译产物，SwiftUI 系统框架
（SwiftUICore.framework 7.3.2）是预编译的，内部在调用我们 view body closure 时
仍可能走 actor isolation check 路径。

**环境**：pid=65587，已加载全部三层保障（env var + Info.plist + compile flag），
全部无效。

---

### Round 9 — 2026-04-23 00:45 — `closure #3 in SessionRow.body.getter`（env var 无效）

**触发**：启动后操作。pid=65118。

**关键栈**：

```
0  ???               0x0  (pc=0x0, null function pointer)
1  SerialExecutor.isMainExecutor.getter + 112
2  _swift_task_isMainExecutorSwift + 32
3  swift::SerialExecutorRef::isMainExecutor() const + 24
4  swift_task_isCurrentExecutorWithFlagsImpl + 72
5  closure #3 in SessionRow.body.getter + 84
```

**诊断**：`SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE=legacy` 环境变量
已生效（三层保障），但崩溃不在 assert/return 分支，而是在 check 过程中
`isMainExecutor.getter` 走 witness table 时拿到 null 函数指针 → SIGSEGV。
与之前的 PAC tagged 悬挂指针不同，这次是彻底的 null（`far=0x0`）。

---

### Round 8 — 2026-04-23 00:32 — `AppActivationDelegate.applicationDidBecomeActive` → `Sequence.first(where:)` 闭包

**触发**：用户在 AppKit Photos Import Picker 上点「估算并继续」按钮，NSAlert
模态结束 → AppKit 给 host app 发 `NSApplicationDidBecomeActiveNotification`
→ 我们的 `AppActivationDelegate.applicationDidBecomeActive(_:)` 被 ObjC 反射调到。

**关键栈**：

```
0  libswiftCore          swift_getObjectType + 40
1  libswift_Concurrency  swift_task_isMainExecutorImpl
2  libswift_Concurrency  SerialExecutorRef::isMainExecutor() const
3  libswift_Concurrency  swift_task_isCurrentExecutorWithFlagsImpl
4  Luma                  closure #1 in AppActivationDelegate.activateApp() + 92
5  libswiftCore          Sequence.first(where:) + 756
6  Luma                  AppActivationDelegate.activateApp()  (LumaApp.swift:77)
7  Luma                  AppActivationDelegate.applicationDidBecomeActive(_:)
8  Luma                  @objc AppActivationDelegate.applicationDidBecomeActive(_:) + 248
9  CoreFoundation        __CFNOTIFICATIONCENTER_IS_CALLING_OUT_TO_AN_OBSERVER__
...
14 AppKit                -[NSApplication _handleActivatedEvent:]
```

**诊断**：和 Round 7 同根。`AppActivationDelegate` 标了 `@MainActor` final class，
被 AppKit 通过 ObjC 调 `applicationDidBecomeActive(_:)`。Swift 6.2 编译器在 `@objc`
方法 prologue 注入 actor isolation check；该 check 拿到 PAC-tagged 悬挂
SerialExecutorRef → `swift_getObjectType(0x100000000)` → SIGSEGV。

崩在 `Sequence.first(where:)` 的闭包是细节：闭包继承外层 actor isolation，每次
调用要做 isolation check；Round 7 是 NSView `@objc isFlipped` getter，本质一致。

**修复（已落地）**：

- `AppActivationDelegate` 去掉 `@MainActor` 类标注；类本身 nonisolated。
- `applicationDidFinishLaunching` / `applicationDidBecomeActive` 是 nonisolated 入口，
内部用 `MainActor.assumeIsolated { activateApp() }` 同步切到 main actor 干活
（AppKit 反正在 main thread 调 delegate，assumeIsolated 永远不会 trap）。
- `activateApp()` 仍然 `@MainActor`，但内部 `NSApp.windows.first(where:)` 改成经典
for 循环，避免 closure 隐式继承 actor isolation 再次插 PAC 校验。

**同一波修复**：`AppKitPhotosImportPicker.SegmentedToggleTarget` 之前我标了
`@MainActor`，已同步去掉，改 nonisolated + `MainActor.assumeIsolated` 读 sender 属性。

---

### 已知风险点（尚未崩，但同一类雷）

- `IPhoneAdapter` 的 `IPhoneDeviceDiscovery: NSObject, ICDeviceBrowserDelegate`
仍是 `@MainActor` final class。仅在用户连 USB iPhone 触发设备枚举时被 ImageCapture
通过 ObjC 反射调 `deviceBrowser(_:didAdd:moreComing:)`。当前流程下不在主路径上，
尚无崩溃记录；下次出问题先改这个。修复模板：去掉类的 `@MainActor`，handler 方法
内 `MainActor.assumeIsolated { ... }`。

---

### Round 7 — 2026-04-22 01:51 — `LumaSafeHoverDetector.HoverDetectorView.isFlipped.getter`

**触发**：app 启动后鼠标 hover（连 picker 都没打开）。

**关键栈**：

```
0  libobjc.A.dylib  objc_msgSend + 56
1  libswiftCore     swift_getObjectType + 204
2  libswift_Concurrency  swift_task_isMainExecutorImpl
3  libswift_Concurrency  swift_task_isCurrentExecutorWithFlagsImpl
4  libswift_Concurrency  _checkExpectedExecutor + 60
5  Luma  @objc LumaSafeHoverDetector.HoverDetectorView.isFlipped.getter + 112
6  AppKit  _convertPoint_fromAncestor
7  AppKit  ___nonOverridableViewHitTest_block_invoke      (递归 9 层 hit-test)
...
35 AppKit  -[_NSTrackingAreaAKManager _updateActiveTrackingAreasForWindowLocation:modifierFlags:]
```

**诊断**：

- 上一轮（Round 6）我把 SwiftUI `.onHover` 全替换成 `LumaSafeHoverDetector` (NSViewRepresentable + NSTrackingArea)，绕开 `HoverResponder`。
- 但 `HoverDetectorView` 继承 `NSView`（@MainActor 隔离），override 了 `isFlipped`/`hitTest`/`mouseEntered`/`mouseExited`。
- AppKit 在 hit-test 路径上调 `view.isFlipped`（@objc），Swift 编译器在 @objc method prologue 插入了 `_checkExpectedExecutor` → 同一个 PAC bug 触发。
- 14 个 SessionRow 都挂载了 `HoverDetectorView`，鼠标移动 → AppKit 递归 hit-test 整棵 view tree → 每一层都中招。

**Round 7 临时修复方向（明天试）**：

1. **首选**：删掉 `HoverDetectorView` 中所有 override（`isFlipped`/`hitTest`），只保留 `mouseEntered/mouseExited` 和 `updateTrackingAreas`。父 view tree 不需要 flipped；hitTest 不抢点击通过 `userInteractionEnabled = false` 或父层 `.allowsHitTesting(false)` 已经够。
2. **次选**：`HoverDetectorView` 上每个 override 标 `nonisolated`（Swift 6.2 允许在 @MainActor 类内部局部 opt-out）。
  ```swift
   nonisolated override var isFlipped: Bool { true }
   nonisolated override func hitTest(_ point: NSPoint) -> NSView? { nil }
   nonisolated override func mouseEntered(with event: NSEvent) { ... }
  ```
   — 但 `mouseEntered` 内要写 `onHoverChange?(...)`，closure 仍可能捕获 main isolation。需要 `MainActor.assumeIsolated { ... }` 包一下。
3. **激进**：完全去掉 hover 高亮交互（首页 SessionRow 不再 hover）。性价比最高、最稳。

### Round 6 — 2026-04-22 01:47 — `SessionRow.body` 的 `.onHover { hovered = $0 }`

**触发**：app 启动后鼠标 hover SessionRow（首页）。

**关键栈**：

```
4  Luma  closure #4 in SessionRow.body.getter + 104
5  SwiftUI  partial apply for closure #1 in HoverResponder.updatePhase(_:)
13 SwiftUI  @objc NSHostingView.mouseEntered(with:)
14 AppKit   -[NSTrackingArea _dispatchMouseEntered:]
```

**修复**：写 `LumaSafeHoverDetector`（NSViewRepresentable + NSTrackingArea），全 codebase 14 处 `.onHover { hovered = $0 }` → `.lumaSafeHover($hovered)`。
**结果**：绕开了 SwiftUI HoverResponder，但 NSView override 触发了 Round 7。

### Round 1–5 — Photos Import Picker (SwiftUI sheet)

5 次连续崩溃，均围绕 `PhotosImportPickerView`（SwiftUI sheet）：


| Round | 触发        | 关键栈                                                         | 修复尝试                                                                                    |
| ----- | --------- | ----------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| 1     | 打开 picker | `NavigationStack` + body PAC failure                        | `NavigationStack` → `VStack`                                                            |
| 2     | 同上        | `VStack` body PAC failure                                   | 把 store ref 拆成 closure props                                                            |
| 3     | 同上        | closure prop PAC failure                                    | closure 标 `@MainActor`、`PhotosImportPlan` 改 `Identifiable`、`SmartAlbum` 纯 Swift enum    |
| 4     | 重新估算      | `DesignLibrary.framework` 帧 + isEstimating 状态变化 PAC failure | 去掉 `Form/Section/LabeledContent`，改纯 `ScrollView/VStack`                                 |
| 5     | 重新估算      | `closure in body.getter` PAC failure（无 DesignLibrary 帧）     | **架构换血**：删除 SwiftUI picker，用 AppKit `NSAlert` + `NSStackView` accessory view 实现两步 modal |


**当前状态**：picker 已替换为 `AppKitPhotosImportPicker`（`NSAlert.runModal()` 阻塞），不在崩溃路径上。

---

## 通用规律 / 排查清单

1. 看崩溃栈第 4 帧（去掉 swift_concurrency runtime 的前 4 帧）：通常就是我们写的、被 SwiftUI/AppKit @objc dispatch 调的 closure / method。
2. `Exception Subtype` 含 `(possible pointer authentication failure)` + 高位有非零 byte（如 `0x6826...`、`0x97d0...`）→ 100% PAC bug。
3. 受影响代码模式：
  - SwiftUI `.onHover`、`.onTapGesture`、`.onChange` 等 closure（dispatched by SwiftUI 内部 responder）
  - `@MainActor` class 的 @objc method（被 AppKit 直接调用，prologue 插 `_checkExpectedExecutor`）
  - 任何在 SwiftUI sheet body / SwiftUI render 路径上做 `@MainActor` async 状态变化的 closure
4. 常见绕道：
  - SwiftUI 路径不稳 → 用 AppKit (`NSAlert`、`NSPopover`)
  - `@MainActor` @objc method 不稳 → 加 `nonisolated` opt-out + `MainActor.assumeIsolated` 内部
  - closure stored in struct → 改成函数引用 / 直接读 `@Environment`
5. 完全规避 PAC failure 的最稳办法：**该交互不要做**。hover 高亮、复杂 sheet 都不是 v1 阻塞功能，可以暂时砍。

---

## 诊断日志位置

- 运行时 trace：`~/Library/Application Support/Luma/Diagnostics/runtime-latest.jsonl`
- macOS crash 报告：`~/Library/Logs/DiagnosticReports/Luma-*.ips`
- UI inspector dump：`~/Documents/Luma-UI-Inspector-*.md`

