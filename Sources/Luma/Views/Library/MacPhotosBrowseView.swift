import SwiftUI

struct MacPhotosBrowseView: View {
    @Bindable var store: LibraryStore
    @State private var showSettings = false
    @State private var showCreateExpedition = false

    private let columns = [
        GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 3)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.macPhotosMonthSections.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(store.macPhotosMonthSections) { section in
                            Section {
                                LazyVGrid(columns: columns, spacing: 3) {
                                    ForEach(section.assets, id: \.id) { asset in
                                        AssetThumbnailCell(asset: asset)
                                            .aspectRatio(1, contentMode: .fill)
                                    }
                                }
                                .padding(.horizontal, 4)
                                .padding(.bottom, 12)
                            } header: {
                                sectionHeader(section)
                            }
                        }
                    }
                }
            }
        }
        .background(StitchTheme.background)
        .onAppear {
            if store.macPhotosMonthSections.isEmpty {
                store.refreshMacPhotosAssets()
            }
        }
        .sheet(isPresented: $showSettings) {
            MacPhotosSettingsView(store: store)
                .frame(minWidth: 480, minHeight: 400)
        }
        .sheet(isPresented: $showCreateExpedition) {
            MacPhotosExpeditionCreatorSheet(store: store, isPresented: $showCreateExpedition)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.badge.checkmark")
                .font(.system(size: 18))
                .foregroundStyle(.blue)
            Text("Mac Photos")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(StitchTheme.onSurface)

            Spacer()

            if store.macPhotosIsIndexing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("索引中…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Text("\(store.macPhotosAssetsTotal) 张")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                showCreateExpedition = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                    Text("创建旅程")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.macPhotosAssetsTotal == 0)

            Button {
                Task { await store.refreshMacPhotosIndex() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .disabled(store.macPhotosIsIndexing)
            .help("更新索引")

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help("Mac Photos 设置")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Section Header

    private func sectionHeader(_ section: LibraryStore.MacPhotosMonthSection) -> some View {
        HStack {
            if section.year == 0 {
                Text("无日期")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurface)
            } else {
                Text(section.displayTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurface)
            }
            Spacer()
            Text("\(section.assets.count)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(StitchTheme.background.opacity(0.95))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.25))
            Text("Mac Photos 图库为空")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("点击右上角刷新按钮更新索引")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
