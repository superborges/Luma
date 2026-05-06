import SwiftUI

private let _relativeFormatter: RelativeDateTimeFormatter = {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f
}()

struct ActionJobListView: View {
    @Bindable var store: LibraryStore

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.activeActionJobs.isEmpty && store.completedActionJobs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        if !store.activeActionJobs.isEmpty {
                            sectionHeader("进行中")
                            ForEach(store.activeActionJobs) { job in
                                jobRow(job)
                                Divider().padding(.horizontal, 16)
                            }
                        }
                        if !store.completedActionJobs.isEmpty {
                            sectionHeader("已完成")
                            ForEach(store.completedActionJobs.prefix(20)) { job in
                                jobRow(job)
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StitchTheme.background)
        .task {
            store.refreshActionJobs()
        }
    }

    private var header: some View {
        HStack {
            Text("任务")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(white: 0.93))
            Spacer()
            Button {
                store.refreshActionJobs()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(StitchTheme.topBarBackground)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(StitchTypography.font(size: 10, weight: .bold))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(1.2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func jobRow(_ job: ActionJob) -> some View {
        HStack(spacing: 10) {
            statusIcon(job.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel(job.kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(white: 0.85))
                HStack(spacing: 6) {
                    Text(statusLabel(job.status))
                        .font(.system(size: 10))
                        .foregroundStyle(statusColor(job.status))
                    if let date = job.completedAt {
                        Text(_relativeFormatter.localizedString(for: date, relativeTo: Date()))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.4))
                    }
                }
            }
            Spacer()
            if job.targetAssetIds.count > 0 {
                Text("\(job.targetAssetIds.count) 张")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func statusIcon(_ status: JobStatus) -> some View {
        Group {
            switch status {
            case .pending:
                Image(systemName: "clock").foregroundStyle(.yellow)
            case .running:
                ProgressView().controlSize(.mini)
            case .completed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .cancelled:
                Image(systemName: "slash.circle").foregroundStyle(.gray)
            }
        }
        .font(.system(size: 14))
        .frame(width: 20)
    }

    private func kindLabel(_ kind: ActionKind) -> String {
        switch kind {
        case .archiveVideo: return "归档视频"
        case .archiveLowres: return "低清保留"
        case .archiveMarkerOnly: return "仅标记归档"
        case .exportToFolder: return "导出到文件夹"
        case .syncAlbumToPhotos: return "同步到 Photos"
        }
    }

    private func statusLabel(_ status: JobStatus) -> String {
        switch status {
        case .pending: return "等待中"
        case .running: return "执行中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private func statusColor(_ status: JobStatus) -> Color {
        switch status {
        case .pending: return .yellow
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(Color(white: 0.25))
            Text("暂无任务")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
