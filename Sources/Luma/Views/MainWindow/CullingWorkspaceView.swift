import SwiftUI

/// Culling workspace — faithful to Stitch `0f5e0736383e487c811a71af096f3400.html`.
/// Layout: header bar + [left Smart Groups sidebar | center preview | right detail panel].
struct CullingWorkspaceView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            cullingHeader
            HStack(spacing: 0) {
                smartGroupsSidebar
                    .frame(width: 288)
                centerPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                rightDetailPanel
                    .frame(width: 384)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(StitchTheme.surface)
    }

    // MARK: - Header (h-14, bg-stone-950/80, backdrop-blur-xl)

    private var cullingHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Text("Library")
                    .foregroundStyle(Color(white: 0.42))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.42))
                Text("Expeditions")
                    .foregroundStyle(Color(white: 0.42))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.42))
                Text(store.projectName)
                    .foregroundStyle(Color(white: 0.42))
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.42))
                Text("Culling")
                    .foregroundStyle(Color(white: 0.93))
                    .fontWeight(.bold)
            }
            .font(StitchTypography.font(size: 12, weight: .regular))
            .textCase(.uppercase)
            .tracking(1.2)

            Spacer()

            HStack(spacing: 24) {
                HStack(spacing: 24) {
                    Text("Sessions")
                        .foregroundStyle(Color(white: 0.42))
                    Text(store.projectName)
                        .foregroundStyle(Color(white: 0.93))
                        .fontWeight(.bold)
                }
                .font(StitchTypography.font(size: 12, weight: .regular))
                .textCase(.uppercase)
                .tracking(1.2)

                Rectangle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 1, height: 20)

                HStack(spacing: 12) {
                    CullingHeaderIcon(systemName: "bell")
                    CullingHeaderIcon(systemName: "gearshape")
                }
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 56)
        .background(Color(red: 0.04, green: 0.04, blue: 0.04).opacity(0.8))
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    // MARK: - Left sidebar: Smart Groups (w-72)

    private var smartGroupsSidebar: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Smart Groups")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Text("AI-clustered by location & time")
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
                    ForEach(store.groups) { group in
                        SmartGroupRow(
                            group: group,
                            isSelected: store.selectedGroupID == group.id,
                            summary: store.summary(for: group),
                            allAssets: store.assets
                        ) {
                            store.selectGroup(group.id)
                        }
                    }
                }
                .padding(8)
            }
        }
        .background(StitchTheme.surfaceContainerLow)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
        }
    }

    // MARK: - Center preview (flex-1, bg-black)

    private var centerPreview: some View {
        ZStack {
            Color.black

            if let asset = store.selectedAsset {
                ZStack(alignment: .topLeading) {
                    AsyncImage(url: asset.primaryDisplayURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        default:
                            ProgressView()
                                .tint(StitchTheme.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if asset.aiScore != nil {
                        aiBestPickBadge
                    }

                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            confidenceScore(for: asset)
                        }
                    }
                    .padding(16)
                }
                .padding(24)
                .frame(maxWidth: 944, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(Color(white: 0.3))
                    Text("Select a photo to preview")
                        .font(StitchTypography.font(size: 12, weight: .regular))
                        .foregroundStyle(Color(white: 0.3))
                }
            }
        }
    }

    private var aiBestPickBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
            Text("AI Best Pick")
                .font(StitchTypography.font(size: 10, weight: .bold))
                .textCase(.uppercase)
                .tracking(1)
        }
        .foregroundStyle(StitchTheme.onPrimaryContainer)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(StitchTheme.primaryContainer, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 8, y: 2)
        .padding(16)
    }

    private func confidenceScore(for asset: MediaAsset) -> some View {
        VStack(spacing: 4) {
            Text("\(asset.aiScore?.overall ?? 0)")
                .font(StitchTypography.font(size: 24, weight: .bold))
                .foregroundStyle(StitchTheme.primary)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.8))
                        .background(.ultraThinMaterial, in: Circle())
                )
                .overlay {
                    Circle().stroke(StitchTheme.primary.opacity(0.4), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.4), radius: 8, y: 2)
            Text("Confidence")
                .font(StitchTypography.font(size: 9, weight: .bold))
                .foregroundStyle(StitchTheme.primary.opacity(0.7))
                .textCase(.uppercase)
                .tracking(1.2)
        }
    }

    // MARK: - Right detail panel (w-96)

    private var rightDetailPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Selected Group Details")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(1.2)
                Spacer()
                Button {
                    store.selectRecommendedInCurrentScope()
                } label: {
                    Text("Pick All")
                        .font(StitchTypography.font(size: 10, weight: .bold))
                        .foregroundStyle(StitchTheme.primary)
                        .textCase(.uppercase)
                }
                .buttonStyle(.plain)
            }
            .padding(16)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if let asset = store.selectedAsset {
                        selectedAssetDetail(asset)
                    }
                    filmstripGrid
                }
            }
            .background(StitchTheme.surfaceContainerLow)

            bottomActions
        }
        .background(StitchTheme.surfaceContainer)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(width: 1)
        }
    }

    @ViewBuilder
    private func selectedAssetDetail(_ asset: MediaAsset) -> some View {
        let isSelected = asset.userDecision == .picked

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    AsyncImage(url: asset.primaryDisplayURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color(white: 0.15)
                        }
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                    if isSelected {
                        Color(StitchTheme.primary).opacity(0.1)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(isSelected ? StitchTheme.primary : Color.clear, lineWidth: 2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(asset.baseName)
                            .font(StitchTypography.font(size: 10, weight: .bold))
                            .foregroundStyle(StitchTheme.onSurface)
                            .textCase(.uppercase)
                            .lineLimit(1)
                        Spacer()
                        if let score = asset.aiScore {
                            Text("\(score.overall)% AI Match")
                                .font(StitchTypography.font(size: 10, weight: .bold))
                                .foregroundStyle(StitchTheme.primary)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        exifLabel("ISO \(asset.metadata.iso ?? 0)")
                        exifLabel(asset.metadata.shutterSpeed ?? "—")
                        exifLabel("f/\(String(format: "%.1f", asset.metadata.aperture ?? 0))")
                        exifLabel("\(Int(asset.metadata.focalLength ?? 0))mm")
                    }

                    if let suggestions = asset.editSuggestions {
                        let tags = [
                            suggestions.filterStyle?.primary,
                            suggestions.crop?.needed == true ? "Crop" : nil,
                        ].compactMap { $0 }
                        if !tags.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(StitchTypography.font(size: 8, weight: .regular))
                                        .foregroundStyle(StitchTheme.onSurfaceVariant)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(StitchTheme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(8)
            .padding(.bottom, 8)

            if let aiScore = asset.aiScore {
                autoAnalysisCard(aiScore: aiScore)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
            }

            HStack(spacing: 8) {
                Button {
                    store.markSelection(.picked)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .regular))
                        Text("Keep")
                            .font(StitchTypography.font(size: 10, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(StitchTheme.onPrimary)
                    .background(StitchTheme.primary, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    store.markSelection(.rejected)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .regular))
                        Text("Reject")
                            .font(StitchTypography.font(size: 10, weight: .bold))
                            .textCase(.uppercase)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .foregroundStyle(StitchTheme.onSurface)
                    .background(StitchTheme.surfaceContainerHighest, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(isSelected ? StitchTheme.primary.opacity(0.05) : Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(isSelected ? StitchTheme.primary.opacity(0.2) : Color.white.opacity(0.05)).frame(height: 1)
        }
    }

    private func autoAnalysisCard(aiScore: AIScore) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(StitchTheme.primary)
                Text("Auto Analysis")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }

            analysisRow(label: "Sharpness", value: aiScore.scores.sharpness)
            analysisRow(label: "Composition", value: aiScore.scores.composition)
        }
        .padding(12)
        .background(StitchTheme.surfaceContainerLowest.opacity(0.8), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
    }

    private func analysisRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(StitchTypography.font(size: 10, weight: .regular))
                .foregroundStyle(StitchTheme.onSurfaceVariant)
            Spacer()
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 64, height: 4)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(StitchTheme.primary)
                        .frame(width: 64 * CGFloat(value) / 100, height: 4)
                }
                Text("\(value)%")
                    .font(StitchTypography.font(size: 9, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
            }
        }
    }

    private func exifLabel(_ text: String) -> some View {
        Text(text)
            .font(StitchTypography.font(size: 9, weight: .regular))
            .foregroundStyle(StitchTheme.outline)
    }

    // MARK: - Filmstrip grid (grid-cols-3, gap-1)

    private var filmstripGrid: some View {
        let assets = store.visibleAssets
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
            ForEach(assets) { asset in
                FilmstripTile(
                    asset: asset,
                    isSelected: store.selectedAssetID == asset.id
                ) {
                    store.selectAsset(asset.id)
                }
            }
        }
        .padding(4)
    }

    // MARK: - Bottom actions

    private var bottomActions: some View {
        VStack(spacing: 8) {
            Button {
                store.selectRecommendedInCurrentScope()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                    Text("Apply All AI Suggestions")
                        .font(StitchTypography.font(size: 12, weight: .bold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                .foregroundStyle(StitchTheme.onPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [StitchTheme.primary, StitchTheme.primaryContainer],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .shadow(color: StitchTheme.primary.opacity(0.2), radius: 8, y: 2)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {} label: {
                    Text("Select Similar")
                        .font(StitchTypography.font(size: 9, weight: .bold))
                        .foregroundStyle(StitchTheme.outline)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(StitchTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)

                Button {
                    for asset in store.visibleAssets where asset.userDecision == .pending {
                        store.selectAsset(asset.id)
                        store.markSelection(.rejected)
                    }
                } label: {
                    Text("Reject Rest")
                        .font(StitchTypography.font(size: 9, weight: .bold))
                        .foregroundStyle(StitchTheme.outline)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(StitchTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(StitchTheme.surfaceContainerLow)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
    }
}

// MARK: - Subviews

private struct CullingHeaderIcon: View {
    let systemName: String
    @State private var hovered = false

    var body: some View {
        Button {} label: {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(hovered ? Color(white: 0.93) : Color(white: 0.42))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct SmartGroupRow: View {
    let group: PhotoGroup
    let isSelected: Bool
    let summary: GroupDecisionSummary
    let allAssets: [MediaAsset]
    let onSelect: () -> Void
    @State private var isHovered = false

    private var groupAssets: [MediaAsset] {
        group.assets.compactMap { id in allAssets.first(where: { $0.id == id }) }
    }

    private var thumbURL: URL? {
        groupAssets.first?.primaryDisplayURL
    }

    private var timeString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "hh:mm a"
        return f.string(from: group.timeRange.lowerBound)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    AsyncImage(url: thumbURL) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        default:
                            Color(white: 0.15)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .grayscale(isSelected || isHovered ? 0 : 1)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.name)
                            .font(StitchTypography.font(size: 14, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? StitchTheme.primary : StitchTheme.onSurface)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("\(group.assets.count) Photos • \(timeString)")
                            .font(StitchTypography.font(size: 10, weight: .regular))
                            .foregroundStyle(StitchTheme.outline)
                    }
                }

                if isSelected {
                    GroupProgressBar(summary: summary)
                        .frame(height: 6)

                    HStack {
                        Text("\(summary.picked) P")
                        Spacer()
                        Text("\(summary.rejected) R")
                        Spacer()
                        Text("\(summary.pending) U")
                    }
                    .font(StitchTypography.font(size: 10, weight: .medium))
                    .foregroundStyle(StitchTheme.outline)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? StitchTheme.surfaceContainerHighest : (isHovered ? StitchTheme.surfaceContainerHigh : Color.clear))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(StitchTheme.primary.opacity(0.2), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct FilmstripTile: View {
    let asset: MediaAsset
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: asset.primaryDisplayURL) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color(white: 0.15)
                    }
                }
                .frame(height: 96)
                .clipped()

                if let score = asset.aiScore {
                    Text("\(score.overall)")
                        .font(StitchTypography.font(size: 8, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                        .padding(4)
                }
            }
            .opacity(isSelected || isHovered ? 1 : 0.8)
            .overlay {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(StitchTheme.primary, lineWidth: 2)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
                RoundedRectangle(cornerRadius: 3)
                    .fill(StitchTheme.primary)
                    .frame(width: pw)
                RoundedRectangle(cornerRadius: 0)
                    .fill(StitchTheme.tertiary)
                    .frame(width: rw)
                RoundedRectangle(cornerRadius: 3)
                    .fill(StitchTheme.surfaceVariant)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }
}
