import AppKit
import SwiftUI

/// Session management UI (split list + detail), presented as a **sheet** only.
struct ProjectLibraryView: View {
    @Bindable var store: ProjectStore

    @State private var selectedProjectID: URL?
    @State private var projectPendingDeletion: ProjectSummary?

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        managementBody
            .frame(minWidth: 860, minHeight: 520)
            .onAppear {
                store.refreshProjectSummaries()
                syncSelection()
            }
            .alert(
                "删除此 Session？",
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
                Text("将删除 Session「\(summary.name)」及其本地目录中的 Luma 数据。此操作不可撤回。")
            }
    }

    // MARK: - Management (split view)

    private var managementBody: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session 库")
                        .font(.title2.weight(.semibold))
                    Text("查看、打开或删除本机 Session。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("刷新") {
                    store.refreshProjectSummaries()
                    syncSelection()
                }
                .stitchHoverDimming()
                Button("关闭") {
                    store.closeProjectLibrary()
                }
                .stitchHoverDimming()
            }
            .padding(20)

            Divider()

            if store.projectSummaries.isEmpty {
                ContentUnavailableView(
                    "暂无 Session",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("通过「导入」从文件夹、SD 卡或 iPhone 创建 Session；或确认本机应用支持目录中已有项目。")
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
                                "未选择 Session",
                                systemImage: "folder",
                                description: Text("在左侧列表中选择一个 Session 以查看路径、素材数量与操作。")
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(24)
                }
            }
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
                    Text("当前")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
            }

            Text("本地路径与素材摘要")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            LabeledContent("创建时间", value: summary.createdAt.formatted(date: .abbreviated, time: .shortened))
            LabeledContent("照片数量", value: summary.assetCountDescription)
            LabeledContent("分组数量", value: summary.groupCountDescription)
            LabeledContent("文件夹路径", value: summary.directory.path)

            if case .unavailable(let reason) = summary.state {
                VStack(alignment: .leading, spacing: 8) {
                    Text("无法打开")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(reason)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("可检查磁盘是否已断开、权限或 manifest 是否损坏。")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if !summary.isCurrent {
                Text("打开后将进入选片工作区，可筛选、评分与导出。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([summary.directory])
            } label: {
                Label("在访达中显示", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .stitchHoverDimming()

            Spacer()

            HStack {
                Button("打开") {
                    store.openProject(summary)
                }
                .disabled(summary.isCurrent || !summary.isOpenable)
                .stitchHoverDimming()

                Button("删除", role: .destructive) {
                    projectPendingDeletion = summary
                }
                .stitchHoverDimming(opacity: 0.88)

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
                } else if !summary.isOpenable {
                    Text("不可用")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
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
