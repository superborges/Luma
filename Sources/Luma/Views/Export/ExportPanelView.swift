import SwiftUI

struct ExportPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ProjectStore

    var body: some View {
        NavigationStack {
            Form {
                Section("导出目标") {
                    Picker("目标", selection: $store.exportOptions.destination) {
                        Text("文件夹").tag(ExportDestination.folder)
                        Text("Lightroom").tag(ExportDestination.lightroom)
                        Text("照片 App").tag(ExportDestination.photosApp)
                    }

                    switch store.exportOptions.destination {
                    case .folder:
                        Picker("目录模板", selection: $store.exportOptions.folderTemplate) {
                            Text("按日期").tag(FolderTemplate.byDate)
                            Text("按场景").tag(FolderTemplate.byGroup)
                            Text("按评分").tag(FolderTemplate.byRating)
                        }
                        Toggle("附带 XMP", isOn: $store.exportOptions.writeXmpSidecar)
                        Toggle("写入修图建议", isOn: $store.exportOptions.writeEditSuggestionsToXmp)
                        pathRow(
                            title: "输出目录",
                            path: store.exportOptions.outputPath?.path(percentEncoded: false) ?? "未选择"
                        ) {
                            store.chooseExportFolder()
                        }
                    case .lightroom:
                        Toggle("写入 XMP", isOn: $store.exportOptions.writeXmpSidecar)
                        Toggle("写入修图建议", isOn: $store.exportOptions.writeEditSuggestionsToXmp)
                        pathRow(
                            title: "自动导入目录",
                            path: store.exportOptions.lrAutoImportFolder?.path(percentEncoded: false) ?? "未选择"
                        ) {
                            store.chooseLightroomFolder()
                        }
                    case .photosApp:
                        Toggle("按分组创建相册", isOn: $store.exportOptions.createAlbumPerGroup)
                        Toggle("合并 RAW + JPEG", isOn: $store.exportOptions.mergeRawAndJpeg)
                        Toggle("保留 Live Photo", isOn: $store.exportOptions.preserveLivePhoto)
                        Toggle("写入 AI 评语到照片说明", isOn: $store.exportOptions.includeAICommentAsDescription)
                        Text("导入到照片 App 后不可撤回，建议先确认当前 Picked 结果。")
                            .foregroundStyle(.orange)
                        Text("说明字段目前受限于 macOS PhotoKit 公开接口，导出时会忽略“AI 评语到照片说明”选项。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("未选照片处理") {
                    Picker("处理方式", selection: $store.exportOptions.rejectedHandling) {
                        Text("缩小保留").tag(RejectedHandling.shrinkKeep)
                        Text("归档视频").tag(RejectedHandling.archiveVideo)
                        Text("忽略").tag(RejectedHandling.discard)
                    }
                    Text("未选照片：\(store.archiveCandidatesCount) 张")
                        .foregroundStyle(.secondary)
                }

                Section("当前批次") {
                    LabeledContent("已选", value: "\(store.pickedAssetsCount) 张")
                    LabeledContent("未选", value: "\(store.archiveCandidatesCount) 张")
                }
            }
            .navigationTitle("导出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        store.closeExportPanel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await store.performExport()
                            if !store.isExportPanelPresented {
                                dismiss()
                            }
                        }
                    } label: {
                        if store.isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("开始导出")
                        }
                    }
                    .disabled(store.isExporting)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Button("选择…", action: action)
            }
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}
