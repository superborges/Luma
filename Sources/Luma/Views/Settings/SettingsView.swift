import SwiftUI

struct SettingsView: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("项目") {
                    LabeledContent("当前项目", value: store.projectName)
                    LabeledContent("本地项目数", value: "\(store.projectSummaries.count)")
                    if let path = try? AppDirectories.applicationSupportRoot().path(percentEncoded: false) {
                        LabeledContent("数据目录", value: path)
                    }
                    Button("打开远征库") {
                        store.openProjectLibrary()
                    }
                    .stitchHoverDimming()
                }

                Section("开发") {
                    Button("打开性能诊断") {
                        store.openPerformanceDiagnostics()
                    }
                    .stitchHoverDimming()
                }

                Section("AI") {
                    AIModelConfigView(store: store)
                }
            }
            .formStyle(.grouped)
            .padding()
            .frame(width: 620, height: 420)
        }
    }
}
