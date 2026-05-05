import Foundation

enum FileNamingResolver {

    /// 根据命名规则生成目标文件名（含扩展名）。
    static func resolvedFileName(
        originalName: String,
        captureDate: Date,
        groupName: String,
        sequenceInGroup: Int,
        rule: FileNamingRule,
        template: String
    ) -> String {
        switch rule {
        case .original:
            return originalName

        case .datePrefix:
            let prefix = datePrefixFormatter.string(from: captureDate)
            return "\(prefix)_\(originalName)"

        case .custom:
            let effectiveTemplate = template.isEmpty ? "{original}" : template
            let ext = (originalName as NSString).pathExtension
            let stem = (originalName as NSString).deletingPathExtension
            let sanitizedGroup = AppDirectories.sanitizePathComponent(groupName)

            var result = effectiveTemplate
            result = result.replacingOccurrences(of: "{original}", with: stem)
            result = result.replacingOccurrences(of: "{date}", with: datePrefixFormatter.string(from: captureDate))
            result = result.replacingOccurrences(of: "{datetime}", with: dateTimePrefixFormatter.string(from: captureDate))
            result = result.replacingOccurrences(of: "{group}", with: sanitizedGroup)
            result = result.replacingOccurrences(of: "{seq}", with: String(format: "%04d", sequenceInGroup))

            if ext.isEmpty {
                return result
            }
            return "\(result).\(ext)"
        }
    }

    /// 给定基础 URL，如果目标目录中已存在同名文件，追加 `-2`、`-3` 等后缀直到不冲突。
    static func uniqueURL(for baseURL: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let ext = baseURL.pathExtension
        let stem = ext.isEmpty
            ? baseURL.lastPathComponent
            : (baseURL.lastPathComponent as NSString).deletingPathExtension

        var candidate = baseURL
        var counter = 2
        while fm.fileExists(atPath: candidate.path) {
            let newName = ext.isEmpty ? "\(stem)-\(counter)" : "\(stem)-\(counter).\(ext)"
            candidate = directory.appendingPathComponent(newName)
            counter += 1
        }
        return candidate
    }

    // MARK: - Private formatters

    private static let datePrefixFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dateTimePrefixFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
