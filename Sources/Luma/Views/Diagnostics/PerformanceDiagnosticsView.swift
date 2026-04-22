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
                    uiRegistrySection
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
                    .stitchHoverDimming()
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        closeDiagnostics()
                    }
                    .keyboardShortcut(.cancelAction)
                    .stitchHoverDimming()
                }
            }

            Divider()

            HStack {
                Button("重置计数") {
                    ThumbnailCache.shared.resetDiagnostics()
                    DisplayImageCache.shared.resetDiagnostics()
                    refreshSnapshots()
                }
                .stitchHoverDimming()

                Spacer()

                Button("关闭") {
                    closeDiagnostics()
                }
                .keyboardShortcut(.cancelAction)
                .stitchHoverDimming()
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

    /// UI 元素定位面板：列出当前注册到 `UIRegistry` 的所有元素 + 一把 dump 到 trace。
    /// debug "我点的是哪个 cell" / "右栏 cell 渲染到哪个坐标" 时非常有用。
    /// 也能用 `Cmd+Shift+D` 快捷键直接 dump。
    private var uiRegistrySection: some View {
        let elements = UIRegistry.shared.sortedElements()
        let inspectorOn = UIRegistry.shared.isInspectorEnabled
        return GroupBox("UI 元素 (\(elements.count))") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button(inspectorOn ? "关闭 Inspector Overlay" : "打开 Inspector Overlay") {
                        UIRegistry.shared.toggleInspector(reason: "diagnostics_panel")
                    }
                    .stitchHoverDimming()
                    Button("Dump 到 trace") {
                        UITrace.snapshot(reason: "diagnostics_panel")
                    }
                    .stitchHoverDimming()
                    Button("复制报告到剪贴板") {
                        copyRegistrySnapshotToPasteboard()
                    }
                    .stitchHoverDimming()
                    Spacer()
                    Text("⌘⇧U Inspector · ⌘⇧D Dump")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if elements.isEmpty {
                    Text("尚无元素注册（确保 `.lumaTrack(...)` 已挂上对应视图，且视图已 onAppear）")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(elements, id: \.id) { element in
                        uiElementRow(element)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func uiElementRow(_ element: UIElementInfo) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(element.id)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 320, alignment: .leading)
                .textSelection(.enabled)
            Text(element.kind)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(formatRect(element.frameInWindow))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 2)
        .stitchAdaptiveListRowHover()
    }

    private func formatRect(_ rect: CGRect) -> String {
        String(
            format: "x=%.0f y=%.0f w=%.0f h=%.0f",
            rect.minX, rect.minY, rect.width, rect.height
        )
    }

    private func copyRegistrySnapshotToPasteboard() {
        let report = UIRegistry.shared.textualReport(contextMetadata: [
            "project_name": store.projectName,
            "selected_group_id": store.selectedGroupID?.uuidString ?? "all",
            "selected_asset_id": store.selectedAssetID?.uuidString ?? "none",
            "visible_asset_count": String(store.visibleAssets.count)
        ])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        RuntimeTrace.event(
            "ui_inspector_report_copied",
            category: "ui",
            metadata: [
                "source": "diagnostics_panel",
                "element_count": String(UIRegistry.shared.elements.count),
                "byte_length": String(report.utf8.count)
            ]
        )
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
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stitchAdaptiveListRowHover()
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
                    .stitchHoverDimming()
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .stitchHoverDimming()
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
