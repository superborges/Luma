import Foundation

protocol ExportDestinationAdapter: Sendable {
    var displayName: String { get }
    func export(assets: [MediaAsset], groups: [PhotoGroup], options: ExportOptions) async throws -> ExportResult
    func validateConfiguration(options: ExportOptions) async throws -> Bool
}

struct ExportResult: Codable, Hashable {
    let exportedCount: Int
    let skippedCount: Int
    let destinationDescription: String
}
