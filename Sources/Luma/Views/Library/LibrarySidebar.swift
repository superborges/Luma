import SwiftUI

struct LibrarySidebar: View {
    @Bindable var store: LibraryStore
    @State private var isExpeditionSectionExpanded = true
    @State private var isAlbumSectionExpanded = true
    @State private var isSmartAlbumSectionExpanded = true
    @State private var showCreateExpedition = false
    @State private var showCreateAlbum = false
    @State private var renamingExpeditionId: UUID?
    @State private var renameText: String = ""

    var body: some View {
        List(selection: $store.selectedNavItem) {
            Section("资料库") {
                NavigationLink(value: NavigationItem.allPhotos) {
                    Label {
                        HStack {
                            Text("所有照片")
                            Spacer()
                            Text("\(store.allAssetsCount)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                NavigationLink(value: NavigationItem.macPhotos) {
                    Label {
                        HStack {
                            Text("Mac Photos")
                            Spacer()
                            if store.macPhotosConnected {
                                Text("\(store.macPhotosTotalCount)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("未连接")
                                    .font(.system(size: 9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.3))
                                    .cornerRadius(4)
                            }
                        }
                    } icon: {
                        Image(systemName: "photo.badge.checkmark")
                    }
                }
                NavigationLink(value: NavigationItem.recentlyAdded) {
                    Label {
                        HStack {
                            Text("最近添加")
                            Spacer()
                            Text("\(store.recentlyAddedAssets.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "clock")
                    }
                }
                NavigationLink(value: NavigationItem.unorganized) {
                    Label {
                        HStack {
                            Text("未整理")
                            Spacer()
                            Text("\(store.unorganizedAssets.count)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "tray")
                    }
                }
            }

            Section(isExpanded: $isExpeditionSectionExpanded) {
                ForEach(store.expeditions.filter { !$0.isMacPhotos }) { expedition in
                    NavigationLink(value: NavigationItem.expedition(expedition.id)) {
                        expeditionRow(expedition)
                    }
                    .contextMenu {
                        Button("重命名") {
                            renamingExpeditionId = expedition.id
                            renameText = expedition.name
                        }
                        Button("删除", role: .destructive) {
                            try? store.deleteExpedition(id: expedition.id)
                        }
                    }
                }
                Button {
                    showCreateExpedition = true
                } label: {
                    Label("新建旅程", systemImage: "plus")
                }
            } header: {
                Text("旅程")
            }

            Section(isExpanded: $isAlbumSectionExpanded) {
                ForEach(store.albums.filter { $0.kind == .manual || $0.kind == .photosBacked }) { album in
                    NavigationLink(value: NavigationItem.album(album.id)) {
                        albumRow(album)
                    }
                    .contextMenu {
                        Button("删除", role: .destructive) {
                            try? store.deleteAlbum(id: album.id)
                        }
                    }
                }
                Button {
                    showCreateAlbum = true
                } label: {
                    Label("新建相册", systemImage: "plus")
                }
            } header: {
                Text("相册")
            }

            Section(isExpanded: $isSmartAlbumSectionExpanded) {
                ForEach(SmartAlbumFilter.allCases, id: \.self) { filter in
                    NavigationLink(value: NavigationItem.smartAlbum(filter)) {
                        Label(filter.displayName, systemImage: filter.systemImage)
                    }
                }
            } header: {
                Text("智能相册")
            }

            Section("任务") {
                NavigationLink(value: NavigationItem.taskList) {
                    Label {
                        HStack {
                            Text("任务列表")
                            Spacer()
                            let activeCount = store.activeActionJobs.count + (store.isImporting ? 1 : 0)
                            if activeCount > 0 {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("\(activeCount)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                let total = store.completedActionJobs.count
                                Text("\(total)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: "list.bullet.clipboard")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $showCreateExpedition) {
            CreateExpeditionSheet(store: store, isPresented: $showCreateExpedition)
        }
        .sheet(isPresented: $showCreateAlbum) {
            CreateAlbumSheet(store: store, isPresented: $showCreateAlbum)
        }
        .alert("重命名旅程", isPresented: Binding(
            get: { renamingExpeditionId != nil },
            set: { if !$0 { renamingExpeditionId = nil } }
        )) {
            TextField("名称", text: $renameText)
            Button("确认") {
                if let id = renamingExpeditionId, !renameText.isEmpty {
                    try? store.renameExpedition(id: id, newName: renameText)
                }
                renamingExpeditionId = nil
            }
            Button("取消", role: .cancel) {
                renamingExpeditionId = nil
            }
        }
    }

    private func albumRow(_ album: LumaAlbum) -> some View {
        HStack {
            Label {
                Text(album.name).lineLimit(1)
            } icon: {
                Image(systemName: album.kind == .photosBacked ? "photo.badge.checkmark" : "rectangle.stack")
            }
            Spacer()
            Text("\(store.albumAssetCounts[album.id] ?? 0)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func expeditionRow(_ expedition: Expedition) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expedition.name)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    let count = store.expeditionAssetCounts[expedition.id] ?? 0
                    Text("\(count) 张")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    let groupCount = store.expeditionGroupCounts[expedition.id] ?? 0
                    if groupCount > 0 {
                        Text("\(groupCount) 组")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if let invalidCount = store.invalidReferenceCounts[expedition.id], invalidCount > 0 {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.yellow)
                    .help("\(invalidCount) 个引用失效")
            }
            expeditionStatusBadge(expedition.status)
        }
    }

    private func expeditionStatusBadge(_ status: ExpeditionStatus) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .importing: return ("导入中", .orange)
            case .analyzing: return ("分析中", .purple)
            case .reviewing: return ("选片中", .blue)
            case .completed: return ("已完成", .green)
            case .archived: return ("已归档", .gray)
            }
        }()
        return Text(text)
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .cornerRadius(4)
    }
}
