import Foundation

/// `ScoringJob` 的磁盘持久化（每个 project 一份 `scoring_job.json`）。
///
/// 设计取舍：
/// - 与 manifest 同目录，跟随项目移动 / 删除
/// - 仅在评分进行中存在；`clear()` 在任务完成（或显式取消）后删除文件
/// - 写盘走原子重命名（先写 `.tmp` 再 rename）避免崩溃时半文件
/// - 协议层抽出来便于单测；默认实现 `FileScoringJobStore` 落到磁盘
protocol ScoringJobStore: Sendable {
    func load(in projectDirectory: URL) throws -> ScoringJob?
    func save(_ job: ScoringJob, in projectDirectory: URL) throws
    func clear(in projectDirectory: URL) throws
}

/// 默认实现：原子写入 `scoring_job.json`。
struct FileScoringJobStore: ScoringJobStore {
    init() {}

    func load(in projectDirectory: URL) throws -> ScoringJob? {
        let url = AppDirectories.scoringJobURL(in: projectDirectory)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(ScoringJob.self, from: data)
        } catch {
            // 解析失败：保留文件以便诊断，但返回 nil 让上层视为"无在途任务"。
            RuntimeTrace.event(
                "scoring_job_load_failed",
                category: "ai_scoring",
                metadata: ["error": error.localizedDescription]
            )
            return nil
        }
    }

    func save(_ job: ScoringJob, in projectDirectory: URL) throws {
        let url = AppDirectories.scoringJobURL(in: projectDirectory)
        let tmp = url.appendingPathExtension("tmp")
        let data = try JSONEncoder().encode(job)
        try FileManager.default.createDirectory(
            at: projectDirectory,
            withIntermediateDirectories: true
        )
        try data.write(to: tmp, options: [.atomic])
        // 替换原文件
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
    }

    func clear(in projectDirectory: URL) throws {
        let url = AppDirectories.scoringJobURL(in: projectDirectory)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}

/// 测试用 mock：内存中保存"虚拟"项目目录到 ScoringJob 的映射。
final class InMemoryScoringJobStore: ScoringJobStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL: ScoringJob] = [:]

    init() {}

    func load(in projectDirectory: URL) throws -> ScoringJob? {
        lock.lock()
        defer { lock.unlock() }
        return storage[projectDirectory]
    }

    func save(_ job: ScoringJob, in projectDirectory: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        storage[projectDirectory] = job
    }

    func clear(in projectDirectory: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: projectDirectory)
    }
}
