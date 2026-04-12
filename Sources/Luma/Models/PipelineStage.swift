import Foundation

enum SessionPipelineStage: String, Codable, Hashable, CaseIterable {
    case ingest
    case group
    case score
    case cull
    case editing
    case export
}

enum SessionStageStatus: String, Codable, Hashable {
    case pending
    case running
    case completed
    case failed
}

struct SessionStageState: Codable, Hashable {
    var stage: SessionPipelineStage
    var status: SessionStageStatus
    var progress: Double
}

enum PipelineStageStatus: String, Codable, Hashable {
    case pending
    case running
    case completed
}

struct StageProgress: Hashable {
    var status: PipelineStageStatus
    var progress: Double
}

struct PipelineStatus: Hashable {
    var ingest: StageProgress
    var group: StageProgress
    var score: StageProgress
    var cull: StageProgress
    var editing: StageProgress
    var export: StageProgress
}
