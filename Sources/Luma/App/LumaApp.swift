import AppKit
import SwiftUI

@main
struct LumaApp: App {
    @NSApplicationDelegateAdaptor(AppActivationDelegate.self) private var appActivationDelegate
    @State private var store = ProjectStore()

    init() {
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
        }
    }
}

@MainActor
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        activateApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.activateApp()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateApp()
    }

    private func activateApp() {
        NSApp.setActivationPolicy(.regular)
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])

        if let window = NSApp.windows.first(where: { $0.canBecomeKey }) {
            window.makeKeyAndOrderFront(nil)
        }

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
