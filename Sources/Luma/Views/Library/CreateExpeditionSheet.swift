import AppKit
import SwiftUI

struct CreateExpeditionSheet: View {
    @Bindable var store: LibraryStore
    @Binding var isPresented: Bool
    @State private var name: String = ""
    @State private var sourceMode: ExpeditionSourceMode = .sdCard
    @State private var folderStorageMode: AssetStorageMode = .managed
    @State private var selectedFolderURL: URL?
    @State private var selectedVolumeURL: URL?
    @State private var errorMessage: String?
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 24) {
            Text("新建旅程")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("名称")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("例如：日本关西 2026", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("来源模式")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $sourceMode) {
                        Text("SD 卡").tag(ExpeditionSourceMode.sdCard)
                        Text("本地文件夹").tag(ExpeditionSourceMode.localFolder)
                        Text("Mac Photos").tag(ExpeditionSourceMode.macPhotos)
                    }
                    .pickerStyle(.segmented)
                }

                if sourceMode == .sdCard {
                    sdCardSection
                }

                if sourceMode == .localFolder {
                    folderSection
                }

                if sourceMode == .macPhotos {
                    Text("Mac Photos 旅程请使用 Mac Photos 浏览页面的「创建旅程」功能。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("取消") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    Task { await createAndImport() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreating {
                            ProgressView().controlSize(.small)
                        }
                        Text("创建")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || isCreating)
            }
        }
        .padding(32)
        .frame(width: 440)
        .onChange(of: sourceMode) {
            selectedFolderURL = nil
            selectedVolumeURL = nil
            errorMessage = nil
        }
    }

    // MARK: - SD Card Section

    private var sdCardSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let url = selectedVolumeURL {
                    Image(systemName: "sdcard.fill")
                        .foregroundStyle(.blue)
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Button("更换") { pickSDCard() }
                        .font(.system(size: 12))
                } else {
                    Button {
                        pickSDCard()
                    } label: {
                        Label("选择 SD 卡", systemImage: "sdcard")
                    }
                    Spacer()
                }
            }
            Text("选择含有 DCIM 目录的 SD 卡或存储卡")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.5))
        }
    }

    // MARK: - Folder Section

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("文件夹导入方式")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $folderStorageMode) {
                    Text("复制到 Luma").tag(AssetStorageMode.managed)
                    Text("引用原位置").tag(AssetStorageMode.referenced)
                }
                .pickerStyle(.segmented)
                Text(folderStorageMode == .managed
                     ? "照片将复制到 Luma 管理的目录，占用额外磁盘空间"
                     : "照片保留在原位置，不复制。移动或删除原文件会导致引用失效")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.5))
            }

            HStack {
                if let url = selectedFolderURL {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.blue)
                    Text(url.lastPathComponent)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    Spacer()
                    Button("更换") { pickFolder() }
                        .font(.system(size: 12))
                } else {
                    Button {
                        pickFolder()
                    } label: {
                        Label("选择文件夹", systemImage: "folder")
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Validation

    private var canCreate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        switch sourceMode {
        case .sdCard:
            return selectedVolumeURL != nil
        case .localFolder:
            return selectedFolderURL != nil
        case .macPhotos, .mixed:
            return false
        }
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择照片文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        selectedFolderURL = url
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = url.lastPathComponent
        }
    }

    private func pickSDCard() {
        let volumes = SDCardAdapter.availableVolumes()
        if volumes.count == 1 {
            selectedVolumeURL = volumes[0]
            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                name = volumes[0].lastPathComponent
            }
            return
        }

        let panel = NSOpenPanel()
        panel.title = "选择 SD 卡"
        panel.directoryURL = URL(filePath: "/Volumes", directoryHint: .isDirectory)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard SDCardAdapter.isSupportedVolume(url) else {
            errorMessage = "所选目录不包含 DCIM，请选择 SD 卡卷宗。"
            return
        }
        selectedVolumeURL = url
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = url.lastPathComponent
        }
    }

    private func createAndImport() async {
        guard canCreate else { return }
        isCreating = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            switch sourceMode {
            case .sdCard:
                guard let volumeURL = selectedVolumeURL else { return }
                let expedition = try store.createExpedition(
                    name: trimmedName, sourceMode: .sdCard, defaultStorageMode: .managed
                )
                isPresented = false
                store.openExpedition(id: expedition.id)
                await store.startSDCardImport(expeditionId: expedition.id, volumeURL: volumeURL)

            case .localFolder:
                guard let folderURL = selectedFolderURL else { return }
                let expedition = try store.createExpedition(
                    name: trimmedName, sourceMode: .localFolder, defaultStorageMode: folderStorageMode
                )
                isPresented = false
                store.openExpedition(id: expedition.id)
                await store.startFolderImport(
                    expeditionId: expedition.id, folderURL: folderURL, storageMode: folderStorageMode
                )

            case .macPhotos, .mixed:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
        }
    }
}
