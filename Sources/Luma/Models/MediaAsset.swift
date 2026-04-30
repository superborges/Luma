import Foundation

struct MediaAsset: Identifiable, Codable, Hashable {
    let id: UUID
    let importResumeKey: String
    let baseName: String
    let source: ImportSource
    var previewURL: URL?
    var rawURL: URL?
    var livePhotoVideoURL: URL?
    var depthData: Bool
    var thumbnailURL: URL?
    let metadata: EXIFData
    let mediaType: MediaType
    var importState: ImportState
    var aiScore: AIScore?
    var editSuggestions: EditSuggestions?
    var userDecision: Decision
    var userRating: Int?
    var issues: [AssetIssue]

    var primaryDisplayURL: URL? {
        previewURL ?? rawURL ?? thumbnailURL
    }

    var dimensionsDescription: String {
        "\(metadata.imageWidth) × \(metadata.imageHeight)"
    }

    var isTechnicallyRejected: Bool {
        !issues.isEmpty
    }

    var effectiveRating: Int {
        if let userRating {
            return min(max(userRating, 1), 5)
        }

        let overall = aiScore?.overall ?? 0
        switch overall {
        case 90...:
            return 5
        case 75..<90:
            return 4
        case 60..<75:
            return 3
        case 45..<60:
            return 2
        default:
            return 1
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case importResumeKey
        case baseName
        case source
        case previewURL
        case rawURL
        case livePhotoVideoURL
        case depthData
        case thumbnailURL
        case metadata
        case mediaType
        case importState
        case aiScore
        case editSuggestions
        case userDecision
        case userRating
        case issues
    }

    init(
        id: UUID,
        importResumeKey: String,
        baseName: String,
        source: ImportSource,
        previewURL: URL?,
        rawURL: URL?,
        livePhotoVideoURL: URL?,
        depthData: Bool,
        thumbnailURL: URL?,
        metadata: EXIFData,
        mediaType: MediaType,
        importState: ImportState,
        aiScore: AIScore?,
        editSuggestions: EditSuggestions?,
        userDecision: Decision,
        userRating: Int?,
        issues: [AssetIssue]
    ) {
        self.id = id
        self.importResumeKey = importResumeKey
        self.baseName = baseName
        self.source = source
        self.previewURL = previewURL
        self.rawURL = rawURL
        self.livePhotoVideoURL = livePhotoVideoURL
        self.depthData = depthData
        self.thumbnailURL = thumbnailURL
        self.metadata = metadata
        self.mediaType = mediaType
        self.importState = importState
        self.aiScore = aiScore
        self.editSuggestions = editSuggestions
        self.userDecision = userDecision
        self.userRating = userRating
        self.issues = issues
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        baseName = try container.decode(String.self, forKey: .baseName)
        importResumeKey = try container.decodeIfPresent(String.self, forKey: .importResumeKey) ?? baseName.lowercased()
        source = try container.decode(ImportSource.self, forKey: .source)
        previewURL = try container.decodeIfPresent(URL.self, forKey: .previewURL)
        rawURL = try container.decodeIfPresent(URL.self, forKey: .rawURL)
        livePhotoVideoURL = try container.decodeIfPresent(URL.self, forKey: .livePhotoVideoURL)
        depthData = try container.decode(Bool.self, forKey: .depthData)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        metadata = try container.decode(EXIFData.self, forKey: .metadata)
        mediaType = try container.decode(MediaType.self, forKey: .mediaType)
        importState = try container.decode(ImportState.self, forKey: .importState)
        aiScore = try container.decodeIfPresent(AIScore.self, forKey: .aiScore)
        editSuggestions = try container.decodeIfPresent(EditSuggestions.self, forKey: .editSuggestions)
        userDecision = try container.decode(Decision.self, forKey: .userDecision)
        userRating = try container.decodeIfPresent(Int.self, forKey: .userRating)
        issues = try container.decodeIfPresent([AssetIssue].self, forKey: .issues) ?? []
    }
}

enum ImportSource: Codable, Hashable {
    case sdCard(volumePath: String)
    case iPhone(deviceID: String)
    case folder(path: String)
    case photosLibrary(localIdentifier: String)
}

enum MediaType: String, Codable, Hashable {
    case photo
    case livePhoto
    case portrait
}

enum ImportState: String, Codable, Hashable {
    case discovered
    case thumbnailReady
    case previewCopied
    case rawCopied
    case complete
}

enum Decision: String, Codable, Hashable {
    case pending
    case picked
    case rejected
}

enum AssetIssue: String, Codable, Hashable, CaseIterable, Identifiable {
    case blurry
    case overexposed
    case underexposed
    case eyesClosed
    case unsupportedFormat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blurry:
            return "模糊"
        case .overexposed:
            return "过曝"
        case .underexposed:
            return "欠曝"
        case .eyesClosed:
            return "面部异常"
        case .unsupportedFormat:
            return "不支持"
        }
    }
}
