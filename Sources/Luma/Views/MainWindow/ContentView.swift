import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView(store: store)

            HSplitView {
                GroupSidebar(store: store)
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 280, maxHeight: .infinity)

                PhotoGrid(store: store)
                    .frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)

                DetailPanel(store: store)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 320, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await store.importFolder() }
                } label: {
                    Label("导入文件夹", systemImage: "square.and.arrow.down")
                }

                Button {
                    Task { await store.importSDCard() }
                } label: {
                    Label("导入 SD 卡", systemImage: "memorycard")
                }

                Button {
                    Task { await store.importIPhone() }
                } label: {
                    Label("导入 iPhone", systemImage: "iphone")
                }

                Button {
                    store.openProjectLibrary()
                } label: {
                    Label("项目库", systemImage: "books.vertical")
                }

                Button {
                    store.openPerformanceDiagnostics()
                } label: {
                    Label("性能诊断", systemImage: "speedometer")
                }

                if store.recoverableImportSession != nil {
                    Button {
                        Task { await store.resumeRecoverableImport() }
                    } label: {
                        Label("继续导入", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isImporting)
                }

                Button {
                    store.toggleDisplayMode()
                } label: {
                    Label(
                        store.displayMode == .grid ? "单张查看" : "网格查看",
                        systemImage: store.displayMode == .grid ? "rectangle.inset.filled" : "square.grid.2x2"
                    )
                }
                .disabled(store.selectedAsset == nil)

                Button {
                    Task { await store.startCloudScoring() }
                } label: {
                    Label("开始 AI 评分", systemImage: "sparkles")
                }
                .disabled(store.isCloudScoring || store.activePrimaryModel == nil || store.assets.isEmpty)

                Button {
                    store.openExportPanel()
                } label: {
                    Label("导出选中", systemImage: "square.and.arrow.up")
                }
                .disabled(store.assets.isEmpty || store.pickedAssetsCount == 0)
            }
        }
        .sheet(isPresented: $store.isExportPanelPresented) {
            ExportPanelView(store: store)
        }
        .sheet(isPresented: $store.isProjectLibraryPresented) {
            ProjectLibraryView(store: store)
        }
        .sheet(isPresented: $store.isPerformanceDiagnosticsPresented) {
            PerformanceDiagnosticsView(store: store)
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

private struct StatusBarView: View {
    let store: ProjectStore

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xxl) {
                Text(store.projectName)
                    .font(.headline.weight(.medium))
                    .kerning(DesignType.titleKerning)

                HStack(spacing: AppSpacing.xs) {
                    Text("\(store.assets.count)")
                        .font(.callout.monospacedDigit().weight(.medium))
                    Text("张")
                        .font(.caption.weight(.light))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(store.groups.count)")
                        .font(.callout.monospacedDigit().weight(.medium))
                    Text("组")
                        .font(.caption.weight(.light))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 14)

                statusPill("已选", value: store.pickedCount, tint: LumaSemantic.pick)
                statusPill("待定", value: store.pendingCount, tint: LumaSemantic.pending)
                statusPill("拒绝", value: store.rejectedCount, tint: LumaSemantic.reject)
                statusPill("推荐", value: store.recommendedCount, tint: LumaSemantic.recommend)

                Spacer()

                if store.isLocalScoring {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("本地评估 \(store.localScoringCompleted)/\(store.localScoringTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if store.isCloudScoring {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(LumaSemantic.ai)
                        Text("AI 评分中 \(store.cloudScoringCompleted)/\(store.cloudScoringTotal)")
                            .font(.caption.weight(.light))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if store.importProgress?.phase == .paused {
                    Text("导入已暂停")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if store.costTracker.totalCost > 0 {
                    Text(String(format: "已花费 $%.2f", store.costTracker.totalCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if store.isLocalScoring {
                ProgressView(value: store.localScoringFraction)
                    .progressViewStyle(.linear)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }

            if store.isCloudScoring {
                ProgressView(value: store.cloudScoringFraction)
                    .progressViewStyle(.linear)
                    .tint(LumaSemantic.ai)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.section)
        .padding(.vertical, AppSpacing.lg)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func statusPill(_ title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint.opacity(0.9))
                .frame(width: 6, height: 6)
            Text("\(title) \(value)")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .kerning(DesignType.bodyKerning)
        }
    }
}
