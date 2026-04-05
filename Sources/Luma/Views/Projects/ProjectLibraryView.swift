import SwiftUI

struct ProjectLibraryView: View {
    @Bindable var store: ProjectStore

    @State private var selectedProjectID: URL?
    @State private var projectPendingDeletion: ProjectSummary?

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目库")
                        .font(.title2.weight(.semibold))
                    Text("切换、刷新或删除本地项目。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("刷新") {
                    store.refreshProjectSummaries()
                    syncSelection()
                }
                Button("关闭") {
                    store.closeProjectLibrary()
                }
            }
            .padding(20)

            Divider()

            if store.projectSummaries.isEmpty {
                ContentUnavailableView(
                    "暂无项目",
                    systemImage: "books.vertical",
                    description: Text("先导入一个照片文件夹、SD 卡或 iPhone 项目。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    List(selection: $selectedProjectID) {
                        ForEach(store.projectSummaries) { summary in
                            ProjectRow(summary: summary)
                                .tag(summary.id)
                        }
                    }
                    .frame(minWidth: 320)

                    Divider()

                    Group {
                        if let selectedSummary {
                            detailView(for: selectedSummary)
                        } else {
                            ContentUnavailableView(
                                "未选择项目",
                                systemImage: "folder",
                                description: Text("从左侧选择一个项目查看详情。")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                }
            }
        }
        .frame(minWidth: 860, minHeight: 520)
        .onAppear {
            store.refreshProjectSummaries()
            syncSelection()
        }
        .alert(
            "删除项目？",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            ),
            presenting: projectPendingDeletion
        ) { summary in
            Button("删除", role: .destructive) {
                store.deleteProject(summary)
                projectPendingDeletion = nil
                syncSelection()
            }
            Button("取消", role: .cancel) {
                projectPendingDeletion = nil
            }
        } message: { summary in
            Text("将删除“\(summary.name)”及其本地缓存文件。此操作不可撤回。")
        }
    }

    private var selectedSummary: ProjectSummary? {
        if let selectedProjectID {
            return store.projectSummaries.first(where: { $0.id == selectedProjectID })
        }
        return nil
    }

    @ViewBuilder
    private func detailView(for summary: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.name)
                    .font(.title3.weight(.semibold))
                if summary.isCurrent {
                    Text("当前项目")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }

            LabeledContent("创建时间", value: summary.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("照片数量", value: summary.assetCountDescription)
            LabeledContent("分组数量", value: summary.groupCountDescription)
            LabeledContent("目录", value: summary.directory.path)

            if case .unavailable(let reason) = summary.state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            HStack {
                Button("打开项目") {
                    store.openProject(summary)
                }
                .disabled(summary.isCurrent)

                Button("删除项目", role: .destructive) {
                    projectPendingDeletion = summary
                }

                Spacer()
            }
        }
    }

    private func syncSelection() {
        if let current = store.projectSummaries.first(where: \.isCurrent) {
            selectedProjectID = current.id
        } else {
            selectedProjectID = store.projectSummaries.first?.id
        }
    }
}

private struct ProjectRow: View {
    let summary: ProjectSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(summary.name)
                    .font(.headline)
                    .lineLimit(1)
                if summary.isCurrent {
                    Text("当前")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }

            Text(summary.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(summary.assetCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(summary.groupCountDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(summary.directory.lastPathComponent)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
