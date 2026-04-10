import Foundation

/// On-disk representation of a project.
///
/// `id` is assigned once at project creation and must remain stable across all
/// subsequent saves. `ProjectStore` captures `id` in `currentManifestID` when
/// loading a manifest and reuses it on every write, so callers must never
/// generate a fresh UUID when re-serialising an existing project.
struct ProjectManifest: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var assets: [MediaAsset]
    var groups: [PhotoGroup]
}
