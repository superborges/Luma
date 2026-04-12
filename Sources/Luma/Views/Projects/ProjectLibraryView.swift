import SwiftUI

struct ProjectLibraryView: View {
    @Bindable var store: ProjectStore

    @State private var selectedProjectID: URL?
    @State private var projectPendingDeletion: ProjectSummary?

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        Group {
            switch store.projectLibraryKind {
            case .management:
                managementBody
            case .allExpeditionsGallery(let layout):
                allExpeditionsGalleryBody(layout: layout)
            }
        }
        .frame(minWidth: minWidth, minHeight: minHeight)
        .onAppear {
            store.refreshProjectSummaries()
            syncSelection()
        }
        .alert(
            "删除项目？",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { summary in
            Button("删除", role: .destructive) {
                store.deleteProject(summary)
                projectPendingDeletion = nil
                syncSelection()
            }
            Button("取消", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: { summary in
            Text("将删除“\(summary.name)”及其本地缓存文件。此操作不可撤回。")
        }
    }

    private var minWidth: CGFloat {
        switch store.projectLibraryKind {
        case .management: 860
        case .allExpeditionsGallery: 720
        }
    }

    private var minHeight: CGFloat {
        switch store.projectLibraryKind {
        case .management: 520
        case .allExpeditionsGallery: 480
        }
    }

    // MARK: - Management (legacy split view)

    private var managementBody: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目库")
                        .font(.title2.weight(.semibold))
                    Text("切换、刷新或删除本地项目。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") {
                    store.refreshProjectSummaries()
                    syncSelection()
                }
                .stitchHoverDimming()
                Button("关闭") {
                    store.closeProjectLibrary()
                }
                .stitchHoverDimming()
            }
            .padding(20)

            Divider()

            if store.projectSummaries.isEmpty {
                ContentUnavailableView(
                    "暂无项目",
                    systemImage: "books.vertical",
                    description: Text("先导入一个照片文件夹、SD 卡或 iPhone 项目。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedProjectID) {
                        ForEach(store.projectSummaries) { summary in
                            ProjectRow(summary: summary)
                                .tag(summary.id)
                        }
                    }
                    .frame(minWidth: 320)

                    Divider()

                    Group {
                        if let selectedSummary {
                            detailView(for: selectedSummary)
                        } else {
                            ContentUnavailableView(
                                "未选择项目",
                                systemImage: "folder",
                                description: Text("从左侧选择一个项目查看详情。")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                }
            }
        }
    }

    // MARK: - All Expeditions Gallery

    private func allExpeditionsGalleryBody(layout: ExpeditionsGalleryLayout) -> some View {
        NavigationStack {
            Group {
                if store.projectSummaries.isEmpty {
                    ContentUnavailableView(
                        "No expeditions",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Create a project or import to see expeditions here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if layout == .grid {
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16),
                            ],
                            spacing: 16
                        ) {
                            ForEach(store.projectSummaries) { summary in
                                galleryGridCell(summary)
                            }
                        }
                        .padding(24)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(store.projectSummaries.enumerated()), id: \.element.id) { idx, summary in
                                galleryListRow(summary, showTopBorder: idx > 0)
                            }
                        }
                        .background(StitchTheme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(24)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StitchTheme.background)
            .navigationTitle("Luma - All Expeditions Gallery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        store.closeProjectLibrary()
                    }
                    .stitchHoverDimming()
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("", selection: galleryLayoutBinding) {
                        Text("Grid").tag(ExpeditionsGalleryLayout.grid)
                        Text("List").tag(ExpeditionsGalleryLayout.list)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
        }
    }

    private var galleryLayoutBinding: Binding<ExpeditionsGalleryLayout> {
        Binding(
            get: {
                if case .allExpeditionsGallery(let layout) = store.projectLibraryKind {
                    return layout
                }
                return .list
            },
            set: { newValue in
                store.projectLibraryKind = .allExpeditionsGallery(layout: newValue)
            }
        )
    }

    private func galleryGridCell(_ summary: ProjectSummary) -> some View {
        Button {
            if case .ready = summary.state { store.openProject(summary) }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(galleryThumbFill(summary.id))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        LinearGradient(
                            colors: [
                                StitchTheme.surfaceContainerLowest.opacity(0.75),
                                Color.clear,
                            ],
                            startPoint: .bottom,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(StitchTypography.listRowTitle)
                            .foregroundStyle(StitchTheme.onSurface)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(gallerySubtitle(for: summary))
                            .font(StitchTypography.secondaryMeta)
                            .foregroundStyle(StitchTheme.outline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ExpeditionMoreVertIndicator()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StitchTheme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .stitchSubtleCardHover(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    private func galleryListRow(_ summary: ProjectSummary, showTopBorder: Bool) -> some View {
        ZStack(alignment: .trailing) {
            Button {
                if case .ready = summary.state { store.openProject(summary) }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(galleryThumbFill(summary.id))
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(StitchTypography.listRowTitle)
                            .foregroundStyle(StitchTheme.onSurface)
                            .lineLimit(2)
                        Text(galleryRowMeta(for: summary))
                            .font(StitchTypography.listRowMeta)
                            .foregroundStyle(StitchTheme.outline)
                            .textCase(.uppercase)
                            .tracking(1.2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 2) {
                        switch summary.state {
                        case .ready(let n, _):
                            Text("\(n) RAW")
                                .font(StitchTypography.listRawMono)
                                .foregroundStyle(StitchTheme.onSurface)
                            Text("—")
                                .font(StitchTypography.listSecondaryLine)
                                .foregroundStyle(StitchTheme.outline)
                        case .unavailable(let reason):
                            Text("—")
                                .font(StitchTypography.listRawMono)
                                .foregroundStyle(StitchTheme.outline)
                            Text(reason)
                                .font(StitchTypography.listSecondaryLine)
                                .foregroundStyle(StitchTheme.outline)
                                .lineLimit(1)
                        }
                    }
                    .frame(minWidth: 72, alignment: .trailing)
                    Color.clear.frame(width: 32)
                }
                .padding(.leading, 16)
                .padding(.vertical, 16)
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .stitchListRowHoverBackground()
            }
            .buttonStyle(.plain)
            ExpeditionMoreVertIndicator()
                .padding(.trailing, 14)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            if showTopBorder {
                Rectangle()
                    .fill(StitchTheme.outlineVariant.opacity(0.1))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func galleryThumbFill(_ id: URL) -> LinearGradient {
        let h = abs(id.hashValue % 360)
        let c1 = Color(hue: Double(h) / 360.0, saturation: 0.4, brightness: 0.35)
        let c2 = Color(hue: Double((h + 50) % 360) / 360.0, saturation: 0.5, brightness: 0.2)
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func gallerySubtitle(for summary: ProjectSummary) -> String {
        let d = summary.createdAt.formatted(date: .abbreviated, time: .omitted)
        switch summary.state {
        case .ready(let n, _):
            return "\(d) • \(n) items"
        case .unavailable(let r):
            return r
        }
    }

    private func galleryRowMeta(for summary: ProjectSummary) -> String {
        let m = summary.createdAt.formatted(.dateTime.month(.abbreviated).year())
        return "Project • \(m)"
    }

    private var selectedSummary: ProjectSummary? {
        if let selectedProjectID {
            return store.projectSummaries.first(where: { $0.id == selectedProjectID })
        }
        return nil
    }

    @ViewBuilder
    private func detailView(for summary: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.name)
                    .font(.title3.weight(.semibold))
                if summary.isCurrent {
                    Text("当前项目")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }

            LabeledContent("创建时间", value: summary.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("照片数量", value: summary.assetCountDescription)
            LabeledContent("分组数量", value: summary.groupCountDescription)
            LabeledContent("目录", value: summary.directory.path)

            if case .unavailable(let reason) = summary.state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("打开项目") {
                    store.openProject(summary)
                }
                .disabled(summary.isCurrent)
                .stitchHoverDimming()

                Button("删除项目", role: .destructive) {
                    projectPendingDeletion = summary
                }
                .stitchHoverDimming(opacity: 0.88)

                Spacer()
            }
        }
    }

    private func syncSelection() {
        if let current = store.projectSummaries.first(where: \.isCurrent) {
            selectedProjectID = current.id
        } else {
            selectedProjectID = store.projectSummaries.first?.id
        }
    }
}

private struct ProjectRow: View {
    let summary: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.name)
                    .font(.headline)
                    .lineLimit(1)
                if summary.isCurrent {
                    Text("当前")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }

            Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(summary.assetCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.groupCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(summary.directory.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
