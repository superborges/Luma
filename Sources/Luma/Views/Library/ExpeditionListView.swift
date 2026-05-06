import SwiftUI

struct ExpeditionListView: View {
    @Bindable var store: LibraryStore
    @State private var showCreateSheet = false

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                if store.expeditions.isEmpty {
                    emptyState
                } else {
                    expeditionGrid
                }
            }
            .padding(24)
        }
        .background(StitchTheme.background)
        .sheet(isPresented: $showCreateSheet) {
            CreateExpeditionSheet(store: store, isPresented: $showCreateSheet)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("旅程")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                Text("管理你的照片旅程，从导入到精选到导出")
                    .font(.system(size: 13))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
            }
            Spacer()
            Button {
                showCreateSheet = true
            } label: {
                Label("新建旅程", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(StitchTheme.primary.opacity(0.15))
                    .foregroundStyle(StitchTheme.primary)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    private var expeditionGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(store.expeditions) { expedition in
                ExpeditionCardView(
                    expedition: expedition,
                    assetCount: store.expeditionAssetCounts[expedition.id] ?? 0,
                    groupCount: store.expeditionGroupCounts[expedition.id] ?? 0,
                    invalidRefCount: store.invalidReferenceCounts[expedition.id] ?? 0
                ) {
                    store.openExpedition(id: expedition.id)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 60)
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.25))
            Text("还没有旅程")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(StitchTheme.onSurface)
            Text("创建你的第一个旅程，开始导入和整理照片")
                .font(.system(size: 13))
                .foregroundStyle(StitchTheme.onSurfaceVariant)
            Button {
                showCreateSheet = true
            } label: {
                Label("创建第一个旅程", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(StitchTheme.primaryContainer)
                    .foregroundStyle(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
    }
}
