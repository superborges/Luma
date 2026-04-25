import Foundation

/// 相册导入等**高风险路径**的同步落盘“面包屑”，不依赖 `RuntimeTrace` 的 `Task` 异步写入。
/// 若进程在 Swift 并发 / PhotoKit 回调中 SIGSEGV，事后可看 `import-breadcrumb.jsonl` 最后一行判断卡在哪一阶段。
enum ImportPathBreadcrumb {
    private static let queue = DispatchQueue(label: "com.luma.import-breadcrumb")
    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return enc
    }()

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    static func mark(_ name: String, _ metadata: [String: String] = [:]) {
        guard isEnabled else { return }
        queue.sync {
            Self.appendLineSync(name: name, metadata: metadata)
        }
    }

    private struct Line: Encodable {
        let timestamp: String
        let name: String
        let metadata: [String: String]
    }

    private static func appendLineSync(name: String, metadata: [String: String]) {
        do {
            let url = try AppDirectories.diagnosticsRoot().appendingPathComponent("import-breadcrumb.jsonl")
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let line = Line(
                timestamp: ISO8601DateFormatter().string(from: .now),
                name: name,
                metadata: metadata
            )
            let data = try encoder.encode(line) + Data([0x0A])
            if let h = try? FileHandle(forWritingTo: url) {
                defer { try? h.close() }
                try h.seekToEnd()
                try h.write(contentsOf: data)
            }
        } catch {
            // 诊断写失败不打扰主流程
        }
    }
}
