import SwiftUI

struct SettingsView: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            exportDefaultsTab
                .tabItem { Label("导出默认值", systemImage: "square.and.arrow.up") }
            developerTab
                .tabItem { Label("开发", systemImage: "wrench.and.screwdriver") }
        }
        .padding()
        .frame(width: 620, height: 460)
    }

    private var generalTab: some View {
        Form {
            Section("项目") {
                LabeledContent("当前 Session", value: store.projectName)
                LabeledContent("本地 Session 数", value: "\(store.projectSummaries.count)")
                if let path = try? AppDirectories.applicationSupportRoot().path(percentEncoded: false) {
                    LabeledContent("数据目录", value: path)
                        .textSelection(.enabled)
                }
                Button("打开 Session 库") {
                    store.openProjectLibrary()
                }
                .stitchHoverDimming()
            }
        }
        .formStyle(.grouped)
    }

    /// PRD 设置页 v1 最小集合：默认导出目录 / 默认 LR 自动导入目录 / 默认未选中处理方式。
    /// 这些字段直接复用 `store.exportOptions`，每次修改后 `loadExportSettings` / `saveExportSettings`
    /// 会持久化到 UserDefaults，下一次打开导出面板自动继承。
    private var exportDefaultsTab: some View {
        Form {
            Section("默认导出目录") {
                pathRow(
                    title: "Folder 导出",
                    path: store.exportOptions.outputPath?.path(percentEncoded: false) ?? "未设置"
                ) {
                    store.chooseExportFolder()
                    store.saveDefaultsExplicitly()
                }
                pathRow(
                    title: "Lightroom 自动导入目录",
                    path: store.exportOptions.lrAutoImportFolder?.path(percentEncoded: false) ?? "未设置"
                ) {
                    store.chooseLightroomFolder()
                    store.saveDefaultsExplicitly()
                }
                Text("下次新建 Session、点击「导出」时会自动套用上面这两条路径作为默认值。可在导出面板里覆盖。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("默认未选中处理方式") {
                Picker("默认策略", selection: $store.exportOptions.rejectedHandling) {
                    Text("缩小保留").tag(RejectedHandling.shrinkKeep)
                    Text("归档为视频").tag(RejectedHandling.archiveVideo)
                    Text("丢弃（保留在 Session 内）").tag(RejectedHandling.discard)
                }
                .pickerStyle(.inline)
                .onChange(of: store.exportOptions.rejectedHandling) { _, _ in
                    store.saveDefaultsExplicitly()
                }
                Text("PRD：导出页 Step 2。决定未选中（rejected）照片在导出后如何处理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var developerTab: some View {
        Form {
            Section {
                Button("打开性能诊断") {
                    store.openPerformanceDiagnostics()
                }
                .stitchHoverDimming()
                if let url = try? AppDirectories.runtimeTraceURL() {
                    LabeledContent("Trace 日志", value: url.path)
                        .textSelection(.enabled)
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("Luma 不会自动上传任何 trace；如需复盘 bug，请把上面的日志手动发给开发者。")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    private func pathRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Button("选择…", action: action)
                    .buttonStyle(.borderless)
                    .stitchHoverDimming()
            }
            Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(2)
        }
    }
}
