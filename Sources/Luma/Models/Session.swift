import Foundation

/// 顶层会话模型。一个 Session 对应用户一次"从源导入 → 选片 → 导出"的完整工作流。
/// v1 从旧 `Expedition` 重命名而来；磁盘格式见 `SessionManifest`。
struct Session: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var location: String?
    var tags: [String]
    var coverAssetID: UUID?
    var assets: [MediaAsset]
    var groups: [PhotoGroup]
    var importSessions: [ImportSession]
    var editingSessions: [EditingSession]
    var exportJobs: [ExportJob]
    /// v1 归档语义：仅是首页列表上的"软标签"。
    /// 不删除项目目录，仅在首页列表里以"已归档"分组靠后展示。
    var isArchived: Bool? = nil
    /// 用户手动归档时的时间，便于排序。
    var archivedAt: Date? = nil

    var assetCount: Int { assets.count }

    var pipelineStatus: PipelineStatus {
        let totalAssets = max(assets.count, 1)
        let hasAssets = !assets.isEmpty
        let scoredCount = assets.filter { $0.aiScore != nil }.count
        let pickedOrRejectedCount = assets.filter { $0.userDecision != .pending }.count

        let ingestCompleted = importSessions.contains { $0.status == .completed }
        let ingestRunning = importSessions.contains { $0.status == .running || $0.status == .paused }
        let ingest: StageProgress
        if ingestRunning {
            ingest = StageProgress(status: .running, progress: 0.5)
        } else if hasAssets || ingestCompleted {
            ingest = StageProgress(status: .completed, progress: 1)
        } else {
            ingest = StageProgress(status: .pending, progress: 0)
        }

        let group: StageProgress
        if groups.isEmpty {
            group = StageProgress(status: hasAssets ? .running : .pending, progress: hasAssets ? 0.35 : 0)
        } else {
            group = StageProgress(status: .completed, progress: 1)
        }

        let score: StageProgress
        if hasAssets, scoredCount == assets.count {
            score = StageProgress(status: .completed, progress: 1)
        } else if scoredCount > 0 {
            score = StageProgress(status: .running, progress: Double(scoredCount) / Double(totalAssets))
        } else {
            score = StageProgress(status: .pending, progress: 0)
        }

        let cull: StageProgress
        if hasAssets, pickedOrRejectedCount == assets.count {
            cull = StageProgress(status: .completed, progress: 1)
        } else if pickedOrRejectedCount > 0 {
            cull = StageProgress(status: .running, progress: Double(pickedOrRejectedCount) / Double(totalAssets))
        } else {
            cull = StageProgress(status: .pending, progress: 0)
        }

        let editingCompleted = editingSessions.contains { $0.status == .completed }
        let editingActive = editingSessions.contains { $0.status == .active || $0.status == .initializing }
        let editing: StageProgress
        if editingActive {
            editing = StageProgress(status: .running, progress: 0.5)
        } else if editingCompleted {
            editing = StageProgress(status: .completed, progress: 1)
        } else {
            editing = StageProgress(status: .pending, progress: 0)
        }

        let exportCompleted = exportJobs.contains { $0.status == .completed }
        let exportRunning = exportJobs.contains { $0.status == .running || $0.status == .queued }
        let export: StageProgress
        if exportRunning {
            export = StageProgress(status: .running, progress: 0.5)
        } else if exportCompleted {
            export = StageProgress(status: .completed, progress: 1)
        } else {
            export = StageProgress(status: .pending, progress: 0)
        }

        return PipelineStatus(
            ingest: ingest,
            group: group,
            score: score,
            cull: cull,
            editing: editing,
            export: export
        )
    }

    static func migratedFromLegacy(
        id: UUID,
        name: String,
        createdAt: Date,
        assets: [MediaAsset],
        groups: [PhotoGroup]
    ) -> Session {
        Session(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: .now,
            location: nil,
            tags: [],
            coverAssetID: assets.first?.id,
            assets: assets,
            groups: groups,
            importSessions: [],
            editingSessions: [],
            exportJobs: [],
            isArchived: false,
            archivedAt: nil
        )
    }
}

extension PipelineStageStatus {
    func toSessionStageStatus() -> SessionStageStatus {
        switch self {
        case .pending: return .pending
        case .running: return .running
        case .completed: return .completed
        }
    }
}

extension Session {
    func sessionStageStatesFromPipeline() -> [SessionStageState] {
        let p = pipelineStatus
        return [
            SessionStageState(stage: .ingest, status: p.ingest.status.toSessionStageStatus(), progress: p.ingest.progress),
            SessionStageState(stage: .group, status: p.group.status.toSessionStageStatus(), progress: p.group.progress),
            SessionStageState(stage: .score, status: p.score.status.toSessionStageStatus(), progress: p.score.progress),
            SessionStageState(stage: .cull, status: p.cull.status.toSessionStageStatus(), progress: p.cull.progress),
            SessionStageState(stage: .editing, status: p.editing.status.toSessionStageStatus(), progress: p.editing.progress),
            SessionStageState(stage: .export, status: p.export.status.toSessionStageStatus(), progress: p.export.progress),
        ]
    }
}
