import SwiftUI

struct MacPhotosExpeditionCreatorSheet: View {
    @Bindable var store: LibraryStore
    @Binding var isPresented: Bool

    enum CreationMode: String, CaseIterable {
        case dateRange = "按时间范围"
        case collection = "按系统相册"
    }

    @State private var mode: CreationMode = .dateRange
    @State private var expeditionName = ""
    @State private var startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var endDate = Date()
    @State private var previewCount: Int?
    @State private var previewAssetIds: [UUID] = []
    @State private var isLoadingPreview = false
    @State private var isCreating = false
    @State private var createError: String?

    @State private var collections: [PHCollectionSnapshot] = []
    @State private var selectedCollectionIds: Set<String> = []
    @State private var isLoadingCollections = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 20) {
                    modePicker
                    nameField
                    if mode == .dateRange {
                        dateRangeSection
                    } else {
                        collectionSection
                    }
                    previewSection
                    if let error = createError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                    }
                }
                .padding(24)
            }
            Divider()
            footer
        }
        .frame(width: 500, height: 560)
        .background(StitchTheme.background)
        .task {
            await loadCollections()
            refreshPreview()
        }
        .onChange(of: startDate) { refreshPreview() }
        .onChange(of: endDate) { refreshPreview() }
        .onChange(of: mode) { refreshPreview() }
        .onChange(of: selectedCollectionIds) { refreshPreview() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 18))
                .foregroundStyle(.blue)
            Text("从 Mac Photos 创建旅程")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(StitchTheme.onSurface)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("创建方式", selection: $mode) {
            ForEach(CreationMode.allCases, id: \.self) { m in
                Text(m.rawValue).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("旅程名称")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("例如：2024 日本旅行", text: $expeditionName)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Date Range

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择时间范围")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("开始")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("结束")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }
            dateRangePresets
        }
    }

    private var dateRangePresets: some View {
        HStack(spacing: 8) {
            presetButton("最近 7 天", days: 7)
            presetButton("最近 30 天", days: 30)
            presetButton("最近 90 天", days: 90)
            presetButton("最近一年", days: 365)
            Spacer()
        }
    }

    private func presetButton(_ title: String, days: Int) -> some View {
        Button(title) {
            endDate = Date()
            startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate) ?? endDate
        }
        .font(.system(size: 11))
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Collection

    private var collectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("选择系统相册")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if isLoadingCollections {
                    ProgressView().controlSize(.small)
                }
            }

            if collections.isEmpty && !isLoadingCollections {
                Text("未找到系统相册")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(collections, id: \.localIdentifier) { col in
                            collectionRow(col)
                        }
                    }
                }
                .frame(maxHeight: 180)
                .background(StitchTheme.surfaceContainerLow)
                .cornerRadius(8)
            }
        }
    }

    private func collectionRow(_ col: PHCollectionSnapshot) -> some View {
        Button {
            if selectedCollectionIds.contains(col.localIdentifier) {
                selectedCollectionIds.remove(col.localIdentifier)
            } else {
                selectedCollectionIds.insert(col.localIdentifier)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedCollectionIds.contains(col.localIdentifier)
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedCollectionIds.contains(col.localIdentifier) ? .blue : .secondary)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 1) {
                    Text(col.title)
                        .font(.system(size: 13))
                        .foregroundStyle(StitchTheme.onSurface)
                    Text(col.collectionType == .smartAlbum ? "智能相册" : "用户相册")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if col.estimatedAssetCount > 0 {
                    Text("\(col.estimatedAssetCount)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    private var previewSection: some View {
        HStack {
            if isLoadingPreview {
                ProgressView().controlSize(.small)
                Text("正在查询…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if let count = previewCount {
                Image(systemName: "photo.stack")
                    .foregroundStyle(.blue)
                Text("将包含 **\(count)** 张照片")
                    .font(.system(size: 14))
                    .foregroundStyle(StitchTheme.onSurface)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("取消") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                Task { await createExpedition() }
            } label: {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView().controlSize(.small)
                    }
                    Text("创建旅程")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canCreate)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var canCreate: Bool {
        !expeditionName.trimmingCharacters(in: .whitespaces).isEmpty
        && (previewCount ?? 0) > 0
        && !isCreating
    }

    // MARK: - Actions

    private func refreshPreview() {
        isLoadingPreview = true
        previewCount = nil
        previewAssetIds = []
        createError = nil

        Task {
            do {
                let assets: [MasterAsset]
                switch mode {
                case .dateRange:
                    let adjustedEnd = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: endDate) ?? endDate
                    assets = try store.fetchMacPhotosAssetsByDateRange(from: startDate, to: adjustedEnd)
                case .collection:
                    guard !selectedCollectionIds.isEmpty else {
                        previewCount = 0
                        isLoadingPreview = false
                        return
                    }
                    assets = try await store.fetchMacPhotosAssetsByCollections(Array(selectedCollectionIds))
                }
                previewAssetIds = assets.map(\.id)
                previewCount = assets.count
            } catch {
                previewCount = 0
            }
            isLoadingPreview = false
        }
    }

    private func loadCollections() async {
        isLoadingCollections = true
        collections = await store.fetchMacPhotosCollections()
        isLoadingCollections = false
    }

    private func createExpedition() async {
        guard canCreate else { return }
        isCreating = true
        createError = nil
        do {
            let name = expeditionName.trimmingCharacters(in: .whitespaces)
            let expedition = try store.createExpeditionFromMacPhotos(name: name, assetIds: previewAssetIds)
            isPresented = false
            store.openExpedition(id: expedition.id)
        } catch {
            createError = error.localizedDescription
        }
        isCreating = false
    }
}
