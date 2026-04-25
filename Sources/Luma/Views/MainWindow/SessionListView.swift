import SwiftUI

/// 首页 Session 列表：展示所有 Session、新建 Import Session、排序、打开/归档/删除。
struct SessionListView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.06))
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StitchTheme.background)
        .onAppear { store.refreshProjectSummaries() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Session")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurface)
                Text("导入素材 → 选片（当前页）→ 导出；从下方选择已有项目或新建导入")
                    .font(.system(size: 12))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
            }
            Spacer(minLength: 0)
            sortMenu
            Menu {
                ImportSourceMenuItems(store: store)
            } label: {
                Label("新建 Import Session", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(StitchTheme.primary)
                    )
                    .foregroundStyle(StitchTheme.onPrimary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SessionListSort.allCases) { sort in
                Button {
                    store.updateSessionListSort(sort)
                } label: {
                    if sort == store.sessionListSort {
                        Label(sort.label, systemImage: "checkmark")
                    } else {
                        Text(sort.label)
                    }
                }
            }
        } label: {
            Label("排序：\(store.sessionListSort.label)", systemImage: "arrow.up.arrow.down")
                .font(.system(size: 12))
                .foregroundStyle(StitchTheme.onSurfaceVariant)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(StitchTheme.surfaceContainer)
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if store.projectSummaries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.projectSummaries) { summary in
                        SessionRow(summary: summary) {
                            store.openProject(summary)
                        } onArchiveToggle: {
                            store.setArchive(summary, archived: !summary.isArchived)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(StitchTheme.onSurfaceVariant.opacity(0.6))
            Text("还没有 Session")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(StitchTheme.onSurface)
            Text("点击右上角「新建 Import Session」开始导入")
                .font(.system(size: 12))
                .foregroundStyle(StitchTheme.onSurfaceVariant)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    let summary: ProjectSummary
    let onOpen: () -> Void
    let onArchiveToggle: () -> Void

    // 不要在此使用 `Button` / `.onTapGesture` / 叠加手势：`AppKitEventBindingBridge.flushActions` 会在
    // macOS 26 / Swift 6.2 经该路径回写 SwiftUI 时触发 `SessionRow` body 里闭包的 executor 校验
    // → `swift_task_isCurrentExecutorWithFlagsImpl` + `pc=0`（见 KNOWN_ISSUES Round 10）。
    // 主区域用 `NSView.mouseDown`（`SessionRowOpenHitView`）打开，视觉层 `.allowsHitTesting(false)`。
    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .leading) {
                rowContent
                    .allowsHitTesting(false)
                SessionRowOpenHitView(onOpen: onOpen)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Menu {
                Button("打开") { onOpen() }
                    .disabled(!summary.isOpenable)
                Divider()
                Button(summary.isArchived ? "取消归档" : "归档") { onArchiveToggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
                    .padding(8)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .opacity(summary.isArchived ? 0.6 : 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(StitchTheme.surfaceContainer)
        )
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(StitchTheme.surfaceContainerHigh)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 18))
                        .foregroundStyle(StitchTheme.onSurfaceVariant)
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(summary.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StitchTheme.onSurface)
                    if summary.isArchived {
                        statusChip(text: "已归档", tint: .gray)
                    }
                    if summary.isCurrent {
                        statusChip(text: "当前", tint: .blue)
                    }
                    if summary.isCullingComplete {
                        statusChip(text: "选片完成", tint: .green)
                    }
                    if summary.exportJobCount > 0 {
                        statusChip(text: "已导出", tint: .accentColor)
                    }
                }
                Text(summary.stateSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(StitchTheme.onSurfaceVariant)
                if summary.totalAssetCount > 0 {
                    progressBar
                }
                if let last = summary.lastExportedAt {
                    Text("最近导出：\(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10))
                        .foregroundStyle(StitchTheme.onSurfaceVariant.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(StitchTheme.onSurfaceVariant.opacity(0.6))
        }
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .frame(width: 140, height: 3)
            Capsule()
                .fill(summary.isCullingComplete ? Color.green : StitchTheme.primary)
                .frame(width: 140 * summary.decisionFraction, height: 3)
        }
    }

    private func statusChip(text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18), in: Capsule())
            .foregroundStyle(tint)
    }
}
