import AppKit
import SwiftUI

/// 与 `ThumbnailCell` 底栏、`BurstCell` 单张底栏、`BurstThumbnailChip` 信息密度对齐的说明行（相机/尺寸 · 星级）。
private func workspaceAssetCaptionLine(for asset: MediaAsset) -> String {
    let camera = asset.metadata.cameraModel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let dim = asset.dimensionsDescription
    let left = camera.isEmpty ? dim : camera
    return "\(left) · ★\(asset.effectiveRating)"
}

struct PhotoGrid: View {
    @Bindable var store: ProjectStore

    private let burstMinimumWidth: CGFloat = 180
    private let burstMaximumWidth: CGFloat = 260
    private var burstSpacing: CGFloat { AppSpacing.xxl }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: AppSpacing.xxl, alignment: .top)]
    }

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.assets.isEmpty {
                ContentUnavailableView(
                    "尚未打开项目",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("通过工具栏导入照片文件夹、包含 DCIM 的 SD 卡，或 USB 连接的 iPhone。")
                )
            } else {
                workspaceContent
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(alignment: .bottom) {
            if !store.assets.isEmpty {
                floatingToolbar
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.assets.isEmpty)
    }

    private func preheatSeed(for visibleAssets: [MediaAsset]) -> String {
        let scope = store.selectedGroupID?.uuidString ?? "all"
        let first = visibleAssets.first?.id.uuidString ?? "empty"
        return "\(scope)-\(first)-\(visibleAssets.count)"
    }

    /// 用于连拍网格高亮与展开条：只要当前选中图落在该 burst 内即匹配（含单张伪组，与 `selectedBurstContext` 无关）。
    private func burstIDContainingSelectedAsset(in bursts: [BurstDisplayGroup]) -> UUID? {
        guard let selectedAssetID = store.selectedAssetID else { return nil }
        return bursts.first { burst in
            burst.assets.contains { $0.id == selectedAssetID }
        }?.id
    }

    private func burstPreheatSeed(for bursts: [BurstDisplayGroup]) -> String {
        let scope = store.selectedGroupID?.uuidString ?? "all"
        let first = bursts.first?.coverAsset.id.uuidString ?? "empty"
        return "\(scope)-burst-\(first)-\(bursts.count)"
    }

    @ViewBuilder
    private var workspaceContent: some View {
        let visibleAssets = store.visibleAssets
        let visibleBursts = store.visibleBurstGroups
        let selectedBurstID = burstIDContainingSelectedAsset(in: visibleBursts)

        if store.displayMode == .single, let asset = store.selectedAsset {
            SingleAssetView(asset: asset, visibleAssets: visibleAssets)
                .padding()
                .padding(.bottom, 76)
        } else if store.selectedGroup != nil {
            GeometryReader { geometry in
                let rows = burstRows(for: visibleBursts, availableWidth: geometry.size.width - 40)
                let columnCount = burstColumnCount(for: geometry.size.width - 40)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: burstSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(alignment: .top, spacing: burstSpacing) {
                                    ForEach(row) { burst in
                                        BurstCell(
                                            burst: burst,
                                            isSelected: burst.id == selectedBurstID
                                        )
                                        .frame(maxWidth: burstMaximumWidth)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .gesture(TapGesture().onEnded {
                                            let selectedAssetID = store.selectedAssetID
                                            let targetAssetID = burst.id == selectedBurstID
                                                ? selectedAssetID ?? burst.coverAsset.id
                                                : (burst.bestAssetID ?? burst.coverAsset.id)
                                            store.selectAsset(targetAssetID)
                                        })
                                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                                            let targetAssetID = burst.bestAssetID ?? burst.coverAsset.id
                                            store.selectAsset(targetAssetID)
                                            store.toggleDisplayMode()
                                        })
                                    }

                                    ForEach(row.count..<columnCount, id: \.self) { _ in
                                        Color.clear
                                            .frame(maxWidth: .infinity)
                                    }
                                }

                                if let expandedBurst = expandedBurst(in: row, selectedBurstID: selectedBurstID),
                                   expandedBurst.count > 1 {
                                    BurstThumbnailStrip(
                                        burst: expandedBurst,
                                        selectedAssetID: store.selectedAssetID,
                                        onSelect: { assetID in
                                            store.selectAsset(assetID)
                                        },
                                        onOpen: { assetID in
                                            store.selectAsset(assetID)
                                            store.setDisplayMode(.single)
                                        }
                                    )
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }
                    .padding(AppSpacing.gutter)
                    .padding(.bottom, 80)
                }
            }
            .task(id: burstPreheatSeed(for: visibleBursts)) {
                let leadAssets = visibleBursts.prefix(24).map(\.coverAsset)
                ThumbnailCache.shared.preheat(assets: leadAssets)
                ThumbnailCache.shared.trim(toRetainAssetIDs: Set(visibleBursts.prefix(80).map(\.coverAsset.id)))
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.xxl) {
                    ForEach(visibleAssets) { asset in
                        ThumbnailCell(
                            asset: asset,
                            isSelected: asset.id == store.selectedAssetID
                        )
                        .gesture(TapGesture().onEnded {
                            store.selectAsset(asset.id)
                        })
                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                            store.selectAsset(asset.id)
                            store.toggleDisplayMode()
                        })
                    }
                }
                .padding(AppSpacing.gutter)
                .padding(.bottom, 80)
            }
            .task(id: preheatSeed(for: visibleAssets)) {
                let initialAssets = Array(visibleAssets.prefix(24))
                ThumbnailCache.shared.preheat(assets: initialAssets)
                ThumbnailCache.shared.trim(toRetainAssetIDs: Set(visibleAssets.prefix(120).map(\.id)))
            }
        }
    }

    private func burstColumnCount(for availableWidth: CGFloat) -> Int {
        let safeWidth = max(availableWidth, burstMinimumWidth)
        return max(Int((safeWidth + burstSpacing) / (burstMinimumWidth + burstSpacing)), 1)
    }

    private func burstRows(for bursts: [BurstDisplayGroup], availableWidth: CGFloat) -> [[BurstDisplayGroup]] {
        let columnCount = burstColumnCount(for: availableWidth)
        guard columnCount > 0 else { return [bursts] }

        var rows: [[BurstDisplayGroup]] = []
        var index = 0

        while index < bursts.count {
            let endIndex = min(index + columnCount, bursts.count)
            rows.append(Array(bursts[index..<endIndex]))
            index = endIndex
        }

        return rows
    }

    private func expandedBurst(in row: [BurstDisplayGroup], selectedBurstID: UUID?) -> BurstDisplayGroup? {
        guard let selectedBurstID else { return nil }
        return row.first(where: { $0.id == selectedBurstID })
    }

    private var floatingToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.lg) {
                toolbarPickPill(shortcut: "P", title: "已选") {
                    store.markSelection(.picked)
                }
                toolbarRejectPill(shortcut: "X", title: "拒绝") {
                    store.markSelection(.rejected)
                }
                toolbarGlassPill(shortcut: "U", title: "待定") {
                    store.clearSelectionDecision()
                }

                Divider()
                    .frame(height: 20)

                ratingMenu

                Divider()
                    .frame(height: 20)

                toolbarHint(shortcut: store.displayMode == .single ? "双击" : "Space", title: store.displayMode == .single ? "缩放" : "单页")
                toolbarHint(shortcut: "← →", title: "切换")
            }
            .padding(.horizontal, AppRadius.chipOuter)
            .padding(.vertical, AppSpacing.lg)
        }
        .scrollClipDisabled()
        .frame(maxWidth: 820)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.toolbar, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.toolbar, style: .continuous)
                .strokeBorder(DesignChrome.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }

    private var hasSelection: Bool {
        store.selectedAssetID != nil
    }

    private var ratingMenu: some View {
        Menu {
            ForEach(1...5, id: \.self) { rating in
                Button("\(rating) 星") {
                    store.rateSelection(rating)
                }
            }

            Divider()

            Button("清除评分") {
                store.clearSelectionRating()
            }
        } label: {
            toolbarMonochromeMenuPill(shortcut: "1-5", title: "评星")
        }
        .menuStyle(.borderlessButton)
        .disabled(!hasSelection)
    }

    private func toolbarPickPill(shortcut: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                Text(shortcut)
                    .font(.caption2.monospaced().weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.22), in: RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(LumaSemantic.pick, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
        .opacity(hasSelection ? 1 : 0.5)
    }

    private func toolbarRejectPill(shortcut: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                keycap(shortcut, tint: LumaSemantic.reject.opacity(0.16), foreground: LumaSemantic.reject)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LumaSemantic.reject)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(LumaSemantic.reject.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(LumaSemantic.reject.opacity(0.55), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
        .opacity(hasSelection ? 1 : 0.5)
    }

    /// Glass Dark 次要操作
    private func toolbarGlassPill(shortcut: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.md) {
                keycap(shortcut, tint: DesignChrome.glassDark, foreground: .primary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DesignChrome.glassDark, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
        .opacity(hasSelection ? 1 : 0.5)
    }

    private func toolbarMonochromeMenuPill(shortcut: String, title: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            keycap(shortcut, tint: LumaSemantic.rating.opacity(0.35), foreground: .primary)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(LumaSemantic.rating.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(DesignChrome.hairline, lineWidth: 1))
        .opacity(hasSelection ? 1 : 0.5)
    }

    private func toolbarHint(shortcut: String, title: String) -> some View {
        HStack(spacing: AppSpacing.md) {
            keycap(shortcut, tint: DesignChrome.glassDark, foreground: .secondary)

            Text(title)
                .font(.caption.weight(.light))
                .foregroundStyle(.secondary)
                .kerning(DesignType.bodyKerning)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(DesignChrome.glassDark.opacity(0.5), in: Capsule())
    }

    private func keycap(_ title: String, tint: Color, foreground: Color = .primary) -> some View {
        Text(title)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint, in: RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous))
    }
}

private struct BurstCell: View {
    let burst: BurstDisplayGroup
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            previewCard

            Text(summaryLabel)
                .font(.caption.weight(.light))
                .foregroundStyle(.secondary)
                .kerning(DesignType.bodyKerning)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous)
                .stroke(selectionBorderColor, lineWidth: isSelected ? 2.5 : 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .accessibilityLabel(Text("连拍组，\(summaryLabel)，\(burst.coverAsset.baseName)"))
        .task(id: burst.coverAsset.id) {
            image = await ThumbnailCache.shared.image(for: burst.coverAsset)
        }
        .onAppear {
            ThumbnailCache.shared.preheat(assets: Array(burst.assets.prefix(3)))
        }
    }

    private var summaryLabel: String {
        if burst.count == 1 {
            return workspaceAssetCaptionLine(for: burst.coverAsset)
        }
        return "\(burst.count) 张候选"
    }

    private var previewCard: some View {
        ZStack(alignment: .center) {
            if burst.count > 1 {
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(DesignChrome.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                            .stroke(DesignChrome.hairline, lineWidth: 1)
                    )
                    .offset(x: 10, y: -10)

                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                            .stroke(DesignChrome.hairline, lineWidth: 1)
                    )
                    .offset(x: 5, y: -5)
            }

            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(DesignChrome.imageWell)
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(burst.coverAsset.userDecision == .rejected || burst.coverAsset.isTechnicallyRejected ? 0.52 : 1)
                    } else {
                        ProgressView()
                            .controlSize(.regular)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .aspectRatio(1.1, contentMode: .fit)
        .padding(.trailing, burst.count > 1 ? AppSpacing.lg : 0)
        .padding(.top, burst.count > 1 ? AppSpacing.lg : 0)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private var backgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.10) : DesignChrome.cardSurface
    }

    private var selectionBorderColor: Color {
        isSelected ? Color.accentColor : DesignChrome.hairline
    }
}

private struct BurstThumbnailStrip: View {
    let burst: BurstDisplayGroup
    let selectedAssetID: UUID?
    let onSelect: (UUID) -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack {
                Text("连拍组明细")
                    .font(DesignType.sectionLabel())
                    .tracking(DesignType.sectionTracking)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(burst.count) 张")
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(burst.assets.enumerated()), id: \.element.id) { index, asset in
                        BurstThumbnailChip(
                            asset: asset,
                            index: index,
                            isSelected: asset.id == selectedAssetID,
                            isBest: asset.id == burst.bestAssetID,
                            onSelect: { onSelect(asset.id) },
                            onOpen: { onOpen(asset.id) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .padding(AppRadius.chipOuter)
        .background(DesignChrome.cardSurface, in: RoundedRectangle(cornerRadius: AppRadius.strip, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.strip, style: .continuous)
                .stroke(DesignChrome.hairline, lineWidth: 1)
        }
        .onAppear {
            ThumbnailCache.shared.preheat(assets: burst.assets)
        }
    }
}

private struct BurstThumbnailChip: View {
    let asset: MediaAsset
    let index: Int
    let isSelected: Bool
    let isBest: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var image: NSImage?

    var body: some View {
        RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
            .fill(DesignChrome.imageWell)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 92)
                        .opacity(asset.userDecision == .rejected || asset.isTechnicallyRejected ? 0.52 : 1)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack(spacing: AppSpacing.sm) {
                        DesignChromeBadge(text: "#\(index + 1)")
                        if isBest {
                            SemanticCapsuleBadge(text: "最佳", fill: LumaSemantic.best, foreground: .black)
                        }
                    }
                    if asset.userDecision == .picked {
                        SemanticCapsuleBadge(text: "已选", fill: LumaSemantic.pick, compact: true)
                    } else if asset.userDecision == .rejected {
                        SemanticCapsuleBadge(text: "已拒", fill: LumaSemantic.reject, compact: true)
                    }
                }
                .padding(8)
            }
            .frame(width: 120, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous))
            .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.chipOuter, style: .continuous)
                .fill(chipBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.chipOuter, style: .continuous)
                .stroke(statusBorderColor, lineWidth: statusBorderColor == .clear ? 0 : 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.chipOuter + 2, style: .continuous)
                .stroke(selectionBorderColor, lineWidth: isSelected ? 2.5 : 0)
                .padding(-2)
        )
        .overlay {
            if idleHairlineBorder {
                RoundedRectangle(cornerRadius: AppRadius.chipOuter, style: .continuous)
                    .stroke(DesignChrome.hairline, lineWidth: 1)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: asset.userDecision)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.chipOuter, style: .continuous))
        .gesture(TapGesture().onEnded {
            onSelect()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpen()
        })
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset)
        }
        .accessibilityLabel(Text("第 \(index + 1) 张，\(asset.baseName)"))
    }

    private var chipBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        if asset.userDecision == .picked {
            return LumaSemantic.pick.opacity(0.08)
        }
        if asset.userDecision == .rejected {
            return LumaSemantic.reject.opacity(0.06)
        }
        return Color.clear
    }

    private var statusBorderColor: Color {
        if asset.userDecision == .picked {
            return LumaSemantic.pick.opacity(0.45)
        }
        if asset.userDecision == .rejected {
            return LumaSemantic.reject.opacity(0.42)
        }
        return .clear
    }

    private var selectionBorderColor: Color {
        isSelected ? Color.accentColor : .clear
    }

    private var idleHairlineBorder: Bool {
        !isSelected && asset.userDecision == .pending
    }
}

private struct ThumbnailCell: View {
    let asset: MediaAsset
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            previewCard

            Text(metaLine)
                .font(.caption.weight(.light))
                .foregroundStyle(.secondary)
                .kerning(DesignType.bodyKerning)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous)
                .stroke(statusBorderColor, lineWidth: statusBorderColor == .clear ? 0 : 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.cardOuter + 2, style: .continuous)
                .stroke(selectionBorderColor, lineWidth: isSelected ? 2.5 : 0)
                .padding(-2)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: asset.userDecision)
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset)
        }
        .accessibilityLabel(Text(thumbnailAccessibilitySummary))
    }

    private var thumbnailAccessibilitySummary: String {
        var parts = [asset.baseName, metaLine]
        if let score = asset.aiScore {
            parts.append("AI 分 \(score.overall)")
        }
        return parts.joined(separator: "，")
    }

    private var metaLine: String {
        workspaceAssetCaptionLine(for: asset)
    }

    private var previewCard: some View {
        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
            .fill(DesignChrome.imageWell)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(asset.userDecision == .rejected || asset.isTechnicallyRejected ? 0.52 : 1)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    if asset.aiScore?.recommended == true {
                        SemanticCapsuleBadge(text: "AI 推荐", fill: LumaSemantic.ai)
                    }

                    if let firstIssue = asset.issues.first {
                        SemanticCapsuleBadge(text: firstIssue.label, fill: LumaSemantic.issue)
                    }

                    if asset.userDecision == .picked {
                        SemanticCapsuleBadge(text: "已选", fill: LumaSemantic.pick)
                    } else if asset.userDecision == .rejected {
                        SemanticCapsuleBadge(text: "已拒", fill: LumaSemantic.reject)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .aspectRatio(1.1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.10)
        }
        if asset.userDecision == .picked {
            return LumaSemantic.pick.opacity(0.08)
        }
        if asset.userDecision == .rejected {
            return LumaSemantic.reject.opacity(0.06)
        }
        return DesignChrome.cardSurface
    }

    private var statusBorderColor: Color {
        if asset.userDecision == .picked {
            return LumaSemantic.pick.opacity(0.45)
        }
        if asset.userDecision == .rejected {
            return LumaSemantic.reject.opacity(0.42)
        }
        return .clear
    }

    private var selectionBorderColor: Color {
        isSelected ? Color.accentColor : .clear
    }
}

private struct SingleAssetView: View {
    let asset: MediaAsset
    let visibleAssets: [MediaAsset]

    @State private var image: NSImage?
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            imageStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    if asset.mediaType != .photo {
                        Text(singleDetailMediaTypeTitle(asset.mediaType))
                            .font(.title3.weight(.medium))
                            .kerning(DesignType.titleKerning)
                    }
                    if asset.userDecision == .picked {
                        singleViewDecisionBadge("已选", color: .green)
                    } else if asset.userDecision == .rejected {
                        singleViewDecisionBadge("已拒", color: .red.opacity(0.88))
                    }
                    Spacer()
                    Text(asset.dimensionsDescription)
                        .font(.callout.weight(.light))
                        .foregroundStyle(.secondary)
                        .kerning(DesignType.bodyKerning)
                }
                .animation(.easeInOut(duration: 0.15), value: asset.userDecision)

                if !asset.issues.isEmpty {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(asset.issues) { issue in
                            SemanticCapsuleBadge(text: issue.label, fill: LumaSemantic.issue)
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.vertical, AppRadius.chipOuter)
            .background(.ultraThinMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityLabel(Text("\(asset.baseName)，\(asset.dimensionsDescription)"))
        .task(id: asset.id) {
            await loadImage()
        }
        .onDisappear {
            if let currentIndex = visibleAssets.firstIndex(where: { $0.id == asset.id }) {
                let lowerBound = max(visibleAssets.startIndex, currentIndex - 1)
                let upperBound = min(visibleAssets.endIndex, currentIndex + 2)
                let keep = Set(visibleAssets[lowerBound..<upperBound].map(\.id))
                DisplayImageCache.shared.trim(toRetainAssetIDs: keep)
            }
        }
    }

    private func singleDetailMediaTypeTitle(_ type: MediaType) -> String {
        switch type {
        case .photo:
            return "照片"
        case .livePhoto:
            return "实况照片"
        case .portrait:
            return "人像照片"
        }
    }

    @ViewBuilder
    private var imageStage: some View {
        GeometryReader { geometry in
            let stageSize = geometry.size

            if let image {
                let fitted = fittedSize(for: image, in: stageSize)

                ScrollView([.horizontal, .vertical]) {
                    ZStack {
                        Color.clear

                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .frame(
                                width: max(fitted.width * zoomScale, fitted.width),
                                height: max(fitted.height * zoomScale, fitted.height)
                            )
                            .opacity(asset.userDecision == .rejected || asset.isTechnicallyRejected ? 0.55 : 1)
                            .animation(.easeInOut(duration: 0.15), value: asset.userDecision)
                            .onTapGesture(count: 2) {
                                toggleZoom()
                            }
                    }
                    .frame(
                        width: max(stageSize.width, fitted.width * zoomScale),
                        height: max(stageSize.height, fitted.height * zoomScale)
                    )
                }
                .background(Color.black.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(ProgressView())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func fittedSize(for image: NSImage, in container: CGSize) -> CGSize {
        let original = image.size
        guard original.width > 0,
              original.height > 0,
              container.width > 0,
              container.height > 0 else {
            return container
        }

        let widthRatio = container.width / original.width
        let heightRatio = container.height / original.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(width: original.width * scale, height: original.height * scale)
    }

    private func toggleZoom() {
        zoomScale = zoomScale > 1 ? 1 : 2
        RuntimeTrace.event(
            "single_zoom_toggled",
            category: "viewer",
            metadata: [
                "asset_id": asset.id.uuidString,
                "zoom_scale": String(format: "%.2f", zoomScale)
            ]
        )
    }

    private func singleViewDecisionBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.92), in: Capsule())
            .foregroundStyle(.white)
    }

    private func loadImage() async {
        let startedAt = ProcessInfo.processInfo.systemUptime
        image = nil
        zoomScale = 1
        var firstPaintSource = "placeholder"
        var finalSource = "thumbnail"
        var firstPaintLogged = false

        func logFirstPaint(source: String) {
            guard !firstPaintLogged else { return }
            firstPaintLogged = true
            firstPaintSource = source
            RuntimeTrace.metric(
                "single_image_first_paint",
                category: "viewer",
                metadata: [
                    "asset_id": asset.id.uuidString,
                    "source": source,
                    "duration_ms": String(format: "%.2f", max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1000),
                    "visible_count": String(visibleAssets.count)
                ]
            )
        }

        if let cachedDisplay = DisplayImageCache.shared.cachedImage(for: asset) {
            image = cachedDisplay
            finalSource = "display_memory"
            logFirstPaint(source: finalSource)
        } else {
            let displayLoadTask = Task {
                await DisplayImageCache.shared.image(for: asset)
            }

            if let thumbnail = await ThumbnailCache.shared.image(for: asset) {
                guard !Task.isCancelled else { return }
                image = thumbnail
                logFirstPaint(source: "thumbnail")
            }

            if let displayImage = await displayLoadTask.value {
                guard !Task.isCancelled else { return }
                image = displayImage
                finalSource = "display_async"
                if !firstPaintLogged {
                    logFirstPaint(source: finalSource)
                }
            }
        }

        DisplayImageCache.shared.preheatNeighborhood(around: asset.id, in: visibleAssets, radius: 1)
        RuntimeTrace.metric(
            "single_image_loaded",
            category: "viewer",
            metadata: [
                "asset_id": asset.id.uuidString,
                "source": finalSource,
                "first_paint_source": firstPaintSource,
                "duration_ms": String(format: "%.2f", max(0, ProcessInfo.processInfo.systemUptime - startedAt) * 1000),
                "visible_count": String(visibleAssets.count)
            ]
        )
    }
}
