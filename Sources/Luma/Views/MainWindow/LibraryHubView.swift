import AppKit
import SwiftUI

/// Pixel-aligned to Stitch screen `9bd72cc1` — Library | Digital Darkroom.
struct LibraryHubView: View {
    @Bindable var store: ProjectStore
    @State private var searchText = ""
    @State private var useGridToggle = false
    @FocusState private var searchFieldFocused: Bool

    /// All Expeditions hub shows this many rows/tiles (2-col grid → 3 rows).
    private static let allHubExpeditionLimit = 6

    /// Bundled landscape (Picsum #1018) so Recent featured card can validate real-image hover scale.
    private static let recentExpeditionDemoImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "recent-expedition-demo", withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private var summaries: [ProjectSummary] {
        store.projectSummaries
    }

    /// Slots used by the Recent bento (indices 0..<n), aligned with `recentBentoAlignedRow` / narrow stack.
    private var recentExpeditionSlots: Int {
        switch summaries.count {
        case 0: return 0
        case 1: return 1
        case 2: return 2
        default: return 3
        }
    }

    /// Expeditions for All Expeditions block: skip Recent slots, cap at 6.
    private var allHubSummaries: [ProjectSummary] {
        Array(summaries.dropFirst(recentExpeditionSlots).prefix(Self.allHubExpeditionLimit))
    }

    private var hasOverflowExpeditions: Bool {
        summaries.count > recentExpeditionSlots + Self.allHubExpeditionLimit
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let pad = horizontalPadding(forWidth: width)
            VStack(spacing: 0) {
                topAppBar(horizontalPadding: pad)
                ScrollView {
                    VStack(alignment: .leading, spacing: sectionSpacing(forWidth: width)) {
                        pageHeader(forWidth: width)
                        recentExpeditionsSection(containerWidth: width - pad * 2)
                        bottomSection(containerWidth: width - pad * 2)
                    }
                    .padding(pad)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(StitchTheme.background)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(StitchTheme.background)
    }

    private func horizontalPadding(forWidth width: CGFloat) -> CGFloat {
        max(16, min(40, width * 0.035))
    }

    private func sectionSpacing(forWidth width: CGFloat) -> CGFloat {
        width < 720 ? 28 : 40
    }

    // MARK: - Top bar (fixed height 64, Stitch header)

    private func topAppBar(horizontalPadding pad: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 16) {
                searchField
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: min(32, pad + 8)) {
                archiveHealthBlock
                HStack(spacing: 8) {
                    StitchToolbarIconCircleButton(systemName: "archivebox", action: {})
                    StitchToolbarIconCircleButton(systemName: "gearshape", action: {})
                }
            }
        }
        .padding(.horizontal, pad)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(StitchTheme.topBarBackground)
    }

    private var searchField: some View {
        HStack(spacing: 0) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(StitchTheme.outline)
                .frame(width: 40, alignment: .center)
            TextField("Smart Search (Expeditions, Dates, Tags...)", text: $searchText)
                .textFieldStyle(.plain)
                .font(StitchTypography.searchField)
                .foregroundStyle(StitchTheme.onSurface)
                .focused($searchFieldFocused)
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .background(StitchTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(StitchTheme.primary.opacity(searchFieldFocused ? 0.85 : 0), lineWidth: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: searchFieldFocused)
    }

    private var archiveHealthBlock: some View {
        HStack(spacing: 16) {
            VStack(alignment: .trailing, spacing: 4) {
                Text("Archive Health")
                    .font(StitchTypography.archiveHealthCaption)
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(2.4)
                Text("98.4% SECURE")
                    .font(StitchTypography.archiveHealthValue)
                    .foregroundStyle(StitchTheme.tertiary)
            }
            ZStack {
                Circle()
                    .stroke(StitchTheme.surfaceContainerHighest, lineWidth: 2)
                    .frame(width: 40, height: 40)
                Circle()
                    .trim(from: 0, to: 0.97)
                    .stroke(StitchTheme.tertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 40, height: 40)
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    // MARK: - Page header

    private func pageHeader(forWidth width: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Library")
                    .font(width < 640 ? StitchTypography.font(size: 24, weight: .heavy) : StitchTypography.libraryTitle)
                    .foregroundStyle(StitchTheme.onSurface)
                    .tracking(-0.6)
                Text("Manage your professional photographic expeditions.")
                    .font(StitchTypography.librarySubtitle)
                    .foregroundStyle(StitchTheme.outline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.openProjectLibrary()
            } label: {
                HStack(spacing: 8) {
                    newExpeditionAddPhotoIcon
                    Text("New Expedition")
                        .font(StitchTypography.newExpeditionLabel)
                        .foregroundStyle(StitchTheme.onPrimary)
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [StitchTheme.primary, StitchTheme.primaryContainer],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .tint(nil)
            .stitchHoverDimming()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Stitch `add_a_photo`: `camera.fill` + `plus` badge at the **top-trailing** corner of the camera glyph.
    private var newExpeditionAddPhotoIcon: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(StitchTheme.onPrimary)
            .overlay(alignment: .topTrailing) {
                Image(systemName: "plus")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(StitchTheme.onPrimary)
                    .offset(x: 4, y: -4)
            }
    }

    // MARK: - Recent bento

    private func recentExpeditionsSection(containerWidth width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("Recent Expeditions")
                    .font(StitchTypography.sectionHeading)
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(StitchTypography.sectionHeadingTracking)
                Spacer(minLength: 8)
                LibraryViewAllLink(title: "View All") {
                    store.openAllExpeditionsGallery(layout: .list)
                }
            }

            if summaries.isEmpty {
                emptyRecentPlaceholder
            } else if width >= 800 {
                recentBentoAlignedRow(containerWidth: width)
            } else {
                recentBentoNarrowStack
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Matches Stitch `grid-cols-3`: featured 2/3 width 16:9; right column fills same total height with two stacked slots (`gap-6`).
    private func recentBentoAlignedRow(containerWidth width: CGFloat) -> some View {
        let gap: CGFloat = 24
        let leftW = max(0, (width - gap) * 2 / 3)
        let rightW = max(0, (width - gap) / 3)
        let leftH = leftW * 9 / 16
        let subH = max(0, (leftH - gap) / 2)
        return HStack(alignment: .top, spacing: gap) {
            featuredCard(index: 0, width: leftW, height: leftH)
            VStack(spacing: gap) {
                if summaries.count > 1 {
                    secondaryCard(index: 1, width: rightW, height: subH)
                } else {
                    secondaryPlaceholder(width: rightW, height: subH)
                }
                if summaries.count > 2 {
                    secondaryCard(index: 2, width: rightW, height: subH)
                } else {
                    secondaryPlaceholder(width: rightW, height: subH)
                }
            }
            .frame(width: rightW, height: leftH, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentBentoNarrowStack: some View {
        VStack(alignment: .leading, spacing: 24) {
            featuredCardFlexible(index: 0)
            if summaries.count > 1 {
                HStack(alignment: .top, spacing: 16) {
                    secondaryCardFlexible(index: 1)
                        .frame(maxWidth: .infinity)
                    if summaries.count > 2 {
                        secondaryCardFlexible(index: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyRecentPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(StitchTheme.surfaceContainerLow)
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(StitchTheme.outline)
                    Text("No expeditions yet")
                        .font(StitchTypography.font(size: 16, weight: .semibold))
                        .foregroundStyle(StitchTheme.onSurface)
                    Text("Create a project or import to see recent work here.")
                        .font(StitchTypography.font(size: 12, weight: .regular))
                        .foregroundStyle(StitchTheme.outline)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            }
    }

    private func featuredCard(index: Int, width: CGFloat, height: CGFloat) -> some View {
        let s = summaries[index]
        return expeditionCardButton(summary: s) {
            ZStack(alignment: .bottomLeading) {
                recentFeaturedImage(seed: s.id)
                    .frame(width: width, height: height)
                LinearGradient(
                    colors: [
                        StitchTheme.surfaceContainerLowest.opacity(0.95),
                        Color.clear,
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .allowsHitTesting(false)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LATEST SYNC")
                            .font(StitchTypography.latestSyncBadge)
                            .foregroundStyle(StitchTheme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(StitchTheme.primary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        Text(s.name)
                            .font(StitchTypography.featuredTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(recentSubtitle(for: s))
                            .font(StitchTypography.featuredMeta)
                            .foregroundStyle(StitchTheme.outline)
                    }
                    Spacer(minLength: 8)
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "arrow.forward")
                                .foregroundStyle(.white)
                        }
                }
                .padding(32)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func featuredCardFlexible(index: Int) -> some View {
        let s = summaries[index]
        return expeditionCardButton(summary: s) {
            ZStack(alignment: .bottomLeading) {
                recentFeaturedImage(seed: s.id)
                LinearGradient(
                    colors: [
                        StitchTheme.surfaceContainerLowest.opacity(0.95),
                        Color.clear,
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .allowsHitTesting(false)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("LATEST SYNC")
                            .font(StitchTypography.latestSyncBadge)
                            .foregroundStyle(StitchTheme.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(StitchTheme.primary.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
                        Text(s.name)
                            .font(StitchTypography.featuredTitle)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                        Text(recentSubtitle(for: s))
                            .font(StitchTypography.featuredMeta)
                            .foregroundStyle(StitchTheme.outline)
                    }
                    Spacer(minLength: 8)
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 48, height: 48)
                        .overlay {
                            Image(systemName: "arrow.forward")
                                .foregroundStyle(.white)
                        }
                }
                .padding(32)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private func secondaryCard(index: Int, width: CGFloat, height: CGFloat) -> some View {
        let s = summaries[index]
        return expeditionCardButton(summary: s) {
            ZStack(alignment: .bottomLeading) {
                expeditionImageLayer(seed: s.id)
                    .stitchImageHoverScale(1.1, duration: 0.5)
                    .frame(width: width, height: height)
                LinearGradient(
                    colors: [StitchTheme.surfaceContainerLowest.opacity(0.8), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name)
                        .font(StitchTypography.secondaryTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(shortSubtitle(for: s))
                        .font(StitchTypography.secondaryMeta)
                        .foregroundStyle(StitchTheme.outline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(16)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func secondaryCardFlexible(index: Int) -> some View {
        let s = summaries[index]
        return expeditionCardButton(summary: s) {
            ZStack(alignment: .bottomLeading) {
                expeditionImageLayer(seed: s.id)
                    .stitchImageHoverScale(1.1, duration: 0.5)
                LinearGradient(
                    colors: [StitchTheme.surfaceContainerLowest.opacity(0.8), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.name)
                        .font(StitchTypography.secondaryTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(shortSubtitle(for: s))
                        .font(StitchTypography.secondaryMeta)
                        .foregroundStyle(StitchTheme.outline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .aspectRatio(16 / 9, contentMode: .fit)
        }
    }

    private func secondaryPlaceholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(StitchTheme.surfaceContainerLow)
            .frame(width: width, height: height)
    }

    private func expeditionCardButton<Content: View>(summary: ProjectSummary, @ViewBuilder label: () -> Content) -> some View {
        Button {
            if case .ready = summary.state { store.openProject(summary) }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom: list + archive

    private func bottomSection(containerWidth width: CGFloat) -> some View {
        Group {
            if width >= 960 {
                HStack(alignment: .top, spacing: 40) {
                    allExpeditionsColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                    archiveStatusColumn
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: min(380, width * 0.34))
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                VStack(alignment: .leading, spacing: 32) {
                    allExpeditionsColumn
                    archiveStatusColumn
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var allExpeditionsColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center) {
                Text("All Expeditions")
                    .font(StitchTypography.sectionHeading)
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(StitchTypography.sectionHeadingTracking)
                Spacer(minLength: 8)
                expeditionLayoutToggle
            }

            VStack(spacing: 0) {
                if summaries.isEmpty {
                    Text("No expeditions in library.")
                        .font(StitchTypography.font(size: 13, weight: .regular))
                        .foregroundStyle(StitchTheme.outline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else if allHubSummaries.isEmpty {
                    Text("No additional expeditions beyond those in Recent.")
                        .font(StitchTypography.font(size: 13, weight: .regular))
                        .foregroundStyle(StitchTheme.outline)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(24)
                } else if useGridToggle {
                    allExpeditionsHubGrid
                } else {
                    ForEach(Array(allHubSummaries.enumerated()), id: \.element.id) { idx, summary in
                        expeditionRow(summary, showTopBorder: idx > 0)
                    }
                }
                if hasOverflowExpeditions {
                    openGalleryLinkRow
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StitchTheme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allExpeditionsHubGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
        ]
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(allHubSummaries) { summary in
                hubGridCell(summary)
            }
        }
        .padding(12)
    }

    private func hubGridCell(_ summary: ProjectSummary) -> some View {
        Button {
            if case .ready = summary.state { store.openProject(summary) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowThumbGradient(summary.id))
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(StitchTypography.listRowTitle)
                            .foregroundStyle(StitchTheme.onSurface)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(shortSubtitle(for: summary))
                            .font(StitchTypography.secondaryMeta)
                            .foregroundStyle(StitchTheme.outline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ExpeditionMoreVertIndicator()
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StitchTheme.surfaceContainerLowest.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .stitchSubtleCardHover()
        }
        .buttonStyle(.plain)
    }

    private var openGalleryLinkRow: some View {
        Button {
            store.openAllExpeditionsGallery(layout: useGridToggle ? .grid : .list)
        } label: {
            HStack {
                Text("Luma - All Expeditions Gallery")
                    .font(StitchTypography.viewAllLink)
                    .foregroundStyle(StitchTheme.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StitchTheme.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .stitchListRowHoverBackground()
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(StitchTheme.outlineVariant.opacity(0.1))
                .frame(height: 1)
                .padding(.horizontal, 16)
        }
    }

    /// Stitch: `grid_view` / `list` pair; selected uses `bg-surface-container-high`.
    private var expeditionLayoutToggle: some View {
        HStack(spacing: 2) {
            LayoutToggleSegmentButton(
                systemName: "square.grid.2x2",
                isSelected: useGridToggle
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    useGridToggle = true
                }
            }
            LayoutToggleSegmentButton(
                systemName: "list.bullet",
                isSelected: !useGridToggle
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    useGridToggle = false
                }
            }
        }
        .padding(3)
        .background(StitchTheme.surfaceContainerLowest.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func expeditionRow(_ summary: ProjectSummary, showTopBorder: Bool) -> some View {
        ZStack(alignment: .trailing) {
            Button {
                if case .ready = summary.state { store.openProject(summary) }
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(rowThumbGradient(summary.id))
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(summary.name)
                            .font(StitchTypography.listRowTitle)
                            .foregroundStyle(StitchTheme.onSurface)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Text(rowMeta(for: summary))
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
                    // Reserve trailing gutter so row tap doesn’t cover the ⋮ affordance.
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

    private var archiveStatusColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Archive Status")
                .font(StitchTypography.sectionHeading)
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(StitchTypography.sectionHeadingTracking)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Storage Capacity")
                            .font(StitchTypography.archiveRowLabel)
                            .foregroundStyle(StitchTheme.onSurface)
                        Spacer(minLength: 8)
                        Text("1.2TB / 2TB Used")
                            .font(StitchTypography.archiveRowLabel)
                            .foregroundStyle(StitchTheme.outline)
                            .multilineTextAlignment(.trailing)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(StitchTheme.surfaceContainerLowest)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [StitchTheme.primary, StitchTheme.primaryContainer],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, g.size.width * 0.6))
                        }
                    }
                    .frame(height: 8)
                    .frame(maxWidth: .infinity)
                }

                VStack(spacing: 16) {
                    archiveBreakdownRow(dot: StitchTheme.primary, title: "RAW Masters", value: "842 GB")
                    archiveBreakdownRow(dot: StitchTheme.tertiary, title: "Smart Previews", value: "128 GB")
                    archiveBreakdownRow(dot: StitchTheme.primary.opacity(0.85), title: "Exports", value: "230 GB")
                }

                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                        .background(StitchTheme.outlineVariant.opacity(0.2))
                        .padding(.vertical, 8)
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(StitchTheme.tertiary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Vault Verification Complete")
                                .font(StitchTypography.vaultHeading)
                                .foregroundStyle(StitchTheme.onSurface)
                            Text("Redundancy checks passed. 3,248 files mirrored to Obsidian Cold Storage.")
                                .font(StitchTypography.vaultBody)
                                .foregroundStyle(StitchTheme.outline)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                Button("Run Deep Integrity Scan") {}
                    .font(StitchTypography.integrityButton)
                    .foregroundStyle(StitchTheme.onSurface)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(StitchTheme.surfaceContainerHigh, in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(StitchTheme.outlineVariant.opacity(0.1), lineWidth: 1)
                    }
                    .buttonStyle(.plain)
                    .stitchHoverDimming(opacity: 0.94)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StitchTheme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func archiveBreakdownRow(dot: Color, title: String, value: String) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Circle()
                    .fill(dot)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(StitchTypography.archiveRowLabel)
                    .foregroundStyle(StitchTheme.onSurface)
            }
            Spacer(minLength: 8)
            Text(value)
                .font(StitchTypography.archiveMono)
                .foregroundStyle(StitchTheme.outline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StitchTheme.surfaceContainerLowest, in: RoundedRectangle(cornerRadius: 8))
        .stitchSubtleCardHover(cornerRadius: 8)
    }

    // MARK: - Helpers

    private func recentSubtitle(for summary: ProjectSummary) -> String {
        let date = summary.createdAt.formatted(.dateTime.month(.wide).day().year())
        switch summary.state {
        case .ready(let n, _):
            return "\(date) • \(n) RAW Items"
        case .unavailable:
            return date
        }
    }

    private func shortSubtitle(for summary: ProjectSummary) -> String {
        let d = summary.createdAt.formatted(date: .abbreviated, time: .omitted)
        switch summary.state {
        case .ready(let n, _):
            return "\(d) • \(n) Items"
        case .unavailable(let r):
            return r
        }
    }

    private func rowMeta(for summary: ProjectSummary) -> String {
        let kind = "Project"
        let m = summary.createdAt.formatted(.dateTime.month(.abbreviated).year())
        return "\(kind) • \(m)"
    }

    /// Recent bento **featured** slot only: real JPEG from bundle (falls back to gradient if missing).
    @ViewBuilder
    private func recentFeaturedImage(seed: URL) -> some View {
        if let img = Self.recentExpeditionDemoImage {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .stitchImageHoverScale(1.05, duration: 0.7)
        } else {
            expeditionImageLayer(seed: seed)
                .stitchImageHoverScale(1.05, duration: 0.7)
        }
    }

    @ViewBuilder
    private func expeditionImageLayer(seed: URL) -> some View {
        LinearGradient(
            colors: gradientColors(for: seed),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func gradientColors(for id: URL) -> [Color] {
        let h = abs(id.hashValue % 360)
        let c1 = Color(hue: Double(h) / 360.0, saturation: 0.35, brightness: 0.22)
        let c2 = Color(hue: Double((h + 40) % 360) / 360.0, saturation: 0.45, brightness: 0.14)
        return [c1, c2]
    }

    private func rowThumbGradient(_ id: URL) -> LinearGradient {
        let h = abs(id.hashValue % 360)
        let c1 = Color(hue: Double(h) / 360.0, saturation: 0.4, brightness: 0.35)
        let c2 = Color(hue: Double((h + 50) % 360) / 360.0, saturation: 0.5, brightness: 0.2)
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private struct LibraryViewAllLink: View {
    let title: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(StitchTypography.viewAllLink)
                .foregroundStyle(StitchTheme.primary)
                .underline(hovered, color: StitchTheme.primary)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct LayoutToggleSegmentButton: View {
    let systemName: String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isSelected ? StitchTheme.onSurface : StitchTheme.outline)
                .frame(width: 32, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(segmentFill)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: hovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { hovered = $0 }
    }

    private var segmentFill: Color {
        if isSelected { return StitchTheme.surfaceContainerHigh }
        if hovered { return StitchTheme.surfaceContainerLow }
        return .clear
    }
}
