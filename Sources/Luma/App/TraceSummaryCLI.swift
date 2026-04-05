import Foundation

struct TraceSummaryCLI {
    struct Configuration {
        let traceURL: URL
        let markdownURL: URL
        let jsonURL: URL
        let topLimit: Int
    }

    static func requestedConfiguration(from arguments: [String]) -> Configuration? {
        let wantsSummary =
            arguments.contains("--trace-summary") ||
            arguments.contains("--trace-summary-file") ||
            arguments.contains(where: { $0.hasPrefix("--trace-summary-file=") })
        guard wantsSummary else { return nil }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        guard let traceURL = resolvedTraceURL(from: arguments, cwd: cwd) else {
            return nil
        }

        let markdownURL = resolvedOutputURL(
            from: value(for: "--trace-summary-output", in: arguments),
            defaultPath: "Artifacts/trace-summary-latest.md",
            cwd: cwd
        )
        let jsonURL = resolvedOutputURL(
            from: value(for: "--trace-summary-json", in: arguments),
            defaultPath: "Artifacts/trace-summary-latest.json",
            cwd: cwd
        )

        return Configuration(
            traceURL: traceURL,
            markdownURL: markdownURL,
            jsonURL: jsonURL,
            topLimit: Int(value(for: "--trace-summary-top", in: arguments) ?? "") ?? 10
        )
    }

    static func run(_ configuration: Configuration) throws {
        try TraceSummaryExporter(configuration: configuration).export()
    }

    private static func resolvedTraceURL(from arguments: [String], cwd: URL) -> URL? {
        if let rawPath = value(for: "--trace-summary-file", in: arguments) {
            return resolvedURL(from: rawPath, cwd: cwd)
        }
        return try? AppDirectories.runtimeTraceLatestURL()
    }

    private static func value(for flag: String, in arguments: [String]) -> String? {
        if let inline = arguments.first(where: { $0.hasPrefix("\(flag)=") }) {
            return String(inline.dropFirst(flag.count + 1))
        }

        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func resolvedOutputURL(from rawValue: String?, defaultPath: String, cwd: URL) -> URL {
        resolvedURL(from: rawValue ?? defaultPath, cwd: cwd)
    }

    private static func resolvedURL(from rawPath: String, cwd: URL) -> URL {
        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath)
        }
        return cwd.appendingPathComponent(rawPath)
    }
}

private struct TraceSummaryExporter {
    let configuration: TraceSummaryCLI.Configuration

    private let monitoredMetricDefinitions: [TraceMonitoredMetricDefinition] = [
        .init(category: "interaction", name: "group_selected", budgetMs: 16),
        .init(category: "interaction", name: "display_mode_changed", budgetMs: 16),
        .init(category: "interaction", name: "asset_selected", budgetMs: 8),
        .init(category: "state", name: "derived_state_rebuilt", budgetMs: 8),
        .init(category: "viewer", name: "single_image_first_paint", budgetMs: 40),
        .init(category: "viewer", name: "single_image_loaded", budgetMs: 80),
        .init(category: "project", name: "project_opened", budgetMs: 120),
        .init(category: "app", name: "bootstrap_completed", budgetMs: 80),
        .init(category: "import", name: "initial_manifest_built", budgetMs: 1000),
        .init(category: "import", name: "import_grouping_completed", budgetMs: 1000),
    ]

    private let triggerDefinitions: [TraceTriggerDefinition] = [
        .init(category: "interaction", name: "group_selected", budgetMs: 120, windowSeconds: 2.0),
        .init(category: "interaction", name: "display_mode_changed", budgetMs: 120, windowSeconds: 2.0),
        .init(category: "project", name: "project_opened", budgetMs: 300, windowSeconds: 3.0),
        .init(category: "app", name: "bootstrap_completed", budgetMs: 150, windowSeconds: 2.0),
    ]

    func export() throws {
        let traceData = try Data(contentsOf: configuration.traceURL)
        let analysis = analyze(traceData)
        let report = makeReport(from: analysis)
        try write(report: report)
    }

    private func analyze(_ data: Data) -> TraceAnalysis {
        let decoder = JSONDecoder.lumaDecoder
        let contents = String(decoding: data, as: UTF8.self)
        let lines = contents.split(whereSeparator: \.isNewline)

        var records: [TraceSummaryRecord] = []
        var parseFailures = 0

        for line in lines where !line.isEmpty {
            do {
                let record = try decoder.decode(TraceSummaryRecord.self, from: Data(line.utf8))
                records.append(record)
            } catch {
                parseFailures += 1
            }
        }

        return TraceAnalysis(records: records, parseFailures: parseFailures)
    }

    private func makeReport(from analysis: TraceAnalysis) -> TraceSummaryReport {
        let records = analysis.records.sorted {
            if $0.timestamp == $1.timestamp {
                return ($0.sequence ?? 0) < ($1.sequence ?? 0)
            }
            return $0.timestamp < $1.timestamp
        }

        let sessionID = records.last?.sessionID
        let levelCounts = counts(for: records.map(\.level))
        let categoryCounts = counts(for: records.map(\.category))
        let topEvents = eventCounts(for: records)
            .sorted {
                if $0.count == $1.count { return ($0.category, $0.name, $0.level) < ($1.category, $1.name, $1.level) }
                return $0.count > $1.count
            }
            .prefix(configuration.topLimit)
            .map { $0 }

        let metricSummaries = durationSummaries(for: records)
            .sorted {
                if $0.maxDurationMs == $1.maxDurationMs { return ($0.category, $0.name) < ($1.category, $1.name) }
                return $0.maxDurationMs > $1.maxDurationMs
            }
            .prefix(configuration.topLimit)
            .map { $0 }

        let allMetricSummaries = durationSummaries(for: records)
        let monitoredHotspots = hotspotSummaries(for: records, metricSummaries: allMetricSummaries)
            .sorted {
                if $0.breachCount == $1.breachCount {
                    if $0.maxDurationMs == $1.maxDurationMs { return ($0.category, $0.name) < ($1.category, $1.name) }
                    return $0.maxDurationMs > $1.maxDurationMs
                }
                return $0.breachCount > $1.breachCount
            }
            .prefix(configuration.topLimit)
            .map { $0 }

        let triggerChains = interactionChains(for: records)
            .sorted {
                if $0.totalDurationMs == $1.totalDurationMs { return ($0.sequence ?? 0) > ($1.sequence ?? 0) }
                return $0.totalDurationMs > $1.totalDurationMs
            }
            .prefix(configuration.topLimit)
            .map { $0 }

        let slowSamples = records.compactMap { record -> TraceSlowSample? in
            guard let durationMs = record.durationMs else { return nil }
            return TraceSlowSample(
                sequence: record.sequence,
                timestamp: record.timestamp,
                category: record.category,
                name: record.name,
                durationMs: durationMs,
                summary: summary(for: record.metadata)
            )
        }
        .sorted {
            if $0.durationMs == $1.durationMs { return ($0.sequence ?? 0) > ($1.sequence ?? 0) }
            return $0.durationMs > $1.durationMs
        }
        .prefix(configuration.topLimit)
        .map { $0 }

        let errors = records
            .filter { $0.level == "error" }
            .sorted {
                if $0.timestamp == $1.timestamp {
                    return ($0.sequence ?? 0) > ($1.sequence ?? 0)
                }
                return $0.timestamp > $1.timestamp
            }
            .prefix(configuration.topLimit)
            .map { record in
                TraceErrorEntry(
                    sequence: record.sequence,
                    timestamp: record.timestamp,
                    category: record.category,
                    name: record.name,
                    message: record.metadata["message"] ?? summary(for: record.metadata)
                )
            }

        return TraceSummaryReport(
            generatedAt: .now,
            tracePath: configuration.traceURL.path,
            sessionID: sessionID,
            recordCount: records.count,
            parseFailureCount: analysis.parseFailures,
            firstTimestamp: records.first?.timestamp,
            lastTimestamp: records.last?.timestamp,
            levelCounts: levelCounts,
            categoryCounts: categoryCounts,
            topEvents: topEvents,
            metricSummaries: metricSummaries,
            monitoredHotspots: monitoredHotspots,
            triggerChains: triggerChains,
            slowSamples: slowSamples,
            recentErrors: errors
        )
    }

    private func counts(for values: [String]) -> [TraceCount] {
        Dictionary(values.map { ($0, 1) }, uniquingKeysWith: +)
            .map { TraceCount(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
    }

    private func eventCounts(for records: [TraceSummaryRecord]) -> [TraceEventCount] {
        var counts: [TraceEventKey: Int] = [:]
        for record in records {
            counts[TraceEventKey(level: record.level, category: record.category, name: record.name), default: 0] += 1
        }
        return counts.map {
            TraceEventCount(level: $0.key.level, category: $0.key.category, name: $0.key.name, count: $0.value)
        }
    }

    private func durationSummaries(for records: [TraceSummaryRecord]) -> [TraceMetricSummary] {
        var durationsByKey: [TraceMetricKey: [Double]] = [:]
        for record in records {
            guard let durationMs = record.durationMs else { continue }
            durationsByKey[TraceMetricKey(category: record.category, name: record.name), default: []].append(durationMs)
        }

        return durationsByKey.map { key, durations in
            let sortedDurations = durations.sorted()
            let count = sortedDurations.count
            let average = sortedDurations.reduce(0, +) / Double(max(count, 1))
            return TraceMetricSummary(
                category: key.category,
                name: key.name,
                count: count,
                averageDurationMs: average,
                p50DurationMs: percentile(0.5, in: sortedDurations),
                p95DurationMs: percentile(0.95, in: sortedDurations),
                maxDurationMs: sortedDurations.last ?? 0
            )
        }
    }

    private func hotspotSummaries(
        for records: [TraceSummaryRecord],
        metricSummaries: [TraceMetricSummary]
    ) -> [TraceHotspotSummary] {
        let summaryLookup = Dictionary(
            uniqueKeysWithValues: metricSummaries.map { (TraceMetricKey(category: $0.category, name: $0.name), $0) }
        )

        return monitoredMetricDefinitions.compactMap { definition in
            let key = TraceMetricKey(category: definition.category, name: definition.name)
            guard let summary = summaryLookup[key] else { return nil }
            let breachCount = records.filter { record in
                record.category == definition.category &&
                record.name == definition.name &&
                (record.durationMs ?? 0) > definition.budgetMs
            }.count

            return TraceHotspotSummary(
                category: definition.category,
                name: definition.name,
                budgetMs: definition.budgetMs,
                count: summary.count,
                breachCount: breachCount,
                averageDurationMs: summary.averageDurationMs,
                p95DurationMs: summary.p95DurationMs,
                maxDurationMs: summary.maxDurationMs
            )
        }
    }

    private func interactionChains(for records: [TraceSummaryRecord]) -> [TraceTriggerChain] {
        let indexedRecords = Array(records.enumerated())
        let triggerLookup = Dictionary(
            uniqueKeysWithValues: triggerDefinitions.map { (TraceMetricKey(category: $0.category, name: $0.name), $0) }
        )
        let triggerIndices = indexedRecords.compactMap { index, record -> Int? in
            triggerLookup[TraceMetricKey(category: record.category, name: record.name)] == nil ? nil : index
        }

        return triggerIndices.compactMap { triggerIndex in
            let triggerRecord = records[triggerIndex]
            guard let trigger = triggerLookup[TraceMetricKey(category: triggerRecord.category, name: triggerRecord.name)] else {
                return nil
            }

            let nextTriggerIndex = triggerIndices.first(where: { $0 > triggerIndex }) ?? records.count
            let windowEnd = triggerRecord.timestamp.addingTimeInterval(trigger.windowSeconds)

            let chainRecords = records[triggerIndex..<nextTriggerIndex].filter { record in
                record.timestamp <= windowEnd && record.durationMs != nil
            }
            guard !chainRecords.isEmpty else { return nil }

            let totalDurationMs = chainRecords.reduce(0) { $0 + ($1.durationMs ?? 0) }
            let maxDurationMs = chainRecords.compactMap(\.durationMs).max() ?? 0
            let stageSummaries = chainRecords.prefix(5).compactMap { record -> String? in
                guard let durationMs = record.durationMs else { return nil }
                return String(format: "%@/%@ %.2fms", record.category, record.name, durationMs)
            }

            return TraceTriggerChain(
                sequence: triggerRecord.sequence,
                timestamp: triggerRecord.timestamp,
                category: trigger.category,
                name: trigger.name,
                budgetMs: trigger.budgetMs,
                totalDurationMs: totalDurationMs,
                maxStageDurationMs: maxDurationMs,
                stageCount: chainRecords.count,
                overBudget: totalDurationMs > trigger.budgetMs,
                summary: summary(for: triggerRecord.metadata),
                stages: stageSummaries
            )
        }
    }

    private func percentile(_ percentile: Double, in sortedDurations: [Double]) -> Double {
        guard !sortedDurations.isEmpty else { return 0 }
        let rank = Int((Double(sortedDurations.count - 1) * percentile).rounded(.toNearestOrAwayFromZero))
        return sortedDurations[min(max(rank, 0), sortedDurations.count - 1)]
    }

    private func summary(for metadata: [String: String]) -> String? {
        let preferredKeys = [
            "message",
            "project_name",
            "phase",
            "group_id",
            "selected_group_id",
            "asset_id",
            "selected_asset_id",
            "source_name"
        ]

        let parts = preferredKeys.compactMap { key -> String? in
            guard let value = metadata[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    private func write(report: TraceSummaryReport) throws {
        try FileManager.default.createDirectory(
            at: configuration.markdownURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: configuration.jsonURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let markdown = TraceSummaryMarkdownRenderer.render(report)
        try markdown.write(to: configuration.markdownURL, atomically: true, encoding: .utf8)

        let jsonData = try JSONEncoder.lumaEncoder.encode(report)
        try jsonData.write(to: configuration.jsonURL, options: .atomic)
    }
}

private struct TraceAnalysis {
    let records: [TraceSummaryRecord]
    let parseFailures: Int
}

private struct TraceSummaryRecord: Decodable {
    let sequence: Int?
    let timestamp: Date
    let sessionID: String
    let level: String
    let category: String
    let name: String
    let metadata: [String: String]

    var durationMs: Double? {
        guard let rawValue = metadata["duration_ms"] else { return nil }
        return Double(rawValue)
    }
}

private struct TraceSummaryReport: Encodable {
    let generatedAt: Date
    let tracePath: String
    let sessionID: String?
    let recordCount: Int
    let parseFailureCount: Int
    let firstTimestamp: Date?
    let lastTimestamp: Date?
    let levelCounts: [TraceCount]
    let categoryCounts: [TraceCount]
    let topEvents: [TraceEventCount]
    let metricSummaries: [TraceMetricSummary]
    let monitoredHotspots: [TraceHotspotSummary]
    let triggerChains: [TraceTriggerChain]
    let slowSamples: [TraceSlowSample]
    let recentErrors: [TraceErrorEntry]
}

private struct TraceCount: Encodable {
    let name: String
    let count: Int
}

private struct TraceEventCount: Encodable {
    let level: String
    let category: String
    let name: String
    let count: Int
}

private struct TraceMetricSummary: Encodable {
    let category: String
    let name: String
    let count: Int
    let averageDurationMs: Double
    let p50DurationMs: Double
    let p95DurationMs: Double
    let maxDurationMs: Double
}

private struct TraceHotspotSummary: Encodable {
    let category: String
    let name: String
    let budgetMs: Double
    let count: Int
    let breachCount: Int
    let averageDurationMs: Double
    let p95DurationMs: Double
    let maxDurationMs: Double
}

private struct TraceTriggerChain: Encodable {
    let sequence: Int?
    let timestamp: Date
    let category: String
    let name: String
    let budgetMs: Double
    let totalDurationMs: Double
    let maxStageDurationMs: Double
    let stageCount: Int
    let overBudget: Bool
    let summary: String?
    let stages: [String]
}

private struct TraceSlowSample: Encodable {
    let sequence: Int?
    let timestamp: Date
    let category: String
    let name: String
    let durationMs: Double
    let summary: String?
}

private struct TraceErrorEntry: Encodable {
    let sequence: Int?
    let timestamp: Date
    let category: String
    let name: String
    let message: String?
}

private struct TraceEventKey: Hashable {
    let level: String
    let category: String
    let name: String
}

private struct TraceMetricKey: Hashable {
    let category: String
    let name: String
}

private struct TraceMonitoredMetricDefinition {
    let category: String
    let name: String
    let budgetMs: Double
}

private struct TraceTriggerDefinition {
    let category: String
    let name: String
    let budgetMs: Double
    let windowSeconds: TimeInterval
}

private enum TraceSummaryMarkdownRenderer {
    static func render(_ report: TraceSummaryReport) -> String {
        let timestampFormatter = ISO8601DateFormatter()

        var lines: [String] = []
        lines.append("# Trace Summary")
        lines.append("")
        lines.append("- Generated: \(timestampFormatter.string(from: report.generatedAt))")
        lines.append("- Trace: `\(report.tracePath)`")
        if let sessionID = report.sessionID {
            lines.append("- Session: `\(sessionID)`")
        }
        lines.append("- Records: \(report.recordCount)")
        lines.append("- Parse failures: \(report.parseFailureCount)")
        if let firstTimestamp = report.firstTimestamp, let lastTimestamp = report.lastTimestamp {
            lines.append("- Time range: \(timestampFormatter.string(from: firstTimestamp)) -> \(timestampFormatter.string(from: lastTimestamp))")
        }

        lines.append("")
        lines.append("## Levels")
        lines.append("")
        appendCounts(report.levelCounts, to: &lines)

        lines.append("")
        lines.append("## Categories")
        lines.append("")
        appendCounts(report.categoryCounts, to: &lines)

        lines.append("")
        lines.append("## Top Events")
        lines.append("")
        if report.topEvents.isEmpty {
            lines.append("无")
        } else {
            for event in report.topEvents {
                lines.append("- \(event.count)x · `\(event.level)` · `\(event.category)` · `\(event.name)`")
            }
        }

        lines.append("")
        lines.append("## Slow Metrics")
        lines.append("")
        if report.metricSummaries.isEmpty {
            lines.append("无")
        } else {
            for metric in report.metricSummaries {
                lines.append(
                    String(
                        format: "- `%@/%@` · count=%d · avg=%.2fms · p50=%.2fms · p95=%.2fms · max=%.2fms",
                        metric.category,
                        metric.name,
                        metric.count,
                        metric.averageDurationMs,
                        metric.p50DurationMs,
                        metric.p95DurationMs,
                        metric.maxDurationMs
                    )
                )
            }
        }

        lines.append("")
        lines.append("## Hotspot Budgets")
        lines.append("")
        if report.monitoredHotspots.isEmpty {
            lines.append("无")
        } else {
            for hotspot in report.monitoredHotspots {
                let marker = hotspot.breachCount > 0 ? " breach" : " ok"
                lines.append(
                    String(
                        format: "- `%@/%@` · budget=%.0fms · count=%d · breaches=%d · p95=%.2fms · max=%.2fms ·%@",
                        hotspot.category,
                        hotspot.name,
                        hotspot.budgetMs,
                        hotspot.count,
                        hotspot.breachCount,
                        hotspot.p95DurationMs,
                        hotspot.maxDurationMs,
                        marker
                    )
                )
            }
        }

        lines.append("")
        lines.append("## Slow Chains")
        lines.append("")
        if report.triggerChains.isEmpty {
            lines.append("无")
        } else {
            for chain in report.triggerChains {
                let sequence = chain.sequence.map(String.init) ?? "-"
                let overBudgetSuffix = chain.overBudget ? " · over-budget" : ""
                let summarySuffix = chain.summary.map { " · \($0)" } ?? ""
                lines.append(
                    String(
                        format: "- #%@ · `%@/%@` · total=%.2fms · budget=%.0fms · max-stage=%.2fms · stages=%d%@%@",
                        sequence,
                        chain.category,
                        chain.name,
                        chain.totalDurationMs,
                        chain.budgetMs,
                        chain.maxStageDurationMs,
                        chain.stageCount,
                        overBudgetSuffix,
                        summarySuffix
                    )
                )
                for stage in chain.stages {
                    lines.append("  - \(stage)")
                }
            }
        }

        lines.append("")
        lines.append("## Slow Samples")
        lines.append("")
        if report.slowSamples.isEmpty {
            lines.append("无")
        } else {
            for sample in report.slowSamples {
                let summarySuffix = sample.summary.map { " · \($0)" } ?? ""
                let sequence = sample.sequence.map(String.init) ?? "-"
                lines.append(
                    String(
                        format: "- #%@ · `%@/%@` · %.2fms%@",
                        sequence,
                        sample.category,
                        sample.name,
                        sample.durationMs,
                        summarySuffix
                    )
                )
            }
        }

        lines.append("")
        lines.append("## Recent Errors")
        lines.append("")
        if report.recentErrors.isEmpty {
            lines.append("无")
        } else {
            for error in report.recentErrors {
                let sequence = error.sequence.map(String.init) ?? "-"
                let message = error.message ?? "-"
                lines.append("- #\(sequence) · `\(error.category)/\(error.name)` · \(message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func appendCounts(_ counts: [TraceCount], to lines: inout [String]) {
        if counts.isEmpty {
            lines.append("无")
            return
        }

        for count in counts {
            lines.append("- `\(count.name)` · \(count.count)")
        }
    }
}
