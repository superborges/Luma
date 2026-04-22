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

            // 孤儿清理：项目目录已被用户或系统删除（比如挪去废纸篓），对应 session 不再可恢复，静默丢弃。
            if let projectDirectory = session.projectDirectory,
               !FileManager.default.fileExists(atPath: projectDirectory.path) {
                try? FileManager.default.removeItem(at: url)
                continue
            }

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
