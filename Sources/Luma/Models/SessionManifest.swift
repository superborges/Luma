import Foundation

/// Luma Session 的磁盘表示（项目目录下 manifest.json）。
///
/// `id` 必须等于 `session.id`，在多次保存之间保持稳定。
/// 解码兼容旧 `expedition` 字段（从 v0 迁移而来）；写入使用新 `session` 字段。
///
/// `schemaVersion` 用于将来的迁移：
/// - 1：v0 expedition 格式；
/// - 2：v1 session 格式 + ExportJob 增量字段（cleanedCount/failures/...）。
/// 当前默认 = `currentSchemaVersion`，旧格式解码后回填为 1，写入时自动升级到当前值。
struct SessionManifest: Identifiable, Codable, Hashable {
    static let currentSchemaVersion = 2

    let id: UUID
    var session: Session
    var schemaVersion: Int = currentSchemaVersion

    var name: String {
        get { session.name }
        set { session.name = newValue; session.updatedAt = .now }
    }

    var createdAt: Date {
        get { session.createdAt }
        set { session.createdAt = newValue; session.updatedAt = .now }
    }

    var assets: [MediaAsset] {
        get { session.assets }
        set { session.assets = newValue; session.updatedAt = .now }
    }

    var groups: [PhotoGroup] {
        get { session.groups }
        set { session.groups = newValue; session.updatedAt = .now }
    }

    init(id: UUID, session: Session, schemaVersion: Int = SessionManifest.currentSchemaVersion) {
        self.id = id
        self.schemaVersion = schemaVersion
        var s = session
        if s.id != id {
            s = Session(
                id: id,
                name: s.name,
                createdAt: s.createdAt,
                updatedAt: s.updatedAt,
                location: s.location,
                tags: s.tags,
                coverAssetID: s.coverAssetID,
                assets: s.assets,
                groups: s.groups,
                importSessions: s.importSessions,
                editingSessions: s.editingSessions,
                exportJobs: s.exportJobs
            )
        }
        self.session = s
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case session
        case schemaVersion
        case expedition // 兼容 v0 旧字段名
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
        let storedVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion)

        // 新格式
        if let session = try container.decodeIfPresent(Session.self, forKey: .session) {
            self.session = session
            self.schemaVersion = storedVersion ?? SessionManifest.currentSchemaVersion
            return
        }
        // v0 旧字段 `expedition`（Session 与 Expedition 结构兼容，同一 struct shape）
        if let legacy = try container.decodeIfPresent(Session.self, forKey: .expedition) {
            self.session = legacy
            self.schemaVersion = 1 // v0 没显式版本字段
            return
        }

        // 更早 flat 格式
        let name = try container.decode(String.self, forKey: .name)
        let createdAt = try container.decode(Date.self, forKey: .createdAt)
        let assets = try container.decode([MediaAsset].self, forKey: .assets)
        let groups = try container.decode([PhotoGroup].self, forKey: .groups)
        _ = try container.decodeIfPresent([LegacyManifestSessionStub].self, forKey: .sessions)
        _ = try container.decodeIfPresent(UUID.self, forKey: .activeSessionID)

        session = Session.migratedFromLegacy(
            id: id,
            name: name,
            createdAt: createdAt,
            assets: assets,
            groups: groups
        )
        schemaVersion = 1
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(session, forKey: .session)
        // 写入时永远落到当前版本，下次启动自检直接通过。
        try container.encode(SessionManifest.currentSchemaVersion, forKey: .schemaVersion)
    }
}

extension SessionManifest {
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
        let session = Session(
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
        self.init(id: id, session: session)
    }
}

/// Decodes old `sessions` array entries without preserving them (UI now uses `session.importSessions`).
private struct LegacyManifestSessionStub: Codable, Hashable {
    let id: UUID
}
