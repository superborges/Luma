import Foundation

enum AppDirectories {
    static func applicationSupportRoot() throws -> URL {
        if let overrideRoot = overrideApplicationSupportRoot() {
            try FileManager.default.createDirectory(at: overrideRoot, withIntermediateDirectories: true)
            return overrideRoot
        }

        let url = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = url.appendingPathComponent("Luma", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func projectsRoot() throws -> URL {
        let root = try applicationSupportRoot().appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func createProjectDirectory(named name: String, createdAt: Date = .now) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let safeName = sanitizePathComponent(name)
        let directory = try projectsRoot().appendingPathComponent(
            "\(formatter.string(from: createdAt))_\(safeName)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let subdirectories = ["thumbnails", "preview", "raw", "auxiliary"]
        for subdirectory in subdirectories {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(subdirectory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }

        return directory
    }

    static func projectDirectories() throws -> [URL] {
        let root = try projectsRoot()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )

        return urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    static func manifestURL(in projectDirectory: URL) -> URL {
        projectDirectory.appendingPathComponent("manifest.json")
    }

    /// V2 云端评分任务持久化文件，与 manifest 同目录。仅在评分中存在；
    /// 任务完成后由 ScoringJobStore.clear 删除，避免与 manifest 状态发生不一致。
    static func scoringJobURL(in projectDirectory: URL) -> URL {
        projectDirectory.appendingPathComponent("scoring_job.json")
    }

    static func archivesRoot() throws -> URL {
        let root = try applicationSupportRoot().appendingPathComponent("archives", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func importSessionsRoot() throws -> URL {
        let root = try applicationSupportRoot().appendingPathComponent("ImportSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func diagnosticsRoot() throws -> URL {
        let root = try applicationSupportRoot().appendingPathComponent("Diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func runtimeTraceURL() throws -> URL {
        try runtimeTraceLatestURL()
    }

    static func runtimeTraceLatestURL() throws -> URL {
        try diagnosticsRoot().appendingPathComponent("runtime-latest.jsonl")
    }

    static func runtimeTraceSessionsRoot() throws -> URL {
        let root = try diagnosticsRoot().appendingPathComponent("RuntimeSessions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func runtimeTraceSessionURL(startedAt: Date, sessionID: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        let fileName = "\(formatter.string(from: startedAt))_\(sanitizePathComponent(sessionID)).jsonl"
        return try runtimeTraceSessionsRoot().appendingPathComponent(fileName)
    }

    static func importSessionURL(id: UUID) throws -> URL {
        try importSessionsRoot().appendingPathComponent("\(id.uuidString).json")
    }

    /// 与 `import-breadcrumb.jsonl` 同目录；设置页可展示，便于随 trace 一起打包反馈。
    static func importBreadcrumbFileURL() throws -> URL {
        try diagnosticsRoot().appendingPathComponent("import-breadcrumb.jsonl")
    }

    static func archiveBatchDirectory(named name: String) throws -> URL {
        let directory = try archivesRoot().appendingPathComponent(sanitizePathComponent(name), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func sanitizePathComponent(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.illegalCharacters)
            .union(.controlCharacters)
        let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Luma_Project" : trimmed
    }

    private static func overrideApplicationSupportRoot() -> URL? {
        guard let rawPointer = getenv("LUMA_APP_SUPPORT_ROOT"),
              let rawValue = String(validatingCString: rawPointer),
              !rawValue.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: rawValue, isDirectory: true)
    }
}
