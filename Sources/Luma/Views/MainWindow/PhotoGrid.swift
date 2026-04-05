import AppKit
import SwiftUI

struct PhotoGrid: View {
    @Bindable var store: ProjectStore

    private let burstMinimumWidth: CGFloat = 180
    private let burstMaximumWidth: CGFloat = 260
    private let burstSpacing: CGFloat = 16
    private let columns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16, alignment: .top)
    ]

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.assets.isEmpty {
                ContentUnavailableView(
                    "No Project Loaded",
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
            }
        }
    }

    private func preheatSeed(for visibleAssets: [MediaAsset]) -> String {
        let scope = store.selectedGroupID?.uuidString ?? "all"
        let first = visibleAssets.first?.id.uuidString ?? "empty"
        return "\(scope)-\(first)-\(visibleAssets.count)"
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
        let visibleBurstOrdinals = Dictionary(uniqueKeysWithValues: visibleBursts.enumerated().map { ($1.id, $0 + 1) })
        let selectedBurstID = store.selectedBurstContext?.burst.id

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
                                            burstOrdinal: visibleBurstOrdinals[burst.id] ?? 1,
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
                                }
                            }
                        }
                    }
                    .padding(20)
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
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
                .padding(20)
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
            HStack(spacing: 10) {
                toolbarActionButton(
                    shortcut: "P",
                    title: "已选",
                    tint: .green
                ) {
                    store.markSelection(.picked)
                }

                toolbarActionButton(
                    shortcut: "X",
                    title: "拒绝",
                    tint: .red
                ) {
                    store.markSelection(.rejected)
                }

                toolbarActionButton(
                    shortcut: "U",
                    title: "待定",
                    tint: .secondary
                ) {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
        .frame(maxWidth: 820)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
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
            toolbarPill(shortcut: "1-5", title: "评星", tint: .yellow, isInteractive: true)
        }
        .menuStyle(.borderlessButton)
        .disabled(!hasSelection)
    }

    private func toolbarActionButton(
        shortcut: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarPill(shortcut: shortcut, title: title, tint: tint, isInteractive: true)
        }
        .buttonStyle(.plain)
        .disabled(!hasSelection)
    }

    private func toolbarHint(shortcut: String, title: String) -> some View {
        HStack(spacing: 8) {
            keycap(shortcut, tint: Color.secondary.opacity(0.16), foreground: .secondary)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func toolbarPill(
        shortcut: String,
        title: String,
        tint: Color,
        isInteractive: Bool
    ) -> some View {
        HStack(spacing: 8) {
            keycap(shortcut, tint: tint.opacity(isInteractive ? 0.18 : 0.12), foreground: tint)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(isInteractive ? 0.12 : 0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(isInteractive ? 0.18 : 0.12), lineWidth: 1)
        }
        .opacity(hasSelection || !isInteractive ? 1 : 0.55)
    }

    private func keycap(_ title: String, tint: Color, foreground: Color = .primary) -> some View {
        Text(title)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct BurstCell: View {
    let burst: BurstDisplayGroup
    let burstOrdinal: Int
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewCard

            Text(burst.coverAsset.baseName)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(summaryLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if burst.bestAssetID != nil {
                    Text("Best")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(selectionBorderColor, lineWidth: isSelected ? 2.5 : 1)
        )
        .task(id: burst.coverAsset.id) {
            image = await ThumbnailCache.shared.image(for: burst.coverAsset)
        }
        .onAppear {
            ThumbnailCache.shared.preheat(assets: Array(burst.assets.prefix(3)))
        }
    }

    private var summaryLabel: String {
        if burst.count == 1 {
            return "单张"
        }
        return "\(burst.count) 张候选"
    }

    private var previewCard: some View {
        ZStack(alignment: .center) {
            if burst.count > 1 {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .offset(x: 10, y: -10)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.30), lineWidth: 1)
                    )
                    .offset(x: 5, y: -5)
            }

            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
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
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        if burst.count > 1 {
                            badge("连拍组 \(burstOrdinal)", color: .orange)
                        }

                        if burst.coverAsset.aiScore?.recommended == true {
                            badge("AI 推荐", color: .blue)
                        }
                    }
                    .padding(10)
                }
                .overlay(alignment: .topTrailing) {
                    if burst.count > 1 {
                        Text("x\(burst.count)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let score = burst.coverAsset.aiScore {
                        Text("\(score.overall)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(10)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .aspectRatio(1.1, contentMode: .fit)
        .padding(.trailing, burst.count > 1 ? 10 : 0)
        .padding(.top, burst.count > 1 ? 10 : 0)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var backgroundColor: Color {
        isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.05)
    }

    private var selectionBorderColor: Color {
        isSelected ? .accentColor : Color.white.opacity(0.08)
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.92), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct BurstThumbnailStrip: View {
    let burst: BurstDisplayGroup
    let selectedAssetID: UUID?
    let onSelect: (UUID) -> Void
    let onOpen: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("连拍组明细")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(burst.count) 张")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
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
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 120, height: 92)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 6) {
                        badge("#\(index + 1)", color: .black.opacity(0.72))
                        if isBest {
                            badge("Best", color: .orange)
                        }
                    }
                    .padding(8)
                }
                .frame(width: 120, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(asset.baseName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
        }
        .padding(6)
        .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .gesture(TapGesture().onEnded {
            onSelect()
        })
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            onOpen()
        })
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset)
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct ThumbnailCell: View {
    let asset: MediaAsset
    let isSelected: Bool

    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewCard

            Text(asset.baseName)
                .font(.headline)
                .lineLimit(1)

            HStack {
                Text(asset.metadata.cameraModel ?? asset.dimensionsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("★\(asset.effectiveRating)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(statusBorderColor, lineWidth: statusBorderColor == .clear ? 0 : 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(selectionBorderColor, lineWidth: isSelected ? 3 : 0)
                .padding(-2)
        )
        .task(id: asset.id) {
            image = await ThumbnailCache.shared.image(for: asset)
        }
    }

    private var previewCard: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
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
                VStack(alignment: .leading, spacing: 8) {
                    if asset.aiScore?.recommended == true {
                        badge("AI 推荐", color: .blue)
                    }

                    if let firstIssue = asset.issues.first {
                        badge(firstIssue.label, color: .red)
                    }

                    if asset.userDecision == .picked {
                        badge("已选", color: .green)
                    } else if asset.userDecision == .rejected {
                        badge("已拒", color: .red.opacity(0.85))
                    }
                }
                .padding(10)
            }
            .overlay(alignment: .bottomTrailing) {
                if let score = asset.aiScore {
                    Text("\(score.overall)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
            }
            .aspectRatio(1.1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.14)
        }
        if asset.userDecision == .picked {
            return Color.green.opacity(0.08)
        }
        if asset.userDecision == .rejected {
            return Color.red.opacity(0.06)
        }
        return Color.secondary.opacity(0.05)
    }

    private var statusBorderColor: Color {
        if asset.userDecision == .picked {
            return Color.green.opacity(0.45)
        }
        if asset.userDecision == .rejected {
            return Color.red.opacity(0.42)
        }
        return .clear
    }

    private var selectionBorderColor: Color {
        isSelected ? .accentColor : .clear
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(color.opacity(0.92), in: Capsule())
            .foregroundStyle(.white)
    }
}

private struct SingleAssetView: View {
    let asset: MediaAsset
    let visibleAssets: [MediaAsset]

    @State private var image: NSImage?
    @State private var zoomScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            imageStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(asset.baseName)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(asset.dimensionsDescription)
                    .foregroundStyle(.secondary)
            }

            if !asset.issues.isEmpty {
                HStack {
                    ForEach(asset.issues) { issue in
                        Text(issue.label)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.9), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Spacer()
                }
            }
        }
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
