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

            Section("选片参数") {
                Picker("分组时间阈值", selection: Binding(
                    get: { store.groupingTimeThresholdMinutes },
                    set: { store.groupingTimeThresholdMinutes = $0 }
                )) {
                    Text("15 分钟 — 密集拍摄").tag(15)
                    Text("30 分钟（默认）").tag(30)
                    Text("60 分钟 — 大跨度").tag(60)
                    Text("120 分钟 — 宽松").tag(120)
                }
                Text("修改后对下一次导入生效，已有 Session 不受影响。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("缓存") {
                Stepper(
                    "缩略图缓存上限：\(store.thumbnailCacheLimit)",
                    value: Binding(
                        get: { store.thumbnailCacheLimit },
                        set: { store.thumbnailCacheLimit = $0 }
                    ),
                    in: 100...2000,
                    step: 100
                )
                Text("立即生效。值越大占内存越多，缩略图加载越快。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("默认文件命名") {
                Picker("命名规则", selection: Binding(
                    get: { store.defaultFileNamingRule },
                    set: { store.defaultFileNamingRule = $0 }
                )) {
                    Text("保留原名").tag(FileNamingRule.original)
                    Text("日期前缀").tag(FileNamingRule.datePrefix)
                    Text("自定义模板").tag(FileNamingRule.custom)
                }
                Text("新建导出时自动套用此规则。可在导出面板覆盖。")
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
                if let path = try? AppDirectories.importBreadcrumbFileURL().path(percentEncoded: false) {
                    LabeledContent("导入面包屑 (同步)", value: path)
                        .textSelection(.enabled)
                }
            } header: {
                Text("诊断")
            } footer: {
                Text("Luma 不会自动上传任何 trace；「导入面包屑」在相册导入各阶段同步追加，若崩溃可据此看最后一行；请与 Trace 一并打包发给开发者。")
                    .font(.caption)
            }

            // "照片导入"调试开关已移除：v2 月份选择器不再需要简化回退路径。
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
