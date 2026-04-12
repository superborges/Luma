import SwiftUI

struct ImportsHubView: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                header
                pipelineCard
                actionsCard
                sessionsCard
            }
            .padding(AppSpacing.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("导入总览")
                .font(.title2.weight(.medium))
                .kerning(DesignType.titleKerning)
            Text(store.importsHubSubtitle)
                .font(.callout.weight(.light))
                .foregroundStyle(.secondary)
                .kerning(DesignType.bodyKerning)
        }
    }

    private var pipelineCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("会话阶段")
                .font(.headline.weight(.medium))
            ForEach(store.currentPipelineStages, id: \.stage) { item in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    HStack {
                        Text(stageTitle(item.stage))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(stageStatusTitle(item.status))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(stageStatusColor(item.status))
                    }
                    ProgressView(value: min(max(item.progress, 0), 1))
                        .tint(stageStatusColor(item.status))
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .stitchAdaptiveListRowHover()
            }
        }
        .padding(AppSpacing.gutter)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous))
    }

    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("导入动作")
                .font(.headline.weight(.medium))
            HStack(spacing: AppSpacing.sm) {
                Button("导入文件夹") { Task { await store.importFolder() } }
                    .stitchHoverDimming()
                Button("导入 SD 卡") { Task { await store.importSDCard() } }
                    .stitchHoverDimming()
                Button("导入 iPhone") { Task { await store.importIPhone() } }
                    .stitchHoverDimming()
                if store.recoverableImportSession != nil {
                    Button("继续导入") { Task { await store.resumeRecoverableImport() } }
                        .disabled(store.isImporting)
                        .stitchHoverDimming()
                }
            }
            .buttonStyle(.borderedProminent)

            if let progress = store.importProgress, store.isImporting || progress.phase == .paused {
                Text(importPhaseTitle(progress.phase) + " \(progress.completed)/\(progress.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.gutter)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous))
    }

    private var sessionsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("会话")
                .font(.headline.weight(.medium))
            if store.expeditionImportSessions.isEmpty {
                Text("暂无导入会话记录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.expeditionImportSessions) { session in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.displayProjectName)
                            .font(.subheadline.weight(.medium))
                        Text("\(session.source.displayName) · \(session.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(session.status.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .stitchAdaptiveListRowHover()
                }
            }
        }
        .padding(AppSpacing.gutter)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous))
    }

    private func stageTitle(_ stage: SessionPipelineStage) -> String {
        switch stage {
        case .ingest: return "Ingest 导入"
        case .group: return "Group 分组"
        case .score: return "Score 评分"
        case .cull: return "Cull 筛选"
        case .editing: return "Editing 编辑"
        case .export: return "Export 导出"
        }
    }

    private func stageStatusTitle(_ status: SessionStageStatus) -> String {
        switch status {
        case .pending: return "待开始"
        case .running: return "进行中"
        case .completed: return "已完成"
        case .failed: return "异常"
        }
    }

    private func stageStatusColor(_ status: SessionStageStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return LumaSemantic.ai
        case .completed: return LumaSemantic.pick
        case .failed: return LumaSemantic.reject
        }
    }

    private func importPhaseTitle(_ phase: ImportPhase) -> String {
        switch phase {
        case .scanning:
            return "扫描素材"
        case .preparingThumbnails:
            return "准备缩略图"
        case .copyingPreviews:
            return "拷贝预览图"
        case .copyingOriginals:
            return "拷贝原图"
        case .paused:
            return "导入暂停"
        case .finalizing:
            return "整理项目"
        }
    }
}
