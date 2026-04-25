import Foundation
import Vision

struct BurstReviewCLI {
    struct Configuration {
        let rootURL: URL
        let markdownURL: URL
        let jsonURL: URL
        let splitLimit: Int
        let mergeLimit: Int
    }

    static func requestedConfiguration(from arguments: [String]) -> Configuration? {
        guard let rootPath = value(for: "--burst-review-root", in: arguments) else {
            return nil
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let markdownURL = resolvedOutputURL(
            from: value(for: "--burst-review-output", in: arguments),
            defaultPath: "Artifacts/burst-review-latest.md",
            cwd: cwd
        )
        let jsonURL = resolvedOutputURL(
            from: value(for: "--burst-review-json", in: arguments),
            defaultPath: "Artifacts/burst-review-latest.json",
            cwd: cwd
        )

        return Configuration(
            rootURL: URL(fileURLWithPath: rootPath, isDirectory: true),
            markdownURL: markdownURL,
            jsonURL: jsonURL,
            splitLimit: Int(value(for: "--burst-review-split-limit", in: arguments) ?? "") ?? 15,
            mergeLimit: Int(value(for: "--burst-review-merge-limit", in: arguments) ?? "") ?? 15
        )
    }

    static func run(_ configuration: Configuration) throws {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = BurstReviewResultBox()

        Task {
            do {
                try await BurstReviewExporter(configuration: configuration).export()
                resultBox.store(.success(()))
            } catch {
                resultBox.store(.failure(error))
            }
            semaphore.signal()
        }

        semaphore.wait()
        switch resultBox.load() ?? .success(()) {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func resolvedOutputURL(from rawValue: String?, defaultPath: String, cwd: URL) -> URL {
        let rawPath = rawValue ?? defaultPath
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return cwd.appendingPathComponent(rawPath)
    }
}

private final class BurstReviewResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, Error>?

    func store(_ result: Result<Void, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<Void, Error>? {
        lock.lock()
        let current = result
        lock.unlock()
        return current
    }
}

private struct BurstReviewExporter {
    let configuration: BurstReviewCLI.Configuration

    private let burstPolicy = BurstGroupingPolicy()

    func export() async throws {
        let items = try MediaFileScanner.scan(
            rootFolder: configuration.rootURL,
            source: .folder(path: configuration.rootURL.path)
        )
        let assets = items.map(makeAsset(from:))
        let groupingEngine = GroupingEngine(
            locationNamingProvider: NullLocationNamingProvider(),
            visualSubgroupingProvider: SilentVisualSubgroupingProvider()
        )
        let sceneGroups = await groupingEngine.makeGroups(from: assets)
        let assetLookup = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var analyzer = BurstReviewAnalyzer(rootURL: configuration.rootURL)

        var splitCandidates: [BurstReviewCandidate] = []
        var mergeCandidates: [BurstReviewCandidate] = []

        for (sceneIndex, group) in sceneGroups.enumerated() {
            let bursts = sceneBursts(for: group, assetLookup: assetLookup)

            for (burstIndex, burst) in bursts.enumerated() where burst.assets.count > 1 {
                let metrics = analyzer.metrics(for: burst.assets)
                let score = splitScore(for: burst, metrics: metrics)
                guard score > 0 else { continue }

                splitCandidates.append(
                    BurstReviewCandidate(
                        id: "S-\(sceneIndex + 1)-\(burstIndex + 1)",
                        kind: .split,
                        score: score,
                        sceneIndex: sceneIndex + 1,
                        sceneName: group.name,
                        burstIndices: [burstIndex + 1],
                        summary: "疑似误并：组内距离或跨度接近阈值",
                        metrics: metrics,
                        leftBurst: burst,
                        rightBurst: nil
                    )
                )
            }

            for index in 0..<max(0, bursts.count - 1) {
                let left = bursts[index]
                let right = bursts[index + 1]
                let metrics = analyzer.adjacencyMetrics(left: left.assets, right: right.assets)
                let score = mergeScore(left: left, right: right, metrics: metrics)
                guard score > 0 else { continue }

                mergeCandidates.append(
                    BurstReviewCandidate(
                        id: "M-\(sceneIndex + 1)-\(index + 1)",
                        kind: .merge,
                        score: score,
                        sceneIndex: sceneIndex + 1,
                        sceneName: group.name,
                        burstIndices: [index + 1, index + 2],
                        summary: "疑似漏并：相邻连拍组时间近且视觉距离接近阈值",
                        metrics: metrics,
                        leftBurst: left,
                        rightBurst: right
                    )
                )
            }
        }

        let selectedSplitCandidates = Array(splitCandidates.sorted(by: sortCandidates).prefix(configuration.splitLimit))
        let selectedMergeCandidates = Array(mergeCandidates.sorted(by: sortCandidates).prefix(configuration.mergeLimit))

        let report = BurstReviewReport(
            generatedAt: .now,
            rootPath: configuration.rootURL.path,
            assetCount: assets.count,
            sceneCount: sceneGroups.count,
            burstCount: sceneGroups.reduce(0) { partialResult, group in
                partialResult + sceneBursts(for: group, assetLookup: assetLookup).count
            },
            multiAssetBurstCount: sceneGroups.reduce(0) { partialResult, group in
                partialResult + sceneBursts(for: group, assetLookup: assetLookup).filter { $0.assets.count > 1 }.count
            },
            splitCandidates: selectedSplitCandidates.map(makeReviewEntry),
            mergeCandidates: selectedMergeCandidates.map(makeReviewEntry)
        )

        try write(report: report)
    }

    private func sortCandidates(lhs: BurstReviewCandidate, rhs: BurstReviewCandidate) -> Bool {
        if lhs.score == rhs.score {
            return lhs.id < rhs.id
        }
        return lhs.score > rhs.score
    }

    private func makeAsset(from item: DiscoveredItem) -> MediaAsset {
        MediaAsset(
            id: item.id,
            importResumeKey: item.resumeKey,
            baseName: item.baseName,
            source: item.source,
            previewURL: item.previewFile,
            rawURL: item.rawFile,
            livePhotoVideoURL: item.auxiliaryFile,
            depthData: item.depthData,
            thumbnailURL: nil,
            metadata: item.metadata,
            mediaType: item.mediaType,
            importState: .complete,
            aiScore: nil,
            editSuggestions: nil,
            userDecision: .pending,
            userRating: nil,
            issues: []
        )
    }

    private func sceneBursts(for group: PhotoGroup, assetLookup: [UUID: MediaAsset]) -> [BurstReviewBurst] {
        let sourceSubGroups: [SubGroup]
        if group.subGroups.isEmpty {
            sourceSubGroups = group.assets.map { assetID in
                SubGroup(id: assetID, assets: [assetID], bestAsset: nil)
            }
        } else {
            sourceSubGroups = group.subGroups
        }

        return sourceSubGroups.compactMap { subGroup in
            let assets = subGroup.assets.compactMap { assetLookup[$0] }.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
            guard !assets.isEmpty else { return nil }
            return BurstReviewBurst(id: subGroup.id, assets: assets, bestAssetID: subGroup.bestAsset)
        }
    }

    private func splitScore(for burst: BurstReviewBurst, metrics: BurstReviewMetrics) -> Double {
        guard burst.assets.count > 1 else { return 0 }
        if burst.assets.count == 2,
           metrics.spanSeconds <= burstPolicy.frameGapThreshold,
           let completeDistance = metrics.completeDistanceMax,
           completeDistance <= burstPolicy.completeDistanceThreshold {
            return 0
        }
        let nearCompleteBoundary = (metrics.completeDistanceMax ?? 0) >= burstPolicy.completeDistanceThreshold - 0.08
        let nearAnchorBoundary = (metrics.anchorDistanceMax ?? 0) >= burstPolicy.anchorDistanceThreshold - 0.06
        let nearSpanBoundary = metrics.spanSeconds >= burstPolicy.burstSpanThreshold * 0.75
        guard nearCompleteBoundary || nearAnchorBoundary || nearSpanBoundary else {
            return 0
        }

        var score = 0.0
        if let completeDistance = metrics.completeDistanceMax {
            score += normalized(completeDistance, threshold: burstPolicy.completeDistanceThreshold, margin: 0.08) * 0.6
        }
        if let anchorDistance = metrics.anchorDistanceMax {
            score += normalized(anchorDistance, threshold: burstPolicy.anchorDistanceThreshold, margin: 0.06) * 0.25
        }
        if nearSpanBoundary {
            score += min(metrics.spanSeconds / burstPolicy.burstSpanThreshold, 1.25) * 0.15
        }

        return score >= 0.15 ? score : 0
    }

    private func mergeScore(left: BurstReviewBurst, right: BurstReviewBurst, metrics: BurstReviewMetrics) -> Double {
        guard left.assets.count == 1 || right.assets.count == 1 else { return 0 }
        guard metrics.gapSeconds <= burstPolicy.frameGapThreshold else { return 0 }
        guard let minDistance = metrics.interBurstMinDistance else { return 0 }
        guard minDistance <= burstPolicy.completeDistanceThreshold + 0.03 else { return 0 }

        var score = 0.0
        score += normalized(minDistance, threshold: burstPolicy.completeDistanceThreshold, margin: 0.03) * 0.75
        score += max(0, 1 - (metrics.gapSeconds / burstPolicy.frameGapThreshold)) * 0.25

        return score
    }

    private func normalized(_ value: Float, threshold: Float, margin: Float) -> Double {
        let floor = threshold - margin
        guard value >= floor else { return 0 }
        let ratio = (value - floor) / max(margin, 0.001)
        return Double(min(max(ratio, 0), 1))
    }

    private func makeReviewEntry(from candidate: BurstReviewCandidate) -> BurstReviewEntry {
        BurstReviewEntry(
            id: candidate.id,
            kind: candidate.kind.rawValue,
            sceneIndex: candidate.sceneIndex,
            sceneName: candidate.sceneName,
            burstIndices: candidate.burstIndices,
            summary: candidate.summary,
            score: candidate.score,
            metrics: candidate.metrics,
            bursts: [candidate.leftBurst, candidate.rightBurst].compactMap { burst in
                burst.map { makeBurstEntry(from: $0) }
            }
        )
    }

    private func makeBurstEntry(from burst: BurstReviewBurst) -> BurstReviewBurstEntry {
        BurstReviewBurstEntry(
            bestAssetBaseName: burst.assets.first(where: { $0.id == burst.bestAssetID })?.baseName,
            assets: burst.assets.map { asset in
                BurstReviewAssetEntry(
                    baseName: asset.baseName,
                    relativePath: relativePath(for: asset),
                    captureDate: asset.metadata.captureDate,
                    focalLength: asset.metadata.focalLength
                )
            }
        )
    }

    private func relativePath(for asset: MediaAsset) -> String {
        let sourceURL = asset.previewURL ?? asset.rawURL ?? asset.livePhotoVideoURL
        guard let sourceURL else { return asset.baseName }
        let rootPath = configuration.rootURL.path
        let fullPath = sourceURL.path
        guard fullPath.hasPrefix(rootPath) else { return fullPath }
        let relative = String(fullPath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? sourceURL.lastPathComponent : relative
    }

    private func write(report: BurstReviewReport) throws {
        try FileManager.default.createDirectory(
            at: configuration.markdownURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: configuration.jsonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let markdown = BurstReviewMarkdownRenderer.render(report)
        try markdown.write(to: configuration.markdownURL, atomically: true, encoding: .utf8)

        let jsonData = try JSONEncoder.lumaEncoder.encode(report)
        try jsonData.write(to: configuration.jsonURL, options: .atomic)
    }
}

private struct BurstReviewAnalyzer {
    let rootURL: URL

    private var featurePrints: [UUID: VNFeaturePrintObservation] = [:]

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    mutating func metrics(for assets: [MediaAsset]) -> BurstReviewMetrics {
        let sortedAssets = assets.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        guard let first = sortedAssets.first,
              let last = sortedAssets.last else {
            return BurstReviewMetrics()
        }

        var anchorDistanceMax: Float?
        var completeDistanceMax: Float?

        for asset in sortedAssets.dropFirst() {
            if let distance = distance(between: first, and: asset) {
                anchorDistanceMax = max(anchorDistanceMax ?? distance, distance)
            }
        }

        for lhsIndex in sortedAssets.indices {
            for rhsIndex in sortedAssets.indices where rhsIndex > lhsIndex {
                guard let distance = distance(between: sortedAssets[lhsIndex], and: sortedAssets[rhsIndex]) else { continue }
                completeDistanceMax = max(completeDistanceMax ?? distance, distance)
            }
        }

        return BurstReviewMetrics(
            gapSeconds: 0,
            spanSeconds: last.metadata.captureDate.timeIntervalSince(first.metadata.captureDate),
            anchorDistanceMax: anchorDistanceMax,
            completeDistanceMax: completeDistanceMax,
            interBurstMinDistance: nil
        )
    }

    mutating func adjacencyMetrics(left: [MediaAsset], right: [MediaAsset]) -> BurstReviewMetrics {
        let leftSorted = left.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        let rightSorted = right.sorted { $0.metadata.captureDate < $1.metadata.captureDate }
        let gap = max(0, (rightSorted.first?.metadata.captureDate ?? .distantFuture).timeIntervalSince(leftSorted.last?.metadata.captureDate ?? .distantPast))

        var minDistance: Float?
        for lhs in leftSorted {
            for rhs in rightSorted {
                guard let distance = distance(between: lhs, and: rhs) else { continue }
                minDistance = min(minDistance ?? distance, distance)
            }
        }

        return BurstReviewMetrics(
            gapSeconds: gap,
            spanSeconds: 0,
            anchorDistanceMax: nil,
            completeDistanceMax: nil,
            interBurstMinDistance: minDistance
        )
    }

    private mutating func distance(between lhs: MediaAsset, and rhs: MediaAsset) -> Float? {
        guard let lhsObservation = featurePrint(for: lhs),
              let rhsObservation = featurePrint(for: rhs) else {
            return nil
        }

        var distance: Float = .greatestFiniteMagnitude
        do {
            try lhsObservation.computeDistance(&distance, to: rhsObservation)
            return distance
        } catch {
            return nil
        }
    }

    private mutating func featurePrint(for asset: MediaAsset) -> VNFeaturePrintObservation? {
        if let cached = featurePrints[asset.id] {
            return cached
        }
        guard let sourceURL = [asset.previewURL, asset.thumbnailURL, asset.rawURL].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let cgImage = EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 512) else {
            return nil
        }

        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                return nil
            }
            featurePrints[asset.id] = observation
            return observation
        } catch {
            return nil
        }
    }
}

private struct BurstReviewReport: Encodable {
    let generatedAt: Date
    let rootPath: String
    let assetCount: Int
    let sceneCount: Int
    let burstCount: Int
    let multiAssetBurstCount: Int
    let splitCandidates: [BurstReviewEntry]
    let mergeCandidates: [BurstReviewEntry]
}

private struct BurstReviewEntry: Encodable {
    let id: String
    let kind: String
    let sceneIndex: Int
    let sceneName: String
    let burstIndices: [Int]
    let summary: String
    let score: Double
    let metrics: BurstReviewMetrics
    let bursts: [BurstReviewBurstEntry]
}

private struct BurstReviewBurstEntry: Encodable {
    let bestAssetBaseName: String?
    let assets: [BurstReviewAssetEntry]
}

private struct BurstReviewAssetEntry: Encodable {
    let baseName: String
    let relativePath: String
    let captureDate: Date
    let focalLength: Double?
}

private struct BurstReviewMetrics: Encodable {
    var gapSeconds: TimeInterval = 0
    var spanSeconds: TimeInterval = 0
    var anchorDistanceMax: Float?
    var completeDistanceMax: Float?
    var interBurstMinDistance: Float?
}

private struct BurstReviewCandidate {
    enum Kind: String {
        case split
        case merge
    }

    let id: String
    let kind: Kind
    let score: Double
    let sceneIndex: Int
    let sceneName: String
    let burstIndices: [Int]
    let summary: String
    let metrics: BurstReviewMetrics
    let leftBurst: BurstReviewBurst
    let rightBurst: BurstReviewBurst?
}

private struct BurstReviewBurst {
    let id: UUID
    let assets: [MediaAsset]
    let bestAssetID: UUID?
}

private struct BurstReviewMarkdownRenderer {
    static func render(_ report: BurstReviewReport) -> String {
        let dateFormatter = ISO8601DateFormatter()
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "zh_Hans")
        timeFormatter.timeZone = TimeZone.current
        timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var lines: [String] = []
        lines.append("# Burst Review Pack")
        lines.append("")
        lines.append("- Generated: \(dateFormatter.string(from: report.generatedAt))")
        lines.append("- Root: `\(report.rootPath)`")
        lines.append("- Assets: \(report.assetCount)")
        lines.append("- Scene groups: \(report.sceneCount)")
        lines.append("- Burst groups: \(report.burstCount)")
        lines.append("- Multi-asset bursts: \(report.multiAssetBurstCount)")
        lines.append("")
        lines.append("## 疑似误并")
        lines.append("")
        if report.splitCandidates.isEmpty {
            lines.append("无")
        } else {
            append(entries: report.splitCandidates, to: &lines, timeFormatter: timeFormatter)
        }
        lines.append("")
        lines.append("## 疑似漏并")
        lines.append("")
        if report.mergeCandidates.isEmpty {
            lines.append("无")
        } else {
            append(entries: report.mergeCandidates, to: &lines, timeFormatter: timeFormatter)
        }

        return lines.joined(separator: "\n")
    }

    private static func append(entries: [BurstReviewEntry], to lines: inout [String], timeFormatter: DateFormatter) {
        for entry in entries {
            lines.append("### \(entry.id) · \(entry.sceneName)")
            lines.append("")
            lines.append("- Scene: \(entry.sceneIndex)")
            lines.append("- Burst: \(entry.burstIndices.map(String.init).joined(separator: ", "))")
            lines.append("- Summary: \(entry.summary)")
            lines.append(String(format: "- Score: %.3f", entry.score))
            if entry.metrics.gapSeconds > 0 {
                lines.append(String(format: "- Gap: %.1fs", entry.metrics.gapSeconds))
            }
            if entry.metrics.spanSeconds > 0 {
                lines.append(String(format: "- Span: %.1fs", entry.metrics.spanSeconds))
            }
            if let anchorDistanceMax = entry.metrics.anchorDistanceMax {
                lines.append(String(format: "- Anchor max: %.3f", anchorDistanceMax))
            }
            if let completeDistanceMax = entry.metrics.completeDistanceMax {
                lines.append(String(format: "- Complete max: %.3f", completeDistanceMax))
            }
            if let interBurstMinDistance = entry.metrics.interBurstMinDistance {
                lines.append(String(format: "- Inter-burst min: %.3f", interBurstMinDistance))
            }
            lines.append("")

            for (burstIndex, burst) in entry.bursts.enumerated() {
                let title = entry.kind == "merge" ? "Burst \(entry.burstIndices[burstIndex])" : "Burst"
                lines.append("#### \(title)")
                lines.append("")
                if let bestAssetBaseName = burst.bestAssetBaseName {
                    lines.append("- Best: `\(bestAssetBaseName)`")
                }
                for asset in burst.assets {
                    let timestamp = timeFormatter.string(from: asset.captureDate)
                    let focalLength = asset.focalLength.map { String(format: "%.0fmm", $0) } ?? "-"
                    lines.append("- `\(asset.relativePath)` · \(timestamp) · \(focalLength)")
                }
                lines.append("")
            }
        }
    }
}

private struct NullLocationNamingProvider: GroupLocationNamingProvider, Sendable {
    func name(for coordinate: Coordinate) async -> String? {
        nil
    }
}

private struct SilentVisualSubgroupingProvider: VisualSubgroupingProvider, Sendable {
    func continuityDistance(between lhs: [MediaAsset], and rhs: [MediaAsset]) async -> Float? {
        nil
    }

    func subgroupAssets(in assets: [MediaAsset]) async -> [[MediaAsset]] {
        let provider = VisionVisualSubgroupingProvider()
        return await provider.subgroupAssets(in: assets)
    }
}
