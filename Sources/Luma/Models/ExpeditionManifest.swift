import Foundation

/// On-disk representation of a Luma expedition (project directory).
///
/// `id` must match `expedition.id` and remain stable across saves.
struct ExpeditionManifest: Identifiable, Codable, Hashable {
    let id: UUID
    var expedition: Expedition

    /// Shims for import pipeline and legacy call sites.
    var name: String {
        get { expedition.name }
        set { expedition.name = newValue; expedition.updatedAt = .now }
    }

    var createdAt: Date {
        get { expedition.createdAt }
        set { expedition.createdAt = newValue; expedition.updatedAt = .now }
    }

    var assets: [MediaAsset] {
        get { expedition.assets }
        set { expedition.assets = newValue; expedition.updatedAt = .now }
    }

    var groups: [PhotoGroup] {
        get { expedition.groups }
        set { expedition.groups = newValue; expedition.updatedAt = .now }
    }

    init(id: UUID, expedition: Expedition) {
        self.id = id
        var exp = expedition
        if exp.id != id {
            exp = Expedition(
                id: id,
                name: exp.name,
                createdAt: exp.createdAt,
                updatedAt: exp.updatedAt,
                location: exp.location,
                tags: exp.tags,
                coverAssetID: exp.coverAssetID,
                assets: exp.assets,
                groups: exp.groups,
                importSessions: exp.importSessions,
                editingSessions: exp.editingSessions,
                exportJobs: exp.exportJobs
            )
        }
        self.expedition = exp
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case expedition
        case name
        case createdAt
        case assets
        case groups
        case sessions
        case activeSessionID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)

        if let expedition = try container.decodeIfPresent(Expedition.self, forKey: .expedition) {
            self.expedition = expedition
            return
        }

        let name = try container.decode(String.self, forKey: .name)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let assets = try container.decode([MediaAsset].self, forKey: .assets)
        let groups = try container.decode([PhotoGroup].self, forKey: .groups)
        _ = try container.decodeIfPresent([LegacyManifestSessionStub].self, forKey: .sessions)
        _ = try container.decodeIfPresent(UUID.self, forKey: .activeSessionID)

        expedition = Expedition.migratedFromLegacy(
            id: id,
            name: name,
            createdAt: createdAt,
            assets: assets,
            groups: groups
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(expedition, forKey: .expedition)
    }
}

extension ExpeditionManifest {
    /// Flat initializer for call sites that previously used `ProjectManifest`.
    init(
        id: UUID,
        name: String,
        createdAt: Date,
        assets: [MediaAsset],
        groups: [PhotoGroup],
        importSessions: [ImportSession] = [],
        editingSessions: [EditingSession] = [],
        exportJobs: [ExportJob] = []
    ) {
        let expedition = Expedition(
            id: id,
            name: name,
            createdAt: createdAt,
            updatedAt: .now,
            location: nil,
            tags: [],
            coverAssetID: assets.first?.id,
            assets: assets,
            groups: groups,
            importSessions: importSessions,
            editingSessions: editingSessions,
            exportJobs: exportJobs
        )
        self.init(id: id, expedition: expedition)
    }
}

/// Decodes old `sessions` array entries without preserving them (UI now uses `expedition.importSessions`).
private struct LegacyManifestSessionStub: Codable, Hashable {
    let id: UUID
}
