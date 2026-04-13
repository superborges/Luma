import AppKit
import SwiftUI

/// All Expeditions — pixel-faithful to Stitch `dbda147ad6c747c2916dd28a3e0c28a8.html` (main column only).
struct AllExpeditionsGalleryView: View {
    @Bindable var store: ProjectStore
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool
    @State private var carouselFocusIndex: Int = 0
    @State private var heroEnterHovered = false
    @State private var smartImportHovered = false
    @State private var newExpeditionCardHovered = false

    /// Tailwind `px-8` on header
    private let headerHorizontalPadding: CGFloat = 32
    /// Tailwind `px-12` / hero `p-12`
    private let sectionHorizontalPadding: CGFloat = 48

    private static let demoHeroImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "recent-expedition-demo", withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private var filteredSummaries: [ProjectSummary] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return store.projectSummaries }
        return store.projectSummaries.filter {
            $0.name.localizedCaseInsensitiveContains(q)
        }
    }

    private var orderedCarouselSummaries: [ProjectSummary] {
        filteredSummaries.sorted { $0.createdAt > $1.createdAt }
    }

    private var heroSummary: ProjectSummary? {
        let all = store.projectSummaries
        if let cur = all.first(where: { $0.isCurrent && $0.isOpenable }) { return cur }
        return all.first(where: { $0.isOpenable }) ?? all.first
    }

    private var activeExpeditionCount: Int {
        store.projectSummaries.filter(\.isOpenable).count
    }

    private var archivedExpeditionCount: Int {
        store.projectSummaries.filter { !$0.isOpenable }.count
    }

    private static let newExpeditionScrollID = "__luma_new_expedition__"

    /// Tailwind `h-[716px]` cap; scales down on short windows.
    private func heroHeight(in containerHeight: CGFloat) -> CGFloat {
        min(716, max(300, containerHeight * 0.52))
    }

    var body: some View {
        GeometryReader { geo in
            let heroH = heroHeight(in: geo.size.height)

            ZStack(alignment: .top) {
                StitchTheme.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    heroSection(width: geo.size.width, height: heroH)
                    continueExploringSection(containerHeight: geo.size.height - heroH)
                }

                floatingHeader
                    .frame(height: 64)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .onAppear {
                store.refreshProjectSummaries()
                carouselFocusIndex = 0
            }
            .onChange(of: searchText) { _, _ in
                carouselFocusIndex = min(carouselFocusIndex, max(0, orderedCarouselSummaries.count))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            smartImportFAB
                .scaleEffect(smartImportHovered ? 1.05 : 1)
                .animation(.easeOut(duration: 0.2), value: smartImportHovered)
                .padding(.trailing, 48)
                .padding(.bottom, 48)
        }
    }

    // MARK: - Header (`h-16`, `px-8`)

    private var floatingHeader: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 32) {
                HStack(spacing: 16) {
                    Button {
                        store.closeAllExpeditionsGallery()
                    } label: {
                        Text("Library")
                            .font(StitchTypography.font(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .textCase(.uppercase)
                            .tracking(2)
                    }
                    .buttonStyle(.plain)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.3))

                    Text("All Expeditions")
                        .font(StitchTypography.font(size: 10, weight: .bold))
                        .foregroundStyle(Color.white)
                        .textCase(.uppercase)
                        .tracking(2)
                }
            }

            Spacer(minLength: 24)

            // `relative w-64` search
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.09, blue: 0.09).opacity(0.4))
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(Color.white.opacity(0.05), lineWidth: 1)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .stroke(StitchTheme.primary.opacity(searchFieldFocused ? 1 : 0), lineWidth: 1)
                    }

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(red: 0.64, green: 0.64, blue: 0.64))
                    .scaleEffect(0.75)
                    .padding(.leading, 8)
                    .allowsHitTesting(false)

                TextField("Smart Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(StitchTheme.onSurface)
                    .focused($searchFieldFocused)
                    .padding(.leading, 32)
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
            }
            .frame(width: 256)
            .animation(.easeInOut(duration: 0.2), value: searchFieldFocused)
        }
        .padding(.horizontal, headerHorizontalPadding)
    }

    // MARK: - Hero (`h-[716px]`, gradients, `p-12`)

    private func heroSection(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let img = Self.demoHeroImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [
                            Color(hue: 0.55, saturation: 0.35, brightness: 0.22),
                            StitchTheme.surfaceContainerLowest,
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                }
            }
            .frame(width: width, height: height)
            .clipped()

            // `bg-gradient-to-t from-background via-transparent to-background/40`
            LinearGradient(
                stops: [
                    .init(color: StitchTheme.background, location: 0),
                    .init(color: Color.clear, location: 0.45),
                    .init(color: StitchTheme.background.opacity(0.4), location: 1),
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .allowsHitTesting(false)

            // `bg-gradient-to-r from-background/80 via-transparent to-transparent`
            LinearGradient(
                stops: [
                    .init(color: StitchTheme.background.opacity(0.8), location: 0),
                    .init(color: Color.clear, location: 0.45),
                    .init(color: Color.clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .allowsHitTesting(false)

            HStack(alignment: .bottom, spacing: 0) {
                heroCopyBlock
                    .frame(maxWidth: 672, alignment: .leading)

                Spacer(minLength: 16)

                if width >= 1024 {
                    heroGlassStats
                }
            }
            .padding(sectionHorizontalPadding)
            .padding(.top, 64)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var heroCopyBlock: some View {
        if let s = heroSummary {
            VStack(alignment: .leading, spacing: 0) {
                Text("Current Expedition")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.primary)
                    .textCase(.uppercase)
                    .tracking(3)
                    .padding(.bottom, 16)

                Text(s.name)
                    .font(StitchTypography.font(size: 72, weight: .bold))
                    .foregroundStyle(Color.white)
                    .tracking(-2.5)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
                    .lineSpacing(-4)
                    .padding(.bottom, 24)

                HStack(alignment: .center, spacing: 32) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dates")
                            .font(StitchTypography.font(size: 9, weight: .medium))
                            .foregroundStyle(StitchTheme.outline.opacity(0.7))
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Text(heroDateLine(for: s))
                            .font(StitchTypography.font(size: 18, weight: .medium))
                            .foregroundStyle(Color.white)
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 1, height: 32)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Assets")
                            .font(StitchTypography.font(size: 9, weight: .medium))
                            .foregroundStyle(StitchTheme.outline.opacity(0.7))
                            .textCase(.uppercase)
                            .tracking(0.6)
                        Text(heroAssetLine(for: s))
                            .font(StitchTypography.font(size: 18, weight: .medium))
                            .foregroundStyle(Color.white)
                    }

                    if s.isOpenable {
                        Button {
                            store.openProject(s)
                        } label: {
                            Text("Enter Journey")
                                .font(StitchTypography.font(size: 12, weight: .bold))
                                .foregroundStyle(heroEnterHovered ? StitchTheme.onPrimary : Color.black)
                                .textCase(.uppercase)
                                .tracking(3)
                                .padding(.horizontal, 32)
                                .padding(.vertical, 12)
                                .background(heroEnterHovered ? StitchTheme.primary : Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 16)
                        .onHover { heroEnterHovered = $0 }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Current Expedition")
                    .font(StitchTypography.font(size: 10, weight: .bold))
                    .foregroundStyle(StitchTheme.primary)
                    .textCase(.uppercase)
                    .tracking(3)
                Text("No expeditions yet")
                    .font(StitchTypography.font(size: 56, weight: .bold))
                    .foregroundStyle(Color.white)
                    .minimumScaleFactor(0.5)
                Text("Import a session or open Expedition Library to add one.")
                    .font(StitchTypography.font(size: 13, weight: .regular))
                    .foregroundStyle(StitchTheme.outline)
                    .frame(maxWidth: 420, alignment: .leading)
                Button {
                    store.openProjectLibrary()
                } label: {
                    Text("Expedition Library")
                        .font(StitchTypography.font(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                        .textCase(.uppercase)
                        .tracking(3)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    /// `glass-panel`: rgba(53,53,52,0.4) blur; `rounded-xl` + `border-white/5`; `gap-12` `p-6` `mb-4`
    private var heroGlassStats: some View {
        HStack(spacing: 48) {
            statColumn(label: "Active", value: "\(activeExpeditionCount)", valueColor: StitchTheme.primary)
            statColumn(label: "Archived", value: "\(archivedExpeditionCount)", valueColor: StitchTheme.onSurface)
            statColumn(label: "Storage", value: "—", valueColor: StitchTheme.onSurface)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.208, green: 0.208, blue: 0.204).opacity(0.4))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        }
        .padding(.bottom, 16)
    }

    private func statColumn(label: String, value: String, valueColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(StitchTypography.font(size: 9, weight: .medium))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(1.8)
            Text(value)
                .font(StitchTypography.font(size: 24, weight: .bold))
                .foregroundStyle(valueColor)
        }
    }

    private static let heroMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f
    }()

    /// Stitch-style range line; end date is +14 days when only `createdAt` exists.
    private func heroDateLine(for summary: ProjectSummary) -> String {
        let d = summary.createdAt
        let end = Calendar.current.date(byAdding: .day, value: 14, to: d) ?? d
        let a = Self.heroMonthDayFormatter.string(from: d).uppercased()
        let b = Self.heroMonthDayFormatter.string(from: end).uppercased()
        return "\(a) - \(b)"
    }

    private func heroAssetLine(for summary: ProjectSummary) -> String {
        switch summary.state {
        case .ready(let n, _):
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
            return "\(formatted) RAW"
        case .unavailable:
            return "—"
        }
    }

    // MARK: - Continue exploring (`py-8`, `px-12`, `mb-4`, carousel `gap-6` `pb-8`)

    private func continueExploringSection(containerHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(alignment: .center) {
                Text("Continue Exploring")
                    .font(StitchTypography.font(size: 12, weight: .bold))
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(2.4)

                Spacer(minLength: 16)

                HStack(spacing: 8) {
                    layoutMenu
                    carouselNavArrows
                }
            }
            .padding(.horizontal, sectionHorizontalPadding)
            .padding(.bottom, 16)

            Group {
                if store.allExpeditionsGalleryLayout == .grid {
                    carouselRow
                } else {
                    listSection
                }
            }
            .padding(.bottom, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: max(0, containerHeight))
        .background(StitchTheme.background)
        .padding(.vertical, 32)
    }

    private var layoutMenu: some View {
        Menu {
            Button("Carousel") { store.allExpeditionsGalleryLayout = .grid }
            Button("List") { store.allExpeditionsGalleryLayout = .list }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(StitchTheme.outline)
                .frame(width: 36, height: 36)
        }
        .menuStyle(.borderlessButton)
        .help("Layout")
    }

    private var carouselNavArrows: some View {
        HStack(spacing: 8) {
            carouselArrowButton(systemName: "arrow.left") {
                scrollCarousel(delta: -1)
            }
            carouselArrowButton(systemName: "arrow.right") {
                scrollCarousel(delta: 1)
            }
        }
    }

    private func carouselArrowButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(StitchTheme.onSurface)
                .padding(8)
                .background(
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }

    private func scrollCarousel(delta: Int) {
        let maxIdx = orderedCarouselSummaries.count
        carouselFocusIndex = min(maxIdx, max(0, carouselFocusIndex + delta))
    }

    private var carouselRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(orderedCarouselSummaries) { summary in
                        CarouselExpeditionCard(demoImage: Self.demoHeroImage, summary: summary) {
                            if summary.isOpenable { store.openProject(summary) }
                        }
                        .id(summary.id)
                    }
                    newExpeditionCarouselCard
                        .id(Self.newExpeditionScrollID)
                }
                .padding(.horizontal, sectionHorizontalPadding)
            }
            .onChange(of: carouselFocusIndex) { _, newValue in
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(carouselScrollID(for: newValue), anchor: .leading)
                }
            }
        }
    }

    private func carouselScrollID(for index: Int) -> AnyHashable {
        guard index < orderedCarouselSummaries.count else { return Self.newExpeditionScrollID }
        return orderedCarouselSummaries[index].id
    }

    private var newExpeditionCarouselCard: some View {
        Button {
            store.openProjectLibrary()
        } label: {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(StitchTheme.primary)
                }
                .scaleEffect(newExpeditionCardHovered ? 1.1 : 1)
                .animation(.easeOut(duration: 0.2), value: newExpeditionCardHovered)
                Text("Start New Expedition")
                    .font(StitchTypography.font(size: 10, weight: .medium))
                    .foregroundStyle(StitchTheme.outline)
                    .multilineTextAlignment(.center)
                    .textCase(.uppercase)
                    .tracking(2)
            }
            .frame(width: 300, height: 375)
            .background(Color(red: 0.09, green: 0.09, blue: 0.09), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundStyle(newExpeditionCardHovered ? StitchTheme.primary.opacity(0.5) : Color.white.opacity(0.1))
            }
        }
        .buttonStyle(.plain)
        .onHover { newExpeditionCardHovered = $0 }
    }

    /// `auto_awesome` + `shadow-[0_0_50px_rgba(255,255,255,0.1)]`
    private var smartImportFAB: some View {
        Button {
            store.currentSection = .imports
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .medium))
                Text("Smart Import")
                    .font(StitchTypography.font(size: 12, weight: .bold))
                    .textCase(.uppercase)
                    .tracking(3)
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.white.opacity(0.1), radius: 25, x: 0, y: 0)
            )
        }
        .buttonStyle(.plain)
        .onHover { smartImportHovered = $0 }
    }

    // MARK: - List (alternate; not in Stitch HTML)

    private var listSection: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if !q.isEmpty, filteredSummaries.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .padding(.horizontal, sectionHorizontalPadding)
            } else if store.projectSummaries.isEmpty {
                ContentUnavailableView(
                    "No expeditions in library",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Import a folder, SD card, or iPhone session from Imports, or open Expedition Library.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
                .padding(.horizontal, sectionHorizontalPadding)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredSummaries.enumerated()), id: \.element.id) { idx, summary in
                            galleryListRow(summary, showTopBorder: idx > 0)
                        }
                    }
                    .background(StitchTheme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, sectionHorizontalPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
            .disabled(!summary.isOpenable)
            ExpeditionMoreVertIndicator()
                .padding(.trailing, 14)
                .allowsHitTesting(false)
        }
        .opacity(summary.isOpenable ? 1 : 0.58)
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

    private func galleryRowMeta(for summary: ProjectSummary) -> String {
        let m = summary.createdAt.formatted(.dateTime.month(.abbreviated).year())
        return "Expedition · \(m)"
    }
}

// MARK: - Carousel card (`rounded-lg` = 4px, image opacity 60→100, `duration-500` scale)

private struct CarouselExpeditionCard: View {
    let demoImage: NSImage?
    let summary: ProjectSummary
    let onOpen: () -> Void
    @State private var isHovered = false

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return f
    }()

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomLeading) {
                StitchTheme.surfaceContainerLow

                if let img = demoImage {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFill()
                        .opacity(summary.isOpenable ? (isHovered ? 1 : 0.6) : 0.6)
                        .animation(.easeInOut(duration: 0.5), value: isHovered)
                } else {
                    LinearGradient(
                        colors: [
                            Color(hue: Double(abs(summary.id.hashValue % 360)) / 360.0, saturation: 0.45, brightness: 0.28),
                            Color(hue: Double((abs(summary.id.hashValue) + 40) % 360) / 360.0, saturation: 0.5, brightness: 0.16),
                        ],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                    .opacity(summary.isOpenable ? (isHovered ? 1 : 0.6) : 0.6)
                    .animation(.easeInOut(duration: 0.5), value: isHovered)
                }

                // `bg-gradient-to-t from-background via-transparent to-transparent opacity-90`
                LinearGradient(
                    colors: [
                        StitchTheme.background.opacity(0.9),
                        Color.clear,
                    ],
                    startPoint: .bottom,
                    endPoint: .center
                )

                if !summary.isOpenable {
                    VStack {
                        HStack {
                            Spacer()
                            Text("Archived")
                                .font(StitchTypography.font(size: 7, weight: .semibold))
                                .foregroundStyle(StitchTheme.outline)
                                .textCase(.uppercase)
                                .tracking(1.6)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Color(red: 0.208, green: 0.208, blue: 0.204).opacity(0.4))
                                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 2, style: .continuous))
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                }
                        }
                        Spacer()
                    }
                    .padding(16)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.monthFormatter.string(from: summary.createdAt).uppercased())
                        .font(StitchTypography.font(size: 8, weight: .semibold))
                        .foregroundStyle(StitchTheme.outline)
                        .tracking(2)
                    Text(summary.name.uppercased(with: Locale.current))
                        .font(StitchTypography.font(size: 14, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(summary.isOpenable ? Color.white : Color.white.opacity(0.5))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .frame(width: 300, height: 375)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            }
            .grayscale(summary.isOpenable ? 0 : 1)
            .opacity(summary.isOpenable ? 1 : 0.5)
            .scaleEffect(isHovered && summary.isOpenable ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.5), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(!summary.isOpenable)
        .onHover { isHovered = $0 }
    }
}
