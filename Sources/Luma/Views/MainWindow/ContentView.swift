import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ProjectStore
    @AppStorage("Luma.hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @State private var isOnboardingPresented: Bool = false
    // PhotosImportPicker 现在用 AppKit NSAlert 实现（见 AppKitPhotosImportPicker），
    // 不再走 SwiftUI sheet，所以这里也不需要任何 outcome state / sheet modifier。

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        Group {
            if store.hasActiveProject {
                CullingWorkspaceView(store: store)
            } else {
                SessionListView(store: store)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 整个 UI 树共享一个命名坐标空间，所有 .lumaTrack 节点都在这个坐标系里上报 frame，
        // 这样 trace 里的 "frame_x/y/w/h" 在不同子视图之间是可直接对比的。
        .coordinateSpace(.named(LumaCoordinateSpace.window))
        .buttonStyle(StitchPressScaleButtonStyle())
        .preferredColorScheme(.dark)
        .toolbarBackground(StitchTheme.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarColorScheme(.dark, for: .windowToolbar)
        .background(MainWindowTitleConfig())
        .sheet(isPresented: $store.isExportPanelPresented) {
            ExportPanelView(store: store)
                .buttonStyle(StitchPressScaleButtonStyle())
        }
        .sheet(isPresented: $store.isProjectLibraryPresented) {
            ProjectLibraryView(store: store)
                .buttonStyle(StitchPressScaleButtonStyle())
        }
        .sheet(isPresented: $store.isPerformanceDiagnosticsPresented) {
            PerformanceDiagnosticsView(store: store)
                .buttonStyle(StitchPressScaleButtonStyle())
        }
        .sheet(isPresented: $isOnboardingPresented) {
            OnboardingView { isOnboardingPresented = false }
                .buttonStyle(StitchPressScaleButtonStyle())
        }
        .task {
            // 首启自动弹一次 onboarding；用户点"开始使用"后写入 UserDefaults，下次不再弹。
            if !hasSeenOnboarding {
                isOnboardingPresented = true
            }
        }
        // PhotosImportPicker 不再用 SwiftUI sheet。改成 AppKit NSAlert，由
        // `ProjectStore.presentPhotosImportPicker()` 内部直接同步 modal 弹出。
        // 详见 `AppKitPhotosImportPicker` 类型注释中的 5 轮迭代踩坑总结。
        .overlay(alignment: .bottom) {
            if let progress = store.importProgress, store.isImporting || progress.phase == .paused {
                ImportProgressView(progress: progress)
                    .padding()
            } else if let exportProgress = store.exportProgress, store.isExporting {
                ExportProgressBanner(progress: exportProgress)
                    .padding()
            }
        }
        .alert(
            "确认导出到照片 App",
            isPresented: Binding(
                get: { store.isAwaitingPhotosWriteConfirmation },
                set: { if !$0 { store.resolvePhotosWriteConfirmation(false) } }
            )
        ) {
            Button("确认导出") { store.resolvePhotosWriteConfirmation(true) }
            Button("取消", role: .cancel) { store.resolvePhotosWriteConfirmation(false) }
        } message: {
            Text("将把 \(store.pickedAssetsCount) 张已选照片写入「照片 App」。\n写入后无法 Luma 侧撤回；如启用了「删除未选原图」，删除环节会再弹一次系统对话框由你最终确认。")
        }
        .alert(
            store.pendingImportPrompt?.title ?? "导入提示",
            isPresented: Binding(
                get: { store.pendingImportPrompt != nil },
                set: { if !$0 { store.dismissPendingImportPrompt() } }
            ),
            presenting: store.pendingImportPrompt
        ) { prompt in
            Button(prompt.confirmTitle) {
                Task { await store.acceptPendingImportPrompt() }
            }
            Button("稍后", role: .cancel) {
                store.dismissPendingImportPrompt()
            }
        } message: { prompt in
            Text(prompt.message)
        }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.lastErrorMessage = nil } }
            ),
            presenting: store.lastErrorMessage
        ) { _ in
            Button("确定", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: Binding(
            get: { store.lastExportResult != nil },
            set: { if !$0 { store.dismissExportResult() } }
        )) {
            if let result = store.lastExportResult {
                ExportSummaryView(store: store, result: result)
                    .buttonStyle(StitchPressScaleButtonStyle())
            }
        }
        .background(
            KeyboardShortcutBridge { event in
                handleKeyEvent(event)
            }
        )
        // Inspector Overlay（方式 C）：`Cmd+Shift+U` 打开 / 关闭。不用截图就能把
        // 红框 + id 标签叠在真实 UI 上对齐；按工具条 Copy report 可以一键把 registry
        // 导成文本报告粘贴给 AI / 队友。基建文档见 Artifacts/debug-tooling.md。
        .overlay {
            if UIRegistry.shared.isInspectorEnabled {
                LumaInspectorOverlay(
                    registry: UIRegistry.shared,
                    contextMetadataProvider: {
                        [
                            "project_name": store.projectName,
                            "selected_group_id": store.selectedGroupID?.uuidString ?? "all",
                            "selected_asset_id": store.selectedAssetID?.uuidString ?? "none",
                            "visible_asset_count": String(store.visibleAssets.count)
                        ]
                    },
                    onClose: {
                        UIRegistry.shared.toggleInspector(reason: "toolbar_close_button")
                    }
                )
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard shouldHandleKeyEvent(event) else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Cmd+Shift+D：把当前 UI 注册表整批 dump 到 trace（含每个元素的 id + frame + kind）。
        // 配合 RuntimeTrace 的 latest jsonl，定位"用户那一秒看到 / 点到的是哪个矩形"非常方便。
        if modifiers == [.command, .shift], characters == "d" {
            UITrace.snapshot(reason: "shortcut_cmd_shift_d")
            RuntimeTrace.event(
                "ui_dump_requested",
                category: "ui",
                metadata: [
                    "source": "shortcut",
                    "selected_group_id": store.selectedGroupID?.uuidString ?? "all",
                    "selected_asset_id": store.selectedAssetID?.uuidString ?? "none",
                    "element_count": String(UIRegistry.shared.elements.count)
                ]
            )
            return true
        }

        // Cmd+Shift+U：切换 Inspector Overlay（红框 + id 标签）。
        // 这是 Luma 长期保留的 debug 基建，使用说明见 Artifacts/debug-tooling.md。
        if modifiers == [.command, .shift], characters == "u" {
            UIRegistry.shared.toggleInspector(reason: "shortcut_cmd_shift_u")
            return true
        }

        guard modifiers.isEmpty else { return false }

        switch event.keyCode {
        case 123:
            store.moveSelection(by: -1)
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "left", "action": "previous_asset"])
            return true
        case 124:
            store.moveSelection(by: 1)
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "right", "action": "next_asset"])
            return true
        case 126:
            store.jumpToPreviousGroup()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "up", "action": "previous_group"])
            return true
        case 125:
            store.jumpToNextGroup()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "down", "action": "next_group"])
            return true
        case 48:
            store.jumpToNextGroup()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "tab", "action": "next_group"])
            return true
        case 49:
            store.markSelection(.pending)
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "space", "action": "mark_pending"])
            return true
        default:
            break
        }

        switch characters {
        case "p":
            store.markSelection(.picked)
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "p", "action": "pick"])
            return true
        case "x":
            store.markSelection(.rejected)
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "x", "action": "reject"])
            return true
        case "1", "2", "3", "4", "5":
            if let rating = Int(characters) {
                store.rateSelection(rating)
                RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": characters, "action": "rate_\(rating)"])
                return true
            }
        default:
            break
        }

        return false
    }

    private func shouldHandleKeyEvent(_ event: NSEvent) -> Bool {
        guard NSApp.keyWindow != nil,
              store.hasActiveProject,
              store.assets.isEmpty == false,
              store.pendingImportPrompt == nil,
              store.isExportPanelPresented == false,
              store.isProjectLibraryPresented == false,
              store.isPerformanceDiagnosticsPresented == false else {
            return false
        }

        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
           textView.isEditable {
            return false
        }

        return event.type == .keyDown
    }
}
