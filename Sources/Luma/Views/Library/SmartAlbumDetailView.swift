import SwiftUI

struct SmartAlbumDetailView: View {
    @Bindable var store: LibraryStore
    let filter: SmartAlbumFilter

    @State private var assets: [MasterAsset] = []
    @State private var isLoading = true

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 2)]

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            if isLoading {
                ProgressView("加载中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if assets.isEmpty {
                emptyState
            } else {
                gridView
            }
        }
        .task(id: filter) { loadData() }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(filter.displayName, systemImage: filter.systemImage)
                    .font(.title2.bold())
                Text("\(assets.count) 张照片")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("智能相册")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.15))
                .foregroundStyle(.purple)
                .cornerRadius(4)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: filter.systemImage)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("没有匹配的照片")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(assets) { asset in
                    AssetThumbnailCell(asset: asset)
                        .aspectRatio(1, contentMode: .fill)
                        .clipped()
                }
            }
            .padding(2)
        }
    }

    private func loadData() {
        isLoading = true
        let matchedIds = (try? store.evaluateSmartAlbum(filter: filter)) ?? []
        assets = (try? store.fetchAssetsByIds(matchedIds)) ?? []
        isLoading = false
    }
}
