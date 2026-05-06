import AppKit
import SwiftUI

struct ActionPanelView: View {
    @Bindable var store: LibraryStore
    var workspace: ExpeditionWorkspaceStore?
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKind: ActionKind = .exportToFolder
    @State private var showDestructiveConfirm = false
    @State private var folderTemplate: FolderTemplate = .byDate
    @State private var fileNamingRule: FileNamingRule = .original
    @State private var customNamingTemplate: String = "{date}_{original}"
    @State private var writeXmp: Bool = true
    @State private var outputPath: URL?
    @State private var selectedAlbumId: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                actionTypePicker
                configurationSection
                previewStats
            }
            .navigationTitle("Actions")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("执行") { handleExecute() }
                        .disabled(store.isActionRunning || !isValid)
                }
            }
            .confirmationDialog("确认操作", isPresented: $showDestructiveConfirm) {
                Button("确认执行", role: .destructive) { executeAction() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(destructiveMessage)
            }
            .alert("操作失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    // MARK: - Action Type Picker

    private var actionTypePicker: some View {
        Section("操作类型") {
            Picker("类型", selection: $selectedKind) {
                Text("导出到文件夹").tag(ActionKind.exportToFolder)
                Text("归档视频").tag(ActionKind.archiveVideo)
                Text("低清保留").tag(ActionKind.archiveLowres)
                Text("仅标记归档").tag(ActionKind.archiveMarkerOnly)
                Text("同步相册到 Photos").tag(ActionKind.syncAlbumToPhotos)
            }
        }
    }

    // MARK: - Configuration Section

    @ViewBuilder
    private var configurationSection: some View {
        switch selectedKind {
        case .exportToFolder:
            exportToFolderConfig
        case .archiveVideo:
            archiveVideoConfig
        case .archiveLowres:
            archiveLowresConfig
        case .archiveMarkerOnly:
            markerOnlyConfig
        case .syncAlbumToPhotos:
            syncToPhotosConfig
        }
    }

    private var exportToFolderConfig: some View {
        Section("导出配置") {
            Picker("目录模板", selection: $folderTemplate) {
                Text("按日期").tag(FolderTemplate.byDate)
                Text("按场景").tag(FolderTemplate.byGroup)
                Text("按评分").tag(FolderTemplate.byRating)
            }
            Picker("文件命名", selection: $fileNamingRule) {
                Text("保留原名").tag(FileNamingRule.original)
                Text("日期前缀").tag(FileNamingRule.datePrefix)
                Text("自定义模板").tag(FileNamingRule.custom)
            }
            if fileNamingRule == .custom {
                TextField("模板", text: $customNamingTemplate)
                Text("可用变量：{original} {date} {datetime} {group} {seq}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Toggle("附带 XMP Sidecar", isOn: $writeXmp)
            pathRow(
                title: "输出目录",
                path: outputPath?.path(percentEncoded: false) ?? "未选择"
            ) {
                chooseOutputFolder()
            }
        }
    }

    private var archiveVideoConfig: some View {
        Section("归档视频") {
            Text("将所有未选照片合并为一个回忆视频。输出到 Application Support/Archives 目录。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var archiveLowresConfig: some View {
        Section("低清保留") {
            Text("将未选照片缩小为低分辨率 JPEG 保存，释放原图空间。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var markerOnlyConfig: some View {
        Section("仅标记归档") {
            Text("不移动或复制文件，仅在数据库中标记这些资产为已归档。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var syncToPhotosConfig: some View {
        Section("同步到 Photos") {
            let syncable = store.albums.filter { $0.kind == .manual || $0.kind == .photosBacked }
            if syncable.isEmpty {
                Text("暂无可同步的相册")
                    .foregroundStyle(.secondary)
            } else {
                Picker("目标相册", selection: $selectedAlbumId) {
                    Text("请选择").tag(nil as UUID?)
                    ForEach(syncable) { album in
                        Text(album.name).tag(album.id as UUID?)
                    }
                }
            }
        }
    }

    // MARK: - Preview Stats

    private var previewStats: some View {
        Section("当前批次") {
            let (pickedCount, archiveCount) = assetCounts
            LabeledContent("目标资产", value: "\(targetCount) 张")
            if selectedKind == .exportToFolder {
                LabeledContent("已选照片", value: "\(pickedCount) 张")
            }
            if selectedKind.isArchiveKind {
                LabeledContent("可归档照片", value: "\(archiveCount) 张")
            }
        }
    }

    private var assetCounts: (picked: Int, archive: Int) {
        guard let ws = workspace else { return (0, 0) }
        return (ws.pickedCount, ws.archiveableAssets.count)
    }

    private var targetCount: Int {
        switch selectedKind {
        case .exportToFolder:
            return workspace?.pickedCount ?? 0
        case .archiveVideo, .archiveLowres, .archiveMarkerOnly:
            return workspace?.archiveableAssets.count ?? 0
        case .syncAlbumToPhotos:
            if let aid = selectedAlbumId {
                return store.albumAssetCounts[aid] ?? 0
            }
            return 0
        }
    }

    private var isValid: Bool {
        switch selectedKind {
        case .exportToFolder:
            return outputPath != nil && (workspace?.pickedCount ?? 0) > 0
        case .archiveVideo, .archiveLowres, .archiveMarkerOnly:
            return (workspace?.archiveableAssets.count ?? 0) > 0
        case .syncAlbumToPhotos:
            return selectedAlbumId != nil
        }
    }

    private var destructiveMessage: String {
        switch selectedKind {
        case .archiveMarkerOnly:
            return "这会将 \(workspace?.archiveableAssets.count ?? 0) 张照片标记为已归档。不会删除原始文件。"
        case .archiveVideo, .archiveLowres:
            return "这会将 \(workspace?.archiveableAssets.count ?? 0) 张未选照片归档处理，处理后将标记为已归档。"
        default:
            return ""
        }
    }

    // MARK: - Actions

    private func handleExecute() {
        if selectedKind.isArchiveKind {
            showDestructiveConfirm = true
        } else {
            executeAction()
        }
    }

    private func executeAction() {
        Task {
            do {
                let expId = workspace?.currentExpedition?.id
                var targetIds: [UUID] = []

                switch selectedKind {
                case .exportToFolder:
                    targetIds = workspace?.expeditionAssets
                        .filter { $0.decision == .picked }
                        .map(\.assetId) ?? []
                    var opts = ExportOptions.default
                    opts.outputPath = outputPath
                    opts.folderTemplate = folderTemplate
                    opts.fileNamingRule = fileNamingRule
                    opts.customNamingTemplate = customNamingTemplate
                    opts.writeXmpSidecar = writeXmp
                    try await store.submitAndRunAction(
                        kind: .exportToFolder,
                        expeditionId: expId,
                        targetAssetIds: targetIds,
                        exportOptions: opts
                    )
                case .archiveVideo, .archiveLowres, .archiveMarkerOnly:
                    targetIds = workspace?.archiveableAssets.map(\.assetId) ?? []
                    try await store.submitAndRunAction(
                        kind: selectedKind,
                        expeditionId: expId,
                        targetAssetIds: targetIds
                    )
                case .syncAlbumToPhotos:
                    try await store.submitAndRunAction(
                        kind: .syncAlbumToPhotos,
                        albumId: selectedAlbumId
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "选择"
        if panel.runModal() == .OK {
            outputPath = panel.url
        }
    }

    private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Button("选择…", action: action)
                    .buttonStyle(.borderless)
            }
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private extension ActionKind {
    var isArchiveKind: Bool {
        switch self {
        case .archiveVideo, .archiveLowres, .archiveMarkerOnly: return true
        default: return false
        }
    }
}
