import AppKit
import SwiftUI

struct PerformanceDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ProjectStore

    @State private var thumbnailSnapshot: ThumbnailCacheSnapshot = .empty
    @State private var displaySnapshot: DisplayImageCacheSnapshot = .empty
    @State private var latestTraceURL: URL?
    @State private var sessionTraceURL: URL?
    @State private var refreshTask: Task<Void, Never>?

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summarySection
                    traceSection
                    thumbnailSection
                    displaySection
                }
                .padding(24)
            }
            .navigationTitle("性能诊断")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("重置计数") {
                        ThumbnailCache.shared.resetDiagnostics()
                        DisplayImageCache.shared.resetDiagnostics()
                        refreshSnapshots()
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        closeDiagnostics()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }

            Divider()

            HStack {
                Button("重置计数") {
                    ThumbnailCache.shared.resetDiagnostics()
                    DisplayImageCache.shared.resetDiagnostics()
                    refreshSnapshots()
                }

                Spacer()

                Button("关闭") {
                    closeDiagnostics()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(.bar)
        }
        .frame(minWidth: 720, minHeight: 520)
        .task {
            refreshSnapshots()
            refreshTask?.cancel()
            refreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await MainActor.run {
                        refreshSnapshots()
                        refreshTraceURLs()
                    }
                }
            }
        }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
            store.closePerformanceDiagnostics()
        }
        .interactiveDismissDisabled(false)
    }

    private var summarySection: some View {
        GroupBox("当前状态") {
            VStack(alignment: .leading, spacing: 10) {
                statRow("当前项目", store.projectName)
                statRow("当前范围", "\(store.visibleAssets.count) 张")
                statRow("显示模式", store.displayMode == .grid ? "网格" : "单张")
                statRow("当前选中", store.selectedAsset != nil ? "有" : "无")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var traceSection: some View {
        GroupBox("Trace") {
            VStack(alignment: .leading, spacing: 10) {
                traceRow("Latest", latestTraceURL)
                traceRow("Session", sessionTraceURL)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var thumbnailSection: some View {
        GroupBox("缩略图缓存") {
            VStack(alignment: .leading, spacing: 10) {
                statRow("内存命中", "\(thumbnailSnapshot.memoryHits)")
                statRow("磁盘命中", "\(thumbnailSnapshot.diskHits)")
                statRow("并发复用", "\(thumbnailSnapshot.inflightJoins)")
                statRow("新生成", "\(thumbnailSnapshot.generatedImages)")
                statRow("预热请求", "\(thumbnailSnapshot.preheatedItems)")
                statRow("裁剪回收", "\(thumbnailSnapshot.trimEvictions)")
                statRow("内存保留", "\(thumbnailSnapshot.activeMemoryItems)")
                statRow("进行中任务", "\(thumbnailSnapshot.inflightLoads)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var displaySection: some View {
        GroupBox("单张显示缓存") {
            VStack(alignment: .leading, spacing: 10) {
                statRow("内存命中", "\(displaySnapshot.memoryHits)")
                statRow("并发复用", "\(displaySnapshot.inflightJoins)")
                statRow("解码生成", "\(displaySnapshot.decodedImages)")
                statRow("预热请求", "\(displaySnapshot.preheatedItems)")
                statRow("裁剪回收", "\(displaySnapshot.trimEvictions)")
                statRow("内存保留", "\(displaySnapshot.activeMemoryItems)")
                statRow("进行中任务", "\(displaySnapshot.inflightLoads)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .monospacedDigit()
            Spacer()
        }
    }

    private func traceRow(_ title: String, _ url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(title)
                    .foregroundStyle(.secondary)
                    .frame(width: 120, alignment: .leading)
                Text(url?.path ?? "未生成")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
            }

            if let url {
                HStack(spacing: 12) {
                    Button("复制路径") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .padding(.leading, 120)
            }
        }
    }

    private func refreshSnapshots() {
        thumbnailSnapshot = ThumbnailCache.shared.snapshot()
        displaySnapshot = DisplayImageCache.shared.snapshot()
    }

    private func refreshTraceURLs() {
        Task {
            let latest = await RuntimeTrace.latestTraceFileURL()
            let session = await RuntimeTrace.sessionTraceFileURL()
            await MainActor.run {
                latestTraceURL = latest
                sessionTraceURL = session
            }
        }
    }

    private func closeDiagnostics() {
        store.closePerformanceDiagnostics()
        dismiss()
    }
}
