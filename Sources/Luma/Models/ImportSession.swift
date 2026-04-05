import Foundation

enum ImportSourceDescriptor: Codable, Hashable, Identifiable {
    case folder(path: String, displayName: String)
    case sdCard(volumePath: String, displayName: String)
    case iPhone(deviceID: String, deviceName: String)

    var id: String {
        stableID
    }

    var stableID: String {
        switch self {
        case .folder(let path, _):
            return "folder:\(path)"
        case .sdCard(let volumePath, _):
            return "sd:\(volumePath)"
        case .iPhone(let deviceID, _):
            return "iphone:\(deviceID)"
        }
    }

    var displayName: String {
        switch self {
        case .folder(_, let displayName):
            return displayName
        case .sdCard(_, let displayName):
            return displayName
        case .iPhone(_, let deviceName):
            return deviceName
        }
    }

    var suggestedProjectName: String {
        displayName
    }

    var importSource: ImportSource {
        switch self {
        case .folder(let path, _):
            return .folder(path: path)
        case .sdCard(let volumePath, _):
            return .sdCard(volumePath: volumePath)
        case .iPhone(let deviceID, _):
            return .iPhone(deviceID: deviceID)
        }
    }
}

enum ImportSessionStatus: String, Codable, Hashable {
    case running
    case paused
    case completed
}

struct ImportSessionRecord: Codable, Identifiable, Hashable {
    let id: UUID
    var source: ImportSourceDescriptor
    var projectDirectory: URL
    var projectName: String
    var createdAt: Date
    var updatedAt: Date
    var phase: ImportPhase
    var status: ImportSessionStatus
    var totalItems: Int
    var completedThumbnails: Int
    var completedPreviews: Int
    var completedOriginals: Int
    var lastError: String?

    var progressSummary: String {
        switch phase {
        case .scanning:
            return "扫描素材中"
        case .preparingThumbnails:
            return "准备缩略图 \(completedThumbnails)/\(max(totalItems, 1))"
        case .copyingPreviews:
            return "拷贝预览图 \(completedPreviews)/\(max(totalItems, 1))"
        case .copyingOriginals:
            return "拷贝原图 \(completedOriginals)/\(max(totalItems, 1))"
        case .paused:
            return lastError ?? "导入已暂停"
        case .finalizing:
            return "整理项目中"
        }
    }
}

enum PendingImportPrompt: Hashable, Identifiable {
    case importSource(ImportSourceDescriptor)
    case resumeSession(ImportSessionRecord)

    var id: String {
        switch self {
        case .importSource(let source):
            return "import:\(source.stableID)"
        case .resumeSession(let session):
            return "resume:\(session.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .importSource:
            return "检测到可导入设备"
        case .resumeSession:
            return "发现未完成的导入"
        }
    }

    var message: String {
        switch self {
        case .importSource(let source):
            return "检测到 \(source.displayName)，是否立即开始导入？"
        case .resumeSession(let session):
            return "“\(session.projectName)” 还有未完成的导入。\n\(session.progressSummary)"
        }
    }

    var confirmTitle: String {
        switch self {
        case .importSource:
            return "开始导入"
        case .resumeSession:
            return "继续导入"
        }
    }
}
