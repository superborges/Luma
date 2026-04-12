import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        HStack(spacing: 0) {
            SideNavBar(currentSection: $store.currentSection)
            sectionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        .overlay(alignment: .bottom) {
            if let progress = store.importProgress, store.isImporting || progress.phase == .paused {
                ImportProgressView(progress: progress)
                    .padding()
            }
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
        .alert(
            "导出完成",
            isPresented: Binding(
                get: { store.lastExportSummary != nil },
                set: { if !$0 { store.lastExportSummary = nil } }
            ),
            presenting: store.lastExportSummary
        ) { _ in
            Button("确定", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .background(
            KeyboardShortcutBridge { event in
                handleKeyEvent(event)
            }
        )
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch store.currentSection {
        case .library:
            LibraryHubView(store: store)
        case .imports:
            ImportsHubView(store: store)
        case .culling:
            CullingHubView(store: store)
        case .editing:
            EditingHubView()
        case .export:
            ExportHubView(store: store)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard shouldHandleKeyEvent(event) else { return false }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if modifiers == [.command], characters == "a" {
            store.selectRecommendedInCurrentScope()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "cmd+a", "action": "select_recommended"])
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
        case 48:
            store.jumpToNextGroup()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "tab", "action": "next_group"])
            return true
        case 49:
            store.toggleDisplayMode()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "space", "action": "toggle_display_mode"])
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
        case "u":
            store.clearSelectionDecision()
            RuntimeTrace.event("key_command_handled", category: "interaction", metadata: ["key": "u", "action": "clear_decision"])
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
              store.currentSection == .culling,
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
