import AppKit
import SwiftUI

/// Hides the default window title (e.g. executable name "Luma") in the toolbar/titlebar area.
struct MainWindowTitleConfig: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.title = ""
            window.titleVisibility = .hidden
        }
    }
}
