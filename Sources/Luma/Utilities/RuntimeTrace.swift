import Foundation

struct RuntimeTraceRecord: Encodable {
    let sequence: Int
    let timestamp: Date
    let sessionID: String
    let level: String
    let category: String
    let name: String
    let metadata: [String: String]
}

actor RuntimeTraceStore {
    static let shared = RuntimeTraceStore()

    private let sessionID: String
    private let sessionStartedAt: Date
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private let isEnabled: Bool
    private let maxArchivedSessions: Int
    private var hasStartedSession = false
    private var sequence = 0
    private var latestTraceURL: URL?
    private var sessionTraceURL: URL?
    private var latestHandle: FileHandle?
    private var sessionHandle: FileHandle?

    init(
        sessionID: String = UUID().uuidString,
        sessionStartedAt: Date = .now,
        isEnabled: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        maxArchivedSessions: Int = 20
    ) {
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.isEnabled = isEnabled
        self.maxArchivedSessions = maxArchivedSessions
    }

    func startSession(metadata: [String: String] = [:]) {
        guard isEnabled, !hasStartedSession else { return }
        hasStartedSession = true
        let destination: TraceDestination?
        if let resolved = try? resolvedTraceDestination() {
            destination = resolved
        } else {
            destination = nil
        }

        var combinedMetadata = metadata.merging([
            "session_id": sessionID,
            "process_id": String(ProcessInfo.processInfo.processIdentifier)
        ]) { _, new in new }
        if let destination {
            combinedMetadata["latest_trace_file"] = destination.latestURL.path
            combinedMetadata["session_trace_file"] = destination.sessionURL.path
        }

        append(
            level: "info",
            category: "app",
            name: "session_started",
            metadata: combinedMetadata
        )
    }

    func event(_ name: String, category: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        append(level: "info", category: category, name: name, metadata: metadata)
    }

    func metric(_ name: String, category: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        append(level: "metric", category: category, name: name, metadata: metadata)
    }

    func error(_ name: String, category: String, metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        append(level: "error", category: category, name: name, metadata: metadata)
    }

    func latestTraceFileURL() -> URL? {
        latestTraceURL
    }

    func sessionTraceFileURL() -> URL? {
        sessionTraceURL
    }

    private func append(level: String, category: String, name: String, metadata: [String: String]) {
        sequence += 1
        let record = RuntimeTraceRecord(
            sequence: sequence,
            timestamp: .now,
            sessionID: sessionID,
            level: level,
            category: category,
            name: name,
            metadata: metadata
        )

        do {
            let destination = try resolvedTraceDestination()
            let line = try encoder.encode(record) + Data([0x0A])
            try append(line: line, to: destination.latestHandle)
            try append(line: line, to: destination.sessionHandle)
        } catch {
            return
        }
    }

    private func append(line: Data, to handle: FileHandle) throws {
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func resolvedTraceDestination() throws -> TraceDestination {
        if let latestTraceURL,
           let sessionTraceURL,
           let latestHandle,
           let sessionHandle {
            return TraceDestination(
                latestURL: latestTraceURL,
                sessionURL: sessionTraceURL,
                latestHandle: latestHandle,
                sessionHandle: sessionHandle
            )
        }

        let latestURL = try AppDirectories.runtimeTraceLatestURL()
        let sessionURL = try AppDirectories.runtimeTraceSessionURL(
            startedAt: sessionStartedAt,
            sessionID: sessionID
        )

        try Data().write(to: latestURL, options: [.atomic])
        try Data().write(to: sessionURL, options: [.atomic])
        try rotateArchivedSessionsIfNeeded(excluding: sessionURL)

        latestTraceURL = latestURL
        sessionTraceURL = sessionURL
        latestHandle = try Self.openAppendHandle(for: latestURL)
        sessionHandle = try Self.openAppendHandle(for: sessionURL)
        return TraceDestination(
            latestURL: latestURL,
            sessionURL: sessionURL,
            latestHandle: latestHandle!,
            sessionHandle: sessionHandle!
        )
    }

    private func rotateArchivedSessionsIfNeeded(excluding currentSessionURL: URL) throws {
        let root = try AppDirectories.runtimeTraceSessionsRoot()
        let sessionFiles = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "jsonl" }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }

        guard sessionFiles.count > maxArchivedSessions else { return }

        for file in sessionFiles.dropFirst(maxArchivedSessions) where file != currentSessionURL {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func openAppendHandle(for url: URL) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }
}

private struct TraceDestination {
    let latestURL: URL
    let sessionURL: URL
    let latestHandle: FileHandle
    let sessionHandle: FileHandle
}

enum RuntimeTrace {
    static func startSession(metadata: [String: String] = [:]) {
        Task {
            await RuntimeTraceStore.shared.startSession(metadata: metadata)
        }
    }

    static func event(_ name: String, category: String, metadata: [String: String] = [:]) {
        Task {
            await RuntimeTraceStore.shared.event(name, category: category, metadata: metadata)
        }
    }

    static func metric(_ name: String, category: String, metadata: [String: String] = [:]) {
        Task {
            await RuntimeTraceStore.shared.metric(name, category: category, metadata: metadata)
        }
    }

    static func error(_ name: String, category: String, metadata: [String: String] = [:]) {
        Task {
            await RuntimeTraceStore.shared.error(name, category: category, metadata: metadata)
        }
    }

    static func latestTraceFileURL() async -> URL? {
        await RuntimeTraceStore.shared.latestTraceFileURL()
    }

    static func sessionTraceFileURL() async -> URL? {
        await RuntimeTraceStore.shared.sessionTraceFileURL()
    }
}
