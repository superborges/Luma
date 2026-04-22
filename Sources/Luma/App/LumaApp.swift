import AppKit
import SwiftUI

/// macOS 26 / Swift 6.2 / arm64e 上的 `swift_task_isCurrentExecutorWithFlagsImpl` PAC failure
/// 全局规避。必须在 Swift runtime 第一次读取该 flag 之前设置（dispatch_once 读取）。
/// 文件级 `let` 在 `@main` 入口之前被 static init 执行，时机足够早。
/// 详见 KNOWN_ISSUES.md 及 https://www.hughlee.page/en/posts/swift-6-migration-pitfalls/
private let executorLegacyModeApplied: Bool = {
    setenv("SWIFT_IS_CURRENT_EXECUTOR_LEGACY_MODE_OVERRIDE", "legacy", 0)
    return true
}()

@main
struct LumaApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appActivationDelegate
    @State private var store = ProjectStore()

    init() {
        // 确保 legacy executor mode 在任何 actor isolation check 之前就位。
        // 引用 executorLegacyModeApplied 防止编译器 dead-strip 这个 file-level initializer。
        precondition(executorLegacyModeApplied)

        if let configuration = TraceSummaryCLI.requestedConfiguration(from: CommandLine.arguments) {
            do {
                try TraceSummaryCLI.run(configuration)
                exit(0)
            } catch {
                fputs("Failed to generate trace summary: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if let configuration = BurstReviewCLI.requestedConfiguration(from: CommandLine.arguments) {
            do {
                try BurstReviewCLI.run(configuration)
                exit(0)
            } catch {
                fputs("Failed to generate burst review pack: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }

        if let outputURL = UISnapshotRenderer.requestedOutputURL(from: CommandLine.arguments) {
            do {
                try UISnapshotRenderer.render(to: outputURL, arguments: CommandLine.arguments)
                exit(0)
            } catch {
                fputs("Failed to render UI snapshot: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 1120, minHeight: 720)
                .task {
                    await store.bootstrap()
                }
        }
        .commands {
            LumaCommands(store: store)
        }

        Settings {
            SettingsView(store: store)
                .buttonStyle(StitchPressScaleButtonStyle())
        }
    }
}

/// AppKit 通过 ObjC runtime 调 `NSApplicationDelegate` 方法。**故意不标 `@MainActor`**：
///
/// macOS 26 / SwiftUI 7.3 / Swift 6.2 / arm64e 上，把 `@MainActor` 加在 ObjC 可见的类上
/// 会让编译器在 `@objc` 方法 prologue 注入 `swift_task_isCurrentExecutorWithFlagsImpl`
/// PAC 校验；该校验会拿到悬挂 SerialExecutorRef，触发 `swift_getObjectType(invalid_addr)`
/// SIGSEGV。Round 7（`HoverDetectorView.isFlipped.getter`）和 Round 8
/// （`AppActivationDelegate.applicationDidBecomeActive` 内的
/// `NSApp.windows.first(where:)` 闭包）都是同一根因，详见 `KNOWN_ISSUES.md`。
///
/// 解决：类本身 nonisolated，AppKit 反正在 main thread 调用我们；方法内显式
/// `MainActor.assumeIsolated { ... }` 拿到 main actor 上下文做实际工作。这样：
/// - `@objc` prologue 不再插 actor isolation check（无 PAC 失败风险）。
/// - 内部 closure（如 `first(where:)` 谓词）不再隐式继承 actor 隔离，不再被 thunk 包装。
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { activateApp() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated { self?.activateApp() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated { activateApp() }
    }

    @MainActor
    private func activateApp() {
        NSApp.setActivationPolicy(.regular)
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])

        // 故意用经典 for 循环替代 first(where:) 闭包：
        // 闭包形式在 macOS 26 / arm64e 下会被插入 actor isolation thunk + PAC 校验，
        // 于 NSAlert 模态结束触发 applicationDidBecomeActive 时崩。
        var keyableWindow: NSWindow?
        for window in NSApp.windows where window.canBecomeKey {
            keyableWindow = window
            break
        }
        keyableWindow?.makeKeyAndOrderFront(nil)

        RuntimeTrace.event(
            "app_activation_attempted",
            category: "app",
            metadata: [
                "window_count": String(NSApp.windows.count),
                "is_active": NSApp.isActive ? "true" : "false"
            ]
        )
    }
}
