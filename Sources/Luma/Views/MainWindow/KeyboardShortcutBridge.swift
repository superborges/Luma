import AppKit
import SwiftUI

struct KeyboardShortcutBridge: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> KeyHandlingView {
        let view = KeyHandlingView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.installMonitorIfNeeded()
        return view
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {
        context.coordinator.handler = handler
        nsView.coordinator = context.coordinator
        nsView.activateIfNeeded()
    }

    static func dismantleNSView(_ nsView: KeyHandlingView, coordinator: Coordinator) {
        nsView.coordinator = nil
        coordinator.removeMonitor()
    }

    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var localMonitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func installMonitorIfNeeded() {
            guard localMonitor == nil else { return }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handler(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
        }
    }
}

final class KeyHandlingView: NSView {
    weak var coordinator: KeyboardShortcutBridge.Coordinator?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        activateIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        if coordinator?.handler(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    func activateIfNeeded() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(self)
        }
    }
}
