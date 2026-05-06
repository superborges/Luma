import SwiftUI

/// V4 选片工作台：基于 ExpeditionWorkspaceStore 驱动。
/// P1F5 完成导航结构后由 ContentView 路由至此。
struct ExpeditionCullingView: View {
    @Bindable var workspace: ExpeditionWorkspaceStore
    var libraryStore: LibraryStore?
    @State private var pendingRenameGroupId: UUID?
    @State private var pendingRenameText: String = ""
    @State private var showActionPanel = false

    var body: some View {
        VStack(spacing: 0) {
            expeditionHeader
            HStack(spacing: 0) {
                navigationSidebar
                    .frame(width: 264)
                centerPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                detailSidebar
                    .frame(width: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomBar
        }
        .background(StitchTheme.surface)
        .background(
            KeyboardShortcutBridge { event in
                handleKeyEvent(event)
            }
        )
        .alert("重命名分组", isPresented: Binding(
            get: { pendingRenameGroupId != nil },
            set: { if !$0 { pendingRenameGroupId = nil } }
        )) {
            TextField("分组名称", text: $pendingRenameText)
            Button("确认") {
                if let gid = pendingRenameGroupId, !pendingRenameText.isEmpty {
                    try? workspace.renameGroup(groupId: gid, newName: pendingRenameText)
                }
                pendingRenameGroupId = nil
            }
            Button("取消", role: .cancel) { pendingRenameGroupId = nil }
        }
        .sheet(isPresented: $showActionPanel) {
            if let ls = libraryStore {
                ActionPanelView(store: ls, workspace: workspace)
            }
        }
        .sheet(isPresented: Binding(
            get: { libraryStore?.lastActionResult != nil },
            set: { if !$0 { libraryStore?.dismissActionResult() } }
        )) {
            if let ls = libraryStore, let result = ls.lastActionResult {
                ActionResultView(store: ls, result: result)
            }
        }
        .overlay(alignment: .bottom) {
            if let ls = libraryStore, ls.isActionRunning {
                ActionProgressView(
                    progress: ls.currentActionProgress,
                    jobKind: ls.currentActionJobKind
                )
                .padding()
            }
        }
    }

    // MARK: - Header

    private var expeditionHeader: some View {
        HStack(spacing: 16) {
            Button {
                workspace.closeExpedition()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 12, weight: .semibold))
                    Text("全部旅程")
                        .font(StitchTypography.font(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(white: 0.75))
            }
            .buttonStyle(.plain)

            if let expedition = workspace.currentExpedition {
                Text(expedition.name)
                    .foregroundStyle(Color(white: 0.93))
                    .fontWeight(.semibold)
                    .font(StitchTypography.font(size: 12, weight: .regular))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text("\(workspace.pickedCount)")
                    .foregroundStyle(Color.green.opacity(0.8))
                Text("已选")
                    .foregroundStyle(Color(white: 0.5))
                Text("·")
                    .foregroundStyle(Color(white: 0.3))
                Text("\(workspace.rejectedCount)")
                    .foregroundStyle(Color.red.opacity(0.7))
                Text("未选")
                    .foregroundStyle(Color(white: 0.5))
                Text("·")
                    .foregroundStyle(Color(white: 0.3))
                Text("\(workspace.pendingCount)")
                    .foregroundStyle(Color(white: 0.5))
                Text("未审")
                    .foregroundStyle(Color(white: 0.5))
            }
            .font(.system(size: 11))

            Button {
                showActionPanel = true
            } label: {
                Label("Actions", systemImage: "bolt.circle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.75))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(StitchTheme.topBarBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    // MARK: - Left Sidebar

    private var navigationSidebar: some View {
        VStack(spacing: 0) {
            smartFilterSection
            Divider().background(Color.white.opacity(0.05))
            groupListSection
        }
        .background(StitchTheme.sidebarBackground)
    }

    private var smartFilterSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("筛选")
                .font(StitchTypography.font(size: 10, weight: .bold))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(1.2)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ForEach(SmartFilter.allCases) { filter in
                let count = filterCount(filter)
                Button {
                    workspace.activeFilter = filter
                    workspace.selectGroup(id: nil)
                } label: {
                    HStack {
                        Text(filter.label)
                            .font(StitchTypography.font(size: 12, weight: .medium))
                        Spacer()
                        Text("\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Color(white: 0.5))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        workspace.activeFilter == filter && workspace.selectedGroupId == nil
                            ? StitchTheme.sidebarActiveBackground
                            : Color.clear
                    )
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(
                    workspace.activeFilter == filter && workspace.selectedGroupId == nil
                        ? StitchTheme.sidebarActiveText
                        : StitchTheme.sidebarInactiveText
                )
            }
        }
        .padding(.bottom, 8)
    }

    private var groupListSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("分组")
                .font(StitchTypography.font(size: 10, weight: .bold))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(1.2)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(workspace.groups) { group in
                        Button {
                            workspace.activeFilter = .all
                            workspace.selectGroup(id: group.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name)
                                        .font(StitchTypography.font(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text("\(group.assetCount) 张")
                                        if group.pickedCount > 0 {
                                            Text("✓\(group.pickedCount)")
                                                .foregroundStyle(Color.green.opacity(0.7))
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(white: 0.5))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(
                                workspace.selectedGroupId == group.id
                                    ? StitchTheme.sidebarActiveBackground
                                    : Color.clear
                            )
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            workspace.selectedGroupId == group.id
                                ? StitchTheme.sidebarActiveText
                                : StitchTheme.sidebarInactiveText
                        )
                        .contextMenu { groupContextMenu(group) }
                    }
                }
            }
        }
    }

    // MARK: - Center

    private var centerPreview: some View {
        Group {
            if let selected = workspace.selectedAsset {
                VStack(spacing: 0) {
                    ZStack(alignment: .top) {
                        DisplayImageView(asset: selected.masterAsset)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if selected.isReferenceInvalid {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                Text("引用失效 — 原始文件不存在")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.red.opacity(0.8), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .padding(.top, 12)
                        }
                    }

                    decisionBadge(for: selected)
                        .padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(white: 0.3))
                    Text(workspace.totalCount == 0 ? "暂无照片" : "请选择一张照片")
                        .foregroundStyle(Color(white: 0.5))
                }
            }
        }
        .background(StitchTheme.background)
    }

    private func decisionBadge(for asset: ExpeditionAssetWithMaster) -> some View {
        HStack(spacing: 8) {
            switch asset.decision {
            case .picked:
                Label("已选", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .rejected:
                Label("未选", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .pending:
                Label("未审", systemImage: "questionmark.circle")
                    .foregroundStyle(Color(white: 0.5))
            }

            if let rating = asset.rating {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundStyle(star <= rating ? .yellow : Color(white: 0.3))
                    }
                }
            }
        }
        .font(.system(size: 12, weight: .medium))
    }

    // MARK: - Right Sidebar

    private var detailSidebar: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let asset = workspace.selectedAsset {
                    thumbnailStrip
                    exifCard(for: asset)
                    scoreCard(for: asset)
                } else {
                    Text("选择一张照片查看详情")
                        .foregroundStyle(Color(white: 0.4))
                        .padding(.top, 40)
                }
            }
            .padding(16)
        }
        .background(StitchTheme.sidebarBackground)
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 4) {
                ForEach(workspace.visibleAssets) { asset in
                    Button {
                        workspace.selectAsset(id: asset.assetId)
                    } label: {
                        ThumbnailView(masterAsset: asset.masterAsset)
                            .frame(width: 60, height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(
                                        asset.assetId == workspace.selectedAssetId
                                            ? StitchTheme.primary
                                            : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .overlay(alignment: .bottomTrailing) {
                                decisionDot(asset.decision)
                                    .padding(3)
                            }
                            .overlay(alignment: .topLeading) {
                                if asset.isReferenceInvalid {
                                    HStack(spacing: 2) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 8))
                                        Text("引用失效")
                                            .font(.system(size: 7, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                                    .padding(2)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu { photoContextMenu(asset) }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 68)
    }

    private func decisionDot(_ decision: Decision) -> some View {
        Circle()
            .fill(decision == .picked ? .green : decision == .rejected ? .red : Color(white: 0.3))
            .frame(width: 6, height: 6)
    }

    private func exifCard(for asset: ExpeditionAssetWithMaster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXIF")
                .font(StitchTypography.font(size: 10, weight: .bold))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(1.2)

            let ma = asset.masterAsset
            if let date = ma.captureDate {
                infoRow("日期", DateFormatter.lumaShort.string(from: date))
            }
            if let meta = ma.metadata {
                if let cam = meta.cameraModel { infoRow("相机", cam) }
                if let lens = meta.lensModel { infoRow("镜头", lens) }
                if let fl = meta.focalLength { infoRow("焦距", "\(fl)mm") }
                if let ap = meta.aperture { infoRow("光圈", "ƒ/\(String(format: "%.1f", ap))") }
                if let iso = meta.iso { infoRow("ISO", "\(iso)") }
                if meta.imageWidth > 0, meta.imageHeight > 0 {
                    infoRow("尺寸", "\(meta.imageWidth)×\(meta.imageHeight)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(StitchTheme.surfaceContainer.opacity(0.6))
        .cornerRadius(8)
    }

    private func scoreCard(for asset: ExpeditionAssetWithMaster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI 评分")
                .font(StitchTypography.font(size: 10, weight: .bold))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(1.2)

            if let score = asset.latestScore {
                if let overall = score.overall {
                    HStack {
                        Text("综合")
                        Spacer()
                        Text("\(overall)")
                            .fontWeight(.bold)
                            .foregroundStyle(overall >= 75 ? .green : overall >= 50 ? .yellow : .red)
                    }
                }
                if let c = score.composition { scoreRow("构图", c) }
                if let e = score.exposure { scoreRow("曝光", e) }
                if let co = score.color { scoreRow("色彩", co) }
                if let s = score.sharpness { scoreRow("锐度", s) }
                if let st = score.story { scoreRow("故事", st) }
                if let comment = score.comment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.6))
                        .padding(.top, 4)
                }
            } else {
                Text("暂无评分")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(StitchTheme.surfaceContainer.opacity(0.6))
        .cornerRadius(8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 24) {
            HStack(spacing: 12) {
                actionButton("已选 (P)", systemImage: "checkmark.circle.fill", color: .green) {
                    guard let id = workspace.selectedAssetId else { return }
                    try? workspace.setDecision(assetId: id, decision: .picked)
                }
                actionButton("未选 (X)", systemImage: "xmark.circle.fill", color: .red) {
                    guard let id = workspace.selectedAssetId else { return }
                    try? workspace.setDecision(assetId: id, decision: .rejected)
                }
                actionButton("未审 (U)", systemImage: "questionmark.circle", color: Color(white: 0.5)) {
                    guard let id = workspace.selectedAssetId else { return }
                    try? workspace.setDecision(assetId: id, decision: .pending)
                }
            }

            Divider().frame(height: 20).background(Color.white.opacity(0.1))

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        guard let id = workspace.selectedAssetId else { return }
                        try? workspace.setRating(assetId: id, rating: rating)
                    } label: {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(
                                (workspace.selectedAsset?.rating ?? 0) >= rating
                                    ? .yellow
                                    : Color(white: 0.25)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().frame(height: 20).background(Color.white.opacity(0.1))

            HStack(spacing: 8) {
                Button {
                    workspace.moveSelection(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(white: 0.6))

                if let asset = workspace.selectedAsset {
                    let visible = workspace.visibleAssets
                    let idx = visible.firstIndex(where: { $0.assetId == asset.assetId }).map { $0 + 1 } ?? 0
                    Text("\(idx) / \(visible.count)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Color(white: 0.5))
                }

                Button {
                    workspace.moveSelection(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(white: 0.6))
            }

            Spacer()

            progressSummary
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .background(StitchTheme.topBarBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    private var progressSummary: some View {
        let total = workspace.totalCount
        let decided = workspace.pickedCount + workspace.rejectedCount
        let fraction = total > 0 ? Double(decided) / Double(total) : 0

        return HStack(spacing: 8) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .frame(width: 100)
                .tint(StitchTheme.primary)

            Text("\(Int(fraction * 100))%")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.5))
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func groupContextMenu(_ group: PhotoGroupWithAssets) -> some View {
        Button("重命名…") {
            pendingRenameGroupId = group.id
            pendingRenameText = group.name
        }
        Divider()
        if workspace.groups.count >= 2 {
            Button("与上一组合并") {
                guard let idx = workspace.groups.firstIndex(where: { $0.id == group.id }),
                      idx > 0 else { return }
                let prevId = workspace.groups[idx - 1].id
                try? workspace.mergeGroups(ids: [prevId, group.id])
            }
        }
        Button("拆分选中照片为新组") {
            guard let sel = workspace.selectedAssetId else { return }
            try? workspace.splitGroup(groupId: group.id, assetIds: [sel])
        }
        .disabled(workspace.selectedAssetId == nil)
        Divider()
        Button("采纳 AI 推荐") {
            try? workspace.applyAIRecommendations(groupId: group.id)
        }
    }

    @ViewBuilder
    private func photoContextMenu(_ asset: ExpeditionAssetWithMaster) -> some View {
        Button("标记已选 (P)") { try? workspace.setDecision(assetId: asset.assetId, decision: .picked) }
        Button("标记未选 (X)") { try? workspace.setDecision(assetId: asset.assetId, decision: .rejected) }
        Button("标记未审 (U)") { try? workspace.setDecision(assetId: asset.assetId, decision: .pending) }
        Divider()
        if let groupId = workspace.selectedGroupId {
            Button("设为组封面") {
                try? workspace.setGroupCover(groupId: groupId, assetId: asset.assetId)
            }
            Button("从组中移除") {
                try? workspace.removeFromGroup(groupId: groupId, assetIds: [asset.assetId])
            }
        }
        if workspace.groups.count > 1 {
            Menu("移动到组…") {
                ForEach(workspace.groups.filter({ $0.id != workspace.selectedGroupId })) { targetGroup in
                    Button(targetGroup.name) {
                        try? workspace.moveToGroup(assetIds: [asset.assetId], targetGroupId: targetGroup.id)
                    }
                }
            }
        }
        if let ls = libraryStore, !ls.albums.isEmpty {
            Divider()
            Menu("添加到相册…") {
                ForEach(ls.albums.filter({ $0.kind == .manual || $0.kind == .photosBacked })) { album in
                    Button(album.name) {
                        try? ls.addAssetsToAlbum(albumId: album.id, assetIds: [asset.assetId])
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func actionButton(
        _ title: String, systemImage: String, color: Color, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color(white: 0.5))
            Spacer()
            Text(value)
                .foregroundStyle(Color(white: 0.85))
        }
        .font(.system(size: 11))
    }

    private func scoreRow(_ label: String, _ value: Int) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color(white: 0.5))
            Spacer()
            Text("\(value)")
                .foregroundStyle(value >= 75 ? .green : value >= 50 ? .yellow : .red)
        }
        .font(.system(size: 11))
    }

    private func filterCount(_ filter: SmartFilter) -> Int {
        switch filter {
        case .all: return workspace.totalCount
        case .aiRecommended: return workspace.expeditionAssets.count(where: { $0.decision == .pending && $0.isRecommended })
        case .picked: return workspace.pickedCount
        case .rejected: return workspace.rejectedCount
        case .pending: return workspace.pendingCount
        case .problematic: return workspace.expeditionAssets.count(where: { $0.effectiveRating <= 2 })
        }
    }

    // MARK: - Keyboard

    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        if let responder = NSApp.keyWindow?.firstResponder,
           responder is NSTextView || responder is NSTextField {
            return false
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let characters = event.charactersIgnoringModifiers?.lowercased() ?? ""

        // Cmd+A: show all photos overview
        if modifiers == .command, characters == "a" {
            workspace.selectAllPhotosOverview()
            return true
        }

        guard modifiers.isEmpty else { return false }

        switch event.keyCode {
        case 123: // left arrow
            workspace.moveSelection(by: -1)
            return true
        case 124: // right arrow
            workspace.moveSelection(by: 1)
            return true
        case 48: // Tab → jump to next group
            jumpToNextGroup()
            return true
        case 49: // Space → clear to pending (V3 parity)
            guard let id = workspace.selectedAssetId else { return false }
            try? workspace.setDecision(assetId: id, decision: .pending)
            return true
        default:
            break
        }

        switch characters {
        case "p":
            guard let id = workspace.selectedAssetId else { return false }
            try? workspace.setDecision(assetId: id, decision: .picked)
            return true
        case "x":
            guard let id = workspace.selectedAssetId else { return false }
            try? workspace.setDecision(assetId: id, decision: .rejected)
            return true
        case "u":
            guard let id = workspace.selectedAssetId else { return false }
            try? workspace.setDecision(assetId: id, decision: .pending)
            return true
        case "1", "2", "3", "4", "5":
            if let rating = Int(characters), let id = workspace.selectedAssetId {
                try? workspace.setRating(assetId: id, rating: rating)
                return true
            }
        default:
            break
        }
        return false
    }

    private func jumpToNextGroup() {
        let groups = workspace.groups
        guard !groups.isEmpty else { return }
        if let currentId = workspace.selectedGroupId,
           let idx = groups.firstIndex(where: { $0.id == currentId }) {
            let nextIdx = (idx + 1) % groups.count
            workspace.selectGroup(id: groups[nextIdx].id)
        } else {
            workspace.selectGroup(id: groups[0].id)
        }
    }
}

// MARK: - Sub-views wrapping MasterAsset

private struct DisplayImageView: View {
    let asset: MasterAsset
    @State private var photoKitImage: NSImage?

    var body: some View {
        if asset.storageMode == .externalReference {
            photoKitContent(contentMode: .fit)
                .task(id: asset.externalIdentifier) {
                    let provider = AssetImageProviderFactory.provider(for: asset.storageMode)
                    photoKitImage = await provider.preview(for: asset, size: CGSize(width: 1600, height: 1600))
                }
        } else if let url = asset.existingImageFileURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fit)
                default:
                    Color(white: 0.1)
                }
            }
        } else {
            imagePlaceholder
        }
    }

    @ViewBuilder
    private func photoKitContent(contentMode: ContentMode) -> some View {
        if let img = photoKitImage {
            Image(nsImage: img).resizable().aspectRatio(contentMode: contentMode)
        } else {
            Color(white: 0.1).overlay { ProgressView().scaleEffect(0.6) }
        }
    }

    private var imagePlaceholder: some View {
        Color(white: 0.1).overlay {
            Image(systemName: "photo").foregroundStyle(Color(white: 0.3))
        }
    }
}

private struct ThumbnailView: View {
    let masterAsset: MasterAsset
    @State private var photoKitImage: NSImage?

    var body: some View {
        if masterAsset.storageMode == .externalReference {
            photoKitThumbnail
                .cornerRadius(4)
                .task(id: masterAsset.externalIdentifier) {
                    let provider = AssetImageProviderFactory.provider(for: masterAsset.storageMode)
                    photoKitImage = await provider.thumbnail(for: masterAsset, size: CGSize(width: 240, height: 240))
                }
        } else if let url = masterAsset.thumbnailCacheURL ?? masterAsset.previewURL ?? masterAsset.existingImageFileURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill).clipped()
                default:
                    Color(white: 0.15)
                }
            }
            .cornerRadius(4)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.15))
        }
    }

    @ViewBuilder
    private var photoKitThumbnail: some View {
        if let img = photoKitImage {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).clipped()
        } else {
            Color(white: 0.15).overlay { ProgressView().scaleEffect(0.5) }
        }
    }
}

private extension DateFormatter {
    static let lumaShort: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
}
