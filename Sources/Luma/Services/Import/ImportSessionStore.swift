import Foundation

enum ImportSessionStore {
    static func save(_ session: ImportSession) throws {
        let data = try JSONEncoder.lumaEncoder.encode(session)
        try data.write(to: try AppDirectories.importSessionURL(id: session.id), options: [.atomic])
    }

    static func delete(_ session: ImportSession) throws {
        let url = try AppDirectories.importSessionURL(id: session.id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func loadRecoverableSessions() throws -> [ImportSession] {
        let root = try AppDirectories.importSessionsRoot()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var sessions: [ImportSession] = []

        for url in urls {
            let data = try Data(contentsOf: url)
            var session = try JSONDecoder.lumaDecoder.decode(ImportSession.self, from: data)
            guard session.status != .completed else { continue }

            if session.status == .running {
                session.status = .paused
                session.phase = .paused
                session.updatedAt = .now
                if session.lastError == nil {
                    session.lastError = "Luma 上次退出时导入尚未完成。"
                }
                try save(session)
            }

            sessions.append(session)
        }

        return sessions.sorted { $0.updatedAt > $1.updatedAt }
    }

    static func deleteSessions(forProjectDirectory projectDirectory: URL) throws {
        let sessions = try loadRecoverableSessions()
        for session in sessions where session.projectDirectory.map({ sameLocation($0, projectDirectory) }) ?? false {
            try delete(session)
        }
    }

    private static func sameLocation(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.resolvingSymlinksInPath().path == rhs.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
