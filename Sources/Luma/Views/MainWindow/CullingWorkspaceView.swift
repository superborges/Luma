import AppKit
import SwiftUI

/// 选片页主视图（方案丁）。
///
/// 三栏 + 底栏布局：
/// - 左：Smart Groups 智能分组列表，顶部含「全部照片」概览行。
/// - 中：默认大图；选中 Burst 时自动变成 N×M 网格；网格内双击 / Enter 切换为强制大图。
/// - 右：当前 Smart Group 内全部照片（Burst 折叠成 1 张代表 + 角标），下方固定 EXIF 卡。
/// - 底：Pick / Reject / Pending + 1–5 评星 + 上一张/下一张箭头 + Session 决策进度。
///
/// v1 已彻底移除 AI 视觉（confidence/AI Match/Auto Analysis/AI Best Pick）和批量操作
/// （Pick All / 全部采纳推荐 / 连拍择优 / Reject Rest）；模型层 `aiScore` 字段保留但 UI 不展示。
struct CullingWorkspaceView: View {
    @Bindable var store: ProjectStore
    @Environment(\.openSettings) private var openSettings

    /// 选中的是 Burst 时，是否被用户强制放大成大图模式（双击 / Enter 触发）。
    /// 切换分组 / 切换非 burst cell 时自动复位。
    @State private var burstFocusOverride: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            cullingHeader
            HStack(spacing: 0) {
                smartGroupsSidebar
                    .frame(width: 264)
                centerArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightSidebar
                    .frame(width: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottomActionBar
        }
        .background(StitchTheme.surface)
        .onChange(of: store.selectedGroupID) { _, _ in
            burstFocusOverride = false
        }
        .onChange(of: currentBurstID) { _, _ in
            burstFocusOverride = false
        }
    }

    // MARK: - State helpers

    /// 当前选中是 Burst（≥2 张）且未被用户强制单图。
    private var isCenterShowingBurstGrid: Bool {
        store.selectedBurstContext != nil && !burstFocusOverride
    }

    /// 用于驱动 `burstFocusOverride` 在切 burst 时复位的 onChange 键。
    private var currentBurstID: UUID? {
        store.selectedBurstContext?.burst.id
    }

    /// 右栏 cell 的稳定 tracking id：单图按 asset id，连拍按 burst id（burst 折叠成 1 个 cell）。
    private func rightCellTrackingID(_ cell: SmartGroupCell) -> String {
        switch cell {
        case .single(let asset):
            return "culling.right.cell.single[\(asset.id.uuidString)]"
        case .burst(let burst):
            return "culling.right.cell.burst[\(burst.id.uuidString)]"
        }
    }

    private func rightCellTrackingMetadata(_ cell: SmartGroupCell) -> [String: String] {
        switch cell {
        case .single(let asset):
            return ["kind": "single", "asset_id": asset.id.uuidString]
        case .burst(let burst):
            return [
                "kind": "burst",
                "burst_id": burst.id.uuidString,
                "burst_count": String(burst.count),
                "cover_asset_id": burst.coverAsset.id.uuidString
            ]
        }
    }

    // MARK: - Header

    private var cullingHeader: some View {
        HStack(spacing: 16) {
            Button {
                store.leaveProjectToSessionList()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 12, weight: .semibold))
                    Text("全部 Session")
                        .font(StitchTypography.font(size: 12, weight: .medium))
                }
                .foregroundStyle(Color(white: 0.75))
            }
            .buttonStyle(.plain)
            .lumaTrack("culling.header.back", kind: "button")

            HStack(spacing: 8) {
                Text("选片")
                    .foregroundStyle(Color(white: 0.42))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.42))
                Text(store.projectName)
                    .foregroundStyle(Color(white: 0.93))
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .font(StitchTypography.font(size: 12, weight: .regular))
            .textCase(.uppercase)
            .tracking(1.0)

            Spacer(minLength: 0)

            Text(store.importsHubSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color(white: 0.38))
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .trailing)

            Menu {
                ImportSourceMenuItems(store: store)
            } label: {
                Label("继续导入", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.82))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .disabled(store.isImporting)
            .lumaTrack("culling.header.import_menu", kind: "menu")

            Button {
                store.openExportPanel()
            } label: {
                Text("导出…")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(StitchTheme.primary.opacity(store.canExportPicked ? 1 : 0.35))
                    )
                    .foregroundStyle(StitchTheme.onPrimary)
            }
            .buttonStyle(.plain)
            .disabled(!store.canExportPicked)
            .lumaTrack("culling.header.export", kind: "button")

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
            }
            .buttonStyle(.plain)
            .help("设置")
            .lumaTrack("culling.header.settings", kind: "button")
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04).opacity(0.8))
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    // MARK: - Left sidebar: Smart Groups + All Photos overview

    private var smartGroupsSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Groups")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Text("按时间与地点自动聚合")
                    .font(StitchTypography.font(size: 12, weight: .regular))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
                    .italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 8) {
                    AllPhotosOverviewRow(
                        isSelected: store.selectedGroupID == nil,
                        summary: store.summary(for: nil),
                        coverAsset: store.assets.first
                    ) {
                        UITrace.tap("culling.left.all_photos")
                        store.selectAllPhotosOverview()
                    }
                    .lumaTrack("culling.left.all_photos", kind: "row")

                    ForEach(store.groups) { group in
                        SmartGroupRow(
                            group: group,
                            isSelected: store.selectedGroupID == group.id,
                            summary: store.summary(for: group),
                            allAssets: store.assets
                        ) {
                            UITrace.tap(
                                "culling.left.group[\(group.id.uuidString)]",
                                metadata: ["group_name": group.name]
                            )
                            store.selectGroup(group.id)
                        }
                        .lumaTrack(
                            "culling.left.group[\(group.id.uuidString)]",
                            kind: "row",
                            metadata: ["group_name": group.name]
                        )
                    }
                }
                .padding(8)
            }
        }
        .background(StitchTheme.surfaceContainerLow)
        .lumaTrack("culling.left.sidebar", kind: "panel")
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
        }
    }

    // MARK: - Center area: large image OR burst grid

    private var centerArea: some View {
        ZStack {
            Color.black

            if let asset = store.selectedAsset {
                if isCenterShowingBurstGrid, let burstContext = store.selectedBurstContext {
                    burstGridView(burstContext)
                } else {
                    largeImageView(asset)
                }
            } else {
                emptyCenterPlaceholder
            }
        }
        .lumaTrack("culling.center", kind: "panel")
    }

    private var emptyCenterPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Color(white: 0.3))
            Text("从右侧选择一张照片或一组连拍开始选片")
                .font(StitchTypography.font(size: 12, weight: .regular))
                .foregroundStyle(Color(white: 0.3))
        }
        .lumaTrack("culling.center.empty", kind: "placeholder")
    }

    /// 大图：双击在 burst 上下文里会切回网格。
    ///
    /// 使用 `DisplayImageCache` + ImageIO 解码，与预热管线一致；避免 `AsyncImage` 对部分
    /// HEIC/本地路径长期停在 loading、或只认 preview/raw 不认 thumbnail 导致黑屏。
    private func largeImageView(_ asset: MediaAsset) -> some View {
        let isBurstContext = store.selectedBurstContext != nil

        return CullingCachedLargeImage(asset: asset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .overlay(alignment: .topLeading) {
            if isBurstContext {
                Label("\(store.selectedBurstContext!.assetIndex + 1) / \(store.selectedBurstContext!.burst.count)", systemImage: "square.grid.2x2")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(1.0)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .padding(28)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            decisionBadge(for: asset)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if isBurstContext {
                UITrace.doubleTap("culling.center.large_image", metadata: ["action": "exit_to_burst_grid"])
                burstFocusOverride = false
            }
        }
        .help(isBurstContext ? "双击回到连拍网格" : "")
        .lumaTrack(
            "culling.center.large_image",
            kind: "image",
            metadata: [
                "asset_id": asset.id.uuidString,
                "burst_context": String(isBurstContext)
            ]
        )
    }

    /// 中央 Burst 网格：高亮当前 selectedAssetID，单击切高亮，双击放大成大图。
    private func burstGridView(_ context: BurstSelectionContext) -> some View {
        let burst = context.burst
        let columns = burstGridColumns(for: burst.count)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(LumaSemantic.burst)
                Text("连拍组 · \(burst.count) 张")
                    .font(StitchTypography.font(size: 11, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .textCase(.uppercase)
                    .tracking(1.0)
                Spacer()
                Text("第 \(context.burstIndex + 1) / \(context.burstCount) 组")
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
                Text("· 双击放大")
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(burst.assets) { asset in
                        BurstGridTile(
                            asset: asset,
                            isSelected: store.selectedAssetID == asset.id
                        ) {
                            UITrace.tap(
                                "culling.center.burst_grid.tile[\(asset.id.uuidString)]",
                                metadata: ["action": "select"]
                            )
                            store.selectAsset(asset.id)
                        } onDoubleTap: {
                            UITrace.doubleTap(
                                "culling.center.burst_grid.tile[\(asset.id.uuidString)]",
                                metadata: ["action": "force_large_image"]
                            )
                            store.selectAsset(asset.id)
                            burstFocusOverride = true
                        }
                        .lumaTrack(
                            "culling.center.burst_grid.tile[\(asset.id.uuidString)]",
                            kind: "tile",
                            metadata: ["asset_id": asset.id.uuidString]
                        )
                    }
                }
            }
        }
        .padding(20)
        .lumaTrack(
            "culling.center.burst_grid",
            kind: "grid",
            metadata: [
                "burst_id": burst.id.uuidString,
                "burst_count": String(burst.count)
            ]
        )
    }

    private func burstGridColumns(for count: Int) -> [GridItem] {
        let columnCount: Int
        switch count {
        case 0...1: columnCount = 1
        case 2: columnCount = 2
        case 3: columnCount = 3
        case 4: columnCount = 2
        case 5...6: columnCount = 3
        case 7...9: columnCount = 3
        case 10...12: columnCount = 4
        default: columnCount = 4
        }
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
    }

    /// 大图右下角的决策角标（替代被砍掉的 confidence / AI Best Pick）。
    @ViewBuilder
    private func decisionBadge(for asset: MediaAsset) -> some View {
        switch asset.userDecision {
        case .picked:
            decisionTag(text: "已选", icon: "checkmark.circle.fill", color: LumaSemantic.pick)
        case .rejected:
            decisionTag(text: "已拒", icon: "xmark.circle.fill", color: LumaSemantic.reject)
        case .pending:
            EmptyView()
        }
    }

    private func decisionTag(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
            Text(text)
                .font(StitchTypography.font(size: 11, weight: .bold))
                .textCase(.uppercase)
                .tracking(1.0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.85), in: Capsule())
        .padding(28)
    }

    // MARK: - Right sidebar: group cells (Burst folded) + EXIF

    private var rightSidebar: some View {
        VStack(spacing: 0) {
            rightHeader

            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3),
                    spacing: 4
                ) {
                    ForEach(store.visibleSmartGroupCells) { cell in
                        let cellID = rightCellTrackingID(cell)
                        SmartGroupCellTile(
                            cell: cell,
                            isSelected: store.selectedAssetID.map { cell.contains(assetID: $0) } ?? false
                        ) {
                            UITrace.tap(cellID, metadata: rightCellTrackingMetadata(cell))
                            // 点击右栏 burst cell = 用户明确「我要看这个连拍组的网格」。
                            // 必须显式复位 burstFocusOverride：否则若上一次在该 burst 双击放大过，
                            // selectAsset 的 cover.id 与当前 selectedAssetID 相同 → onChange 不触发 →
                            // burstFocusOverride 一直停在 true → 中央卡在单图，回不到网格。
                            if case .burst = cell {
                                burstFocusOverride = false
                            }
                            store.selectSmartGroupCell(cell)
                        }
                        .lumaTrack(cellID, kind: "tile", metadata: rightCellTrackingMetadata(cell))
                    }
                }
                .padding(8)
            }
            .background(StitchTheme.surfaceContainerLow)

            Divider().background(Color.white.opacity(0.05))

            exifCard
        }
        .background(StitchTheme.surfaceContainer)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
        }
        .lumaTrack("culling.right.sidebar", kind: "panel")
    }

    private var rightHeader: some View {
        let summary = store.summary(for: store.selectedGroup)
        let title = store.selectedGroup?.name ?? "全部照片"
        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(StitchTypography.font(size: 13, weight: .semibold))
                .foregroundStyle(StitchTheme.onSurface)
                .lineLimit(1)
            HStack(spacing: 12) {
                statTag(count: summary.picked, label: "已选", color: LumaSemantic.pick)
                statTag(count: summary.rejected, label: "已拒", color: LumaSemantic.reject)
                statTag(count: summary.pending, label: "待定", color: LumaSemantic.pending)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    private func statTag(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(StitchTypography.font(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(StitchTheme.onSurface)
            Text(label)
                .font(StitchTypography.font(size: 10, weight: .regular))
                .foregroundStyle(StitchTheme.outline)
        }
    }

    /// 当前选中图的 EXIF 信息卡（无 AI 评分）。
    private var exifCard: some View {
        let asset = store.selectedAsset
        let exif = asset?.metadata
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(StitchTheme.outline)
                Text(asset?.baseName ?? "未选中")
                    .font(StitchTypography.font(size: 11, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .lineLimit(1)
            }

            if let exif {
                VStack(alignment: .leading, spacing: 6) {
                    if let camera = exif.cameraModel {
                        exifRow(label: "相机", value: camera)
                    }
                    if let lens = exif.lensModel {
                        exifRow(label: "镜头", value: lens)
                    }

                    HStack(spacing: 6) {
                        exifChip(formatAperture(exif.aperture))
                        exifChip(exif.shutterSpeed ?? "—")
                        exifChip(formatISO(exif.iso))
                        exifChip(formatFocalLength(exif.focalLength))
                    }

                    if exif.imageWidth > 0, exif.imageHeight > 0 {
                        exifRow(label: "尺寸", value: "\(exif.imageWidth) × \(exif.imageHeight)")
                    }
                    exifRow(label: "拍摄时间", value: formatDate(exif.captureDate))
                    if let coord = exif.gpsCoordinate {
                        exifRow(
                            label: "位置",
                            value: String(format: "%.4f, %.4f", coord.latitude, coord.longitude)
                        )
                    }
                }
            } else {
                Text("未选中照片")
                    .font(StitchTypography.font(size: 11, weight: .regular))
                    .foregroundStyle(StitchTheme.outline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .lumaTrack(
            "culling.right.exif_card",
            kind: "card",
            metadata: ["asset_id": asset?.id.uuidString ?? "none"]
        )
    }

    private func exifRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(StitchTypography.font(size: 10, weight: .regular))
                .foregroundStyle(StitchTheme.outline)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(StitchTypography.font(size: 11, weight: .medium))
                .foregroundStyle(StitchTheme.onSurface)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func exifChip(_ text: String) -> some View {
        Text(text)
            .font(StitchTypography.font(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(StitchTheme.onSurface)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(StitchTheme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func formatAperture(_ value: Double?) -> String {
        guard let value, value > 0 else { return "f/—" }
        return String(format: "f/%.1f", value)
    }

    private func formatISO(_ value: Int?) -> String {
        guard let value, value > 0 else { return "ISO —" }
        return "ISO \(value)"
    }

    private func formatFocalLength(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—mm" }
        return "\(Int(value))mm"
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date)
    }

    // MARK: - Bottom action bar

    private var bottomActionBar: some View {
        let asset = store.selectedAsset
        let progress = store.sessionDecisionProgress
        let total = max(progress.total, 1)
        let isComplete = progress.total > 0 && progress.decided == progress.total

        return HStack(spacing: 16) {
            navButton(symbol: "chevron.left", help: "上一张 (←)") {
                UITrace.tap("culling.bottom.nav.prev")
                store.moveSelection(by: -1)
            }
            .disabled(asset == nil)
            .lumaTrack("culling.bottom.nav.prev", kind: "button")

            HStack(spacing: 8) {
                actionButton(
                    title: "已选",
                    subtitle: "P",
                    color: LumaSemantic.pick,
                    isActive: asset?.userDecision == .picked
                ) {
                    UITrace.tap("culling.bottom.action.pick")
                    store.markSelection(.picked)
                }
                .lumaTrack("culling.bottom.action.pick", kind: "button")

                actionButton(
                    title: "待定",
                    subtitle: "␣",
                    color: LumaSemantic.pending,
                    isActive: asset?.userDecision == .pending
                ) {
                    UITrace.tap("culling.bottom.action.pending")
                    store.markSelection(.pending)
                }
                .lumaTrack("culling.bottom.action.pending", kind: "button")

                actionButton(
                    title: "已拒",
                    subtitle: "X",
                    color: LumaSemantic.reject,
                    isActive: asset?.userDecision == .rejected
                ) {
                    UITrace.tap("culling.bottom.action.reject")
                    store.markSelection(.rejected)
                }
                .lumaTrack("culling.bottom.action.reject", kind: "button")
            }
            .disabled(asset == nil)

            Divider()
                .frame(height: 28)
                .background(Color.white.opacity(0.05))

            starRatingControl(asset: asset)

            Spacer(minLength: 8)

            sessionProgressView(decided: progress.decided, total: progress.total, fraction: Double(progress.decided) / Double(total), isComplete: isComplete)
                .lumaTrack(
                    "culling.bottom.progress",
                    kind: "indicator",
                    metadata: [
                        "decided": String(progress.decided),
                        "total": String(progress.total)
                    ]
                )

            navButton(symbol: "chevron.right", help: "下一张 (→)") {
                UITrace.tap("culling.bottom.nav.next")
                store.moveSelection(by: 1)
            }
            .disabled(asset == nil)
            .lumaTrack("culling.bottom.nav.next", kind: "button")
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(StitchTheme.surfaceContainerLow)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .lumaTrack("culling.bottom", kind: "panel")
    }

    private func navButton(symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StitchTheme.onSurface)
                .frame(width: 36, height: 36)
                .background(StitchTheme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(StitchTypography.font(size: 12, weight: .bold))
                Text(subtitle)
                    .font(StitchTypography.font(size: 10, weight: .semibold).monospaced())
                    .foregroundStyle(isActive ? Color.white.opacity(0.7) : color.opacity(0.7))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(isActive ? Color.white.opacity(0.3) : color.opacity(0.4), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isActive ? .white : color)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? color : color.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(color.opacity(isActive ? 0 : 0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("\(title) (\(subtitle))")
    }

    /// 1–5 星评级条；点击同一星级清除。与键盘 1–5 同步。
    private func starRatingControl(asset: MediaAsset?) -> some View {
        let active = asset?.userRating ?? 0
        return HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { rating in
                Button {
                    if asset?.userRating == rating {
                        UITrace.tap("culling.bottom.star[\(rating)]", metadata: ["action": "clear"])
                        store.clearSelectionRating()
                    } else {
                        UITrace.tap("culling.bottom.star[\(rating)]", metadata: ["action": "set"])
                        store.rateSelection(rating)
                    }
                } label: {
                    Image(systemName: rating <= active ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rating <= active ? LumaSemantic.rating : StitchTheme.outline.opacity(0.5))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("评 \(rating) 星（再次点击清除）")
                .lumaTrack(
                    "culling.bottom.star[\(rating)]",
                    kind: "button",
                    metadata: ["rating": String(rating)]
                )
            }
        }
        .disabled(asset == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(active > 0 ? "当前评分 \(active) 星" : "未评分"))
    }

    private func sessionProgressView(decided: Int, total: Int, fraction: Double, isComplete: Bool) -> some View {
        HStack(spacing: 8) {
            Text("\(decided)/\(total) 已决定")
                .font(StitchTypography.font(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isComplete ? StitchTheme.primary : Color(white: 0.7))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 96, height: 4)
                Capsule()
                    .fill(isComplete ? StitchTheme.primary : Color(white: 0.7))
                    .frame(width: 96 * fraction, height: 4)
            }
            .accessibilityLabel(Text("已决策 \(decided)，共 \(total)"))
            if isComplete {
                Text("完成")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.onPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(StitchTheme.primary, in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04), in: Capsule())
    }
}

// MARK: - Subviews

/// 左栏「全部照片」概览行：点击切到 selectedGroupID = nil 视图。
private struct AllPhotosOverviewRow: View {
    let isSelected: Bool
    let summary: GroupDecisionSummary
    let coverAsset: MediaAsset?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    CullingThumbnailView(asset: coverAsset)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .grayscale(isSelected ? 0 : 0.4)

                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("全部照片")
                        .font(StitchTypography.font(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? StitchTheme.primary : StitchTheme.onSurface)
                    Text("\(summary.total) 张 · \(summary.picked) 已选")
                        .font(StitchTypography.font(size: 10, weight: .regular))
                        .foregroundStyle(StitchTheme.outline)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? StitchTheme.surfaceContainerHighest : Color.clear)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(StitchTheme.primary.opacity(0.25), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SmartGroupRow: View {
    let group: PhotoGroup
    let isSelected: Bool
    let summary: GroupDecisionSummary
    let allAssets: [MediaAsset]
    let onSelect: () -> Void

    private var coverAsset: MediaAsset? {
        group.assets.compactMap { id in
            allAssets.first(where: { $0.id == id })
        }.first
    }

    private var timeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "HH:mm"
        return f.string(from: group.timeRange.lowerBound)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    CullingThumbnailView(asset: coverAsset)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .grayscale(isSelected ? 0 : 0.4)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(StitchTypography.font(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? StitchTheme.primary : StitchTheme.onSurface)
                            .lineLimit(1)
                        Text("\(group.assets.count) 张 · \(timeString)")
                            .font(StitchTypography.font(size: 10, weight: .regular))
                            .foregroundStyle(StitchTheme.outline)
                    }
                }

                if isSelected {
                    GroupProgressBar(summary: summary)
                        .frame(height: 4)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? StitchTheme.surfaceContainerHighest : Color.clear)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(StitchTheme.primary.opacity(0.25), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 右栏 cell：单图直接显示缩略图；连拍组显示代表图 + 角标（张数）。
private struct SmartGroupCellTile: View {
    let cell: SmartGroupCell
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                CullingThumbnailView(asset: cell.coverAsset)
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                if case .burst(let burst) = cell {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(burst.count)")
                            .font(StitchTypography.font(size: 9, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(LumaSemantic.burst.opacity(0.9), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
                    .padding(4)
                }

                decisionDot(for: cell.coverAsset.userDecision)
            }
            .opacity(isSelected ? 1 : 0.85)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(StitchTheme.primary, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func decisionDot(for decision: Decision) -> some View {
        switch decision {
        case .picked:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LumaSemantic.pick, .black.opacity(0.5))
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(LumaSemantic.reject, .black.opacity(0.5))
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        case .pending:
            EmptyView()
        }
    }
}

/// 中央单张大图：走 `DisplayImageCache`，与 `ProjectStore` 预热同源，避免 `AsyncImage` 无限 loading。
private struct CullingCachedLargeImage: View {
    let asset: MediaAsset

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loadFailed {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Color(white: 0.35))
                    Text("无法加载图片")
                        .font(StitchTypography.font(size: 12, weight: .regular))
                        .foregroundStyle(Color(white: 0.45))
                    if asset.primaryDisplayURL == nil {
                        Text("没有可用的图片资源路径")
                            .font(StitchTypography.font(size: 11, weight: .regular))
                            .foregroundStyle(Color(white: 0.35))
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
            } else {
                ProgressView()
                    .tint(StitchTheme.primary)
            }
        }
        .task(id: asset.id) {
            loadFailed = false
            image = nil
            let loaded = await DisplayImageCache.shared.image(for: asset)
            image = loaded
            loadFailed = loaded == nil
        }
    }
}

/// 中央 burst 网格内的单张瓦片：单击 = 选中；双击 = 强制单图大图。
private struct BurstGridTile: View {
    let asset: MediaAsset
    let isSelected: Bool
    let onTap: () -> Void
    let onDoubleTap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            CullingThumbnailView(asset: asset)
                // 先占满「格子」再裁切；避免大图 intrinsic 尺寸把 LazyVGrid 撑满一行，导致
                // `.lumaTrack` 里 GeometryReader 报出 800+ pt 宽、与邻格重叠的假 frame。
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()

            decisionCorner(for: asset.userDecision)
                .padding(6)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3.0 / 2.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isSelected ? StitchTheme.primary : Color.clear, lineWidth: isSelected ? 3 : 2)
        }
        .opacity(isSelected ? 1 : 0.85)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onDoubleTap)
        .onTapGesture(count: 1, perform: onTap)
        .help("单击选中 · 双击放大")
    }

    @ViewBuilder
    private func decisionCorner(for decision: Decision) -> some View {
        switch decision {
        case .picked:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white, LumaSemantic.pick)
        case .rejected:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white, LumaSemantic.reject)
        case .pending:
            EmptyView()
        }
    }
}

private struct GroupProgressBar: View {
    let summary: GroupDecisionSummary

    var body: some View {
        GeometryReader { geo in
            let total = max(1, summary.picked + summary.rejected + summary.pending)
            let pw = geo.size.width * CGFloat(summary.picked) / CGFloat(total)
            let rw = geo.size.width * CGFloat(summary.rejected) / CGFloat(total)

            HStack(spacing: 0) {
                Rectangle().fill(LumaSemantic.pick).frame(width: pw)
                Rectangle().fill(LumaSemantic.reject).frame(width: rw)
                Rectangle().fill(StitchTheme.surfaceVariant)
            }
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
    }
}

/// 选片页通用缩略图视图，统一走 `ThumbnailCache`。
///
/// 不再用 `AsyncImage(url:)`：导入失败/PhotoKit cloud-only 的资产 `previewURL` 指向的
/// 文件并不存在，`AsyncImage` 拿到 file:// 拉空就显示成黑块。`ThumbnailCache` 内部
/// 优先解码本地 PNG 缩略图（导入阶段必落盘），即使 preview 缺失也能稳定出图。
///
/// 调用方负责给容器加 `.frame(...)`、`.clipShape(...)` 等外层尺寸约束；本视图只
/// 关心「在给定空间内把缩略图画出来」。
private struct CullingThumbnailView: View {
    let asset: MediaAsset?
    var contentMode: ContentMode = .fill

    @State private var image: NSImage?
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if loadFailed || asset == nil {
                Color(white: 0.15)
            } else {
                Color(white: 0.15)
            }
        }
        .task(id: asset?.id) {
            guard let asset else {
                image = nil
                loadFailed = true
                return
            }
            loadFailed = false
            image = nil
            let loaded = await ThumbnailCache.shared.image(for: asset)
            image = loaded
            loadFailed = loaded == nil
        }
    }
}
