import AppKit
import SwiftUI

/// 首页 `SessionRow` 主区域用 AppKit 收鼠标，**不用** SwiftUI `Button` / `onTapGesture`：
/// macOS 26 / Swift 6.2 / arm64e 上 SessionRow 里这类控件会在 `AppKitEventBindingBridge.flushActions`
/// 时仍走进 `SessionRow.body` 的闭包，触发 `swift_task_isCurrentExecutorWithFlagsImpl` + `pc=0`（见 KNOWN_ISSUES Round 10）。
struct SessionRowOpenHitView: NSViewRepresentable {
    var onOpen: () -> Void

    func makeNSView(context: Context) -> SessionRowHitView {
        let v = SessionRowHitView()
        v.onOpen = onOpen
        return v
    }

    func updateNSView(_ nsView: SessionRowHitView, context: Context) {
        nsView.onOpen = onOpen
    }
}

/// 纯 `NSView` + `mouseDown`，不 override `isFlipped` / 不加 `@MainActor` 类标；闭包在 main 上执行。
final class SessionRowHitView: NSView {
    var onOpen: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 全矩形接收点击，避免透明区落到下层 SwiftUI。
        if bounds.contains(point) { return self }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let onOpen else { return }
        // 与 `AppActivationDelegate` 相同：主线程的 NSView 回调里**没有** MainActor 任务时
        // `MainActor.assumeIsolated` 会 assert（.ips: EXC_BREAKPOINT）。用 `Task { @MainActor in }` 投送。
        Task { @MainActor in
            onOpen()
        }
    }
}
