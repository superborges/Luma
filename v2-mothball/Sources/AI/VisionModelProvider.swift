import Foundation

protocol VisionModelProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    var apiProtocol: APIProtocol { get }
    var costPer100Images: Double { get }

    func scoreGroup(images: [ImageData], context: GroupContext) async throws -> GroupScoreResult
    func detailedAnalysis(image: ImageData, context: PhotoContext) async throws -> DetailedAnalysisResult
    func testConnection() async throws -> Bool
}

struct ImageData: Sendable {
    let filename: String
    let mimeType: String
    let data: Data
}

struct GroupContext: Sendable {
    let groupName: String
    let cameraModel: String?
    let lensModel: String?
    let timeRangeDescription: String
}

struct PhotoContext: Sendable {
    let groupName: String
    let exifSummary: String
    let initialScore: Int?
}

struct GroupScoreResult: Codable, Hashable {
    let photoResults: [ScoredPhotoResult]
    let groupBest: [Int]
    let groupComment: String?
    let usage: TokenUsage?
}

struct ScoredPhotoResult: Codable, Hashable {
    let index: Int
    let score: AIScore
}

struct DetailedAnalysisResult: Codable, Hashable {
    let suggestions: EditSuggestions
    let rawResponse: String?
    let usage: TokenUsage?
}

struct TokenUsage: Codable, Hashable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
}
