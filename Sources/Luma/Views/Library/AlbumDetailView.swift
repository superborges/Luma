import SwiftUI

struct AlbumDetailView: View {
    @Bindable var store: LibraryStore
    let albumId: UUID

    @State private var assets: [MasterAsset] = []
    @State private var album: LumaAlbum?
    @State private var isLoading = true
    @State private var syncError: String?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 2)]

    private var syncStatus: AlbumSyncStatus {
        store.albumSyncStatuses[albumId] ?? .notSynced
    }

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
        .task(id: albumId) { loadData() }
        .alert("同步失败", isPresented: Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("确定") { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(album?.name ?? "相册")
                    .font(.title2.bold())
                HStack(spacing: 12) {
                    Text("\(assets.count) 张照片")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let kind = album?.kind {
                        kindBadge(kind)
                    }
                    syncStatusBadge
                }
            }
            Spacer()
            syncActions
        }
        .padding()
    }

    @ViewBuilder
    private var syncStatusBadge: some View {
        switch syncStatus {
        case .notSynced:
            EmptyView()
        case .syncing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("同步中")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.orange)
            }
        case .synced:
            Text("已同步")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.15))
                .foregroundStyle(.green)
                .cornerRadius(4)
        case .stale:
            Label("已失效", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .cornerRadius(4)
        }
    }

    @ViewBuilder
    private var syncActions: some View {
        if let kind = album?.kind, (kind == .manual || kind == .photosBacked) {
            switch syncStatus {
            case .notSynced:
                Button {
                    Task { await performSync() }
                } label: {
                    Label("同步到 Photos", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(assets.isEmpty)
            case .syncing:
                Button {} label: {
                    ProgressView().controlSize(.small)
                }
                .disabled(true)
            case .synced:
                Button {
                    Task { await performSync() }
                } label: {
                    Label("更新同步", systemImage: "arrow.triangle.2.circlepath")
                }
            case .stale:
                Menu {
                    Button("重新绑定") {
                        Task { await rebind() }
                    }
                    Button("转为本地相册") {
                        try? store.convertAlbumToLocal(albumId: albumId)
                        loadData()
                    }
                } label: {
                    Label("已失效", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private func kindBadge(_ kind: AlbumKind) -> some View {
        let (text, color): (String, Color) = {
            switch kind {
            case .manual: return ("手动", .blue)
            case .smart: return ("智能", .purple)
            case .photosBacked: return ("Photos", .green)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(4)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("相册中没有照片")
                .font(.headline)
                .foregroundStyle(.secondary)
            if album?.kind == .manual {
                Text("在旅程选片台中选择照片，右键添加到此相册")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
        album = try? store.fetchAlbum(id: albumId)
        if let a = album, a.kind == .smart, let rule = a.rule {
            let matchedIds = (try? store.evaluateSmartAlbum(
                filter: rule.filters.first ?? .allPicked,
                expeditionId: a.expeditionId
            )) ?? []
            assets = (try? store.fetchAssetsByIds(matchedIds)) ?? []
        } else {
            assets = (try? store.fetchAlbumAssets(albumId: albumId)) ?? []
        }
        isLoading = false
    }

    private func performSync() async {
        do {
            try await store.syncAlbumToPhotos(albumId: albumId)
            loadData()
        } catch LumaError.userCancelled {
            // User cancelled in system dialog — no error
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func rebind() async {
        do {
            try await store.rebindAlbumToPhotos(albumId: albumId)
            loadData()
        } catch LumaError.userCancelled {
            // noop
        } catch {
            syncError = error.localizedDescription
        }
    }
}
