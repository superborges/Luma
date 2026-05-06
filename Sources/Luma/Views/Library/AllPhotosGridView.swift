import SwiftUI

struct AllPhotosGridView: View {
    @Bindable var store: LibraryStore

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("所有照片")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                Spacer()
                Text("\(store.allAssetsCount) 张")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                if store.allAssets.isEmpty {
                    emptyState
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(store.allAssets, id: \.id) { asset in
                            AssetThumbnailCell(asset: asset)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .background(StitchTheme.background)
        .onAppear { store.refreshAllAssets() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 80)
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundStyle(Color(white: 0.25))
            Text("暂无照片")
                .foregroundStyle(.secondary)
            Text("通过「新建旅程」导入照片")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct RecentlyAddedView: View {
    @Bindable var store: LibraryStore

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近添加")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                Spacer()
                Text("\(store.recentlyAddedAssets.count) 张")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                if store.recentlyAddedAssets.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 80)
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(white: 0.25))
                        Text("暂无最近添加的照片")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(store.recentlyAddedAssets, id: \.id) { asset in
                            AssetThumbnailCell(asset: asset)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .background(StitchTheme.background)
    }
}

struct UnorganizedPhotosView: View {
    @Bindable var store: LibraryStore

    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 4)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("未整理")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                Spacer()
                Text("\(store.unorganizedAssets.count) 张")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            ScrollView {
                if store.unorganizedAssets.isEmpty {
                    VStack(spacing: 12) {
                        Spacer(minLength: 80)
                        Image(systemName: "tray")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(white: 0.25))
                        Text("所有照片已归入旅程")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(store.unorganizedAssets, id: \.id) { asset in
                            AssetThumbnailCell(asset: asset)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .background(StitchTheme.background)
    }
}

struct AssetThumbnailCell: View {
    let asset: MasterAsset
    @State private var photoKitImage: NSImage?

    var body: some View {
        ZStack {
            StitchTheme.surfaceContainerLow
            if asset.storageMode == .externalReference {
                if let img = photoKitImage {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ProgressView().scaleEffect(0.5)
                }
            } else if let url = asset.thumbnailCacheURL ?? asset.previewURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    }
                }
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Color(white: 0.25))
            }
        }
        .frame(minHeight: 100)
        .clipped()
        .cornerRadius(4)
        .task(id: asset.id) {
            guard asset.storageMode == .externalReference else { return }
            let provider = AssetImageProviderFactory.provider(for: asset.storageMode)
            photoKitImage = await provider.thumbnail(for: asset, size: CGSize(width: 240, height: 240))
        }
    }
}
