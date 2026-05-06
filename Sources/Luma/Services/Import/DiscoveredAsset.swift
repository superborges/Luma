import Foundation

struct DiscoveredAsset: Identifiable, Sendable {
    let id: UUID
    let baseName: String
    let sourceKind: AssetSourceKind
    let externalIdentifier: String?
    let previewFileURL: URL?
    let rawFileURL: URL?
    let auxiliaryFileURL: URL?
    let metadata: EXIFData
    let mediaType: MediaType
    let suggestedStorageMode: AssetStorageMode
    let contentHashHint: String?

    init(
        id: UUID = UUID(),
        baseName: String,
        sourceKind: AssetSourceKind,
        externalIdentifier: String? = nil,
        previewFileURL: URL? = nil,
        rawFileURL: URL? = nil,
        auxiliaryFileURL: URL? = nil,
        metadata: EXIFData,
        mediaType: MediaType,
        suggestedStorageMode: AssetStorageMode,
        contentHashHint: String? = nil
    ) {
        self.id = id
        self.baseName = baseName
        self.sourceKind = sourceKind
        self.externalIdentifier = externalIdentifier
        self.previewFileURL = previewFileURL
        self.rawFileURL = rawFileURL
        self.auxiliaryFileURL = auxiliaryFileURL
        self.metadata = metadata
        self.mediaType = mediaType
        self.suggestedStorageMode = suggestedStorageMode
        self.contentHashHint = contentHashHint
    }
}
