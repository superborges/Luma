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
    @State private var libraryStore: LibraryStore?
    @State private var migrationManager: V3MigrationManager?

    init() {
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
            Group {
                if let libraryStore, let migrationManager {
                    V4ContentView(libraryStore: libraryStore, migrationManager: migrationManager)
                } else {
                    ProgressView("启动中…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(StitchTheme.background)
                }
            }
            .frame(minWidth: 1120, minHeight: 720)
            .task {
                if libraryStore == nil {
                    do {
                        let db = try LumaDatabase.default()
                        let assetRepo = GRDBMasterAssetRepository(dbQueue: db.dbQueue)
                        let expAssetRepo = GRDBExpeditionAssetRepository(dbQueue: db.dbQueue)
                        let assetMgr = AssetManager(db: db, assetRepo: assetRepo, expeditionAssetRepo: expAssetRepo)
                        let expRepo = GRDBExpeditionRepository(dbQueue: db.dbQueue)
                        let expMgr = ExpeditionManager(repo: expRepo)
                        let sourceMgr = AssetSourceManager(db: db)
                        let groupRepo = GRDBPhotoGroupRepository(dbQueue: db.dbQueue)
                        let scoreRepo = GRDBAssetScoreRepository(dbQueue: db.dbQueue)
                        let importSessionRepo = GRDBImportSessionRepository(dbQueue: db.dbQueue)
                        libraryStore = LibraryStore(
                            db: db,
                            assetManager: assetMgr,
                            expeditionManager: expMgr,
                            assetSourceManager: sourceMgr,
                            photoGroupRepo: groupRepo,
                            scoreRepo: scoreRepo,
                            assetRepo: assetRepo,
                            expeditionAssetRepo: expAssetRepo,
                            importSessionRepo: importSessionRepo
                        )
                        migrationManager = V3MigrationManager(
                            db: db,
                            assetSourceManager: sourceMgr,
                            expeditionManager: expMgr,
                            assetManager: assetMgr,
                            photoGroupRepo: groupRepo,
                            scoreRepo: scoreRepo,
                            importSessionRepo: importSessionRepo
                        )
                    } catch {
                        fatalError("Failed to initialize database: \(error)")
                    }
                }
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

/// AppKit 通过 ObjC 调 delegate；**不要**整类标 `@MainActor`，也**不要**在 `@objc` 入口里同步
/// `MainActor.assumeIsolated`（见 `KNOWN_ISSUES.md`）。用 `Task { @MainActor in … }`。
final class AppActivationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            self.activateApp()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor in
                self?.activateApp()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            self.activateApp()
        }
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
