import Foundation

protocol BatchScheduling: Sendable {
    func scoreGroups(
        _ groups: [PhotoGroup],
        assetsByID: [UUID: MediaAsset],
        provider: any VisionModelProvider,
        modelConfig: ModelConfig,
        progress: @escaping @Sendable (BatchProgress) -> Void
    ) async throws -> BatchSchedulerResult

    func analyzeDetails(
        assetIDs: [UUID],
        assetsByID: [UUID: MediaAsset],
        groupsByID: [UUID: PhotoGroup],
        provider: any VisionModelProvider,
        modelConfig: ModelConfig
    ) async throws -> ([UUID: EditSuggestions], [CostRecord])
}

struct BatchProgress: Sendable {
    let completedGroups: Int
    let totalGroups: Int
    let currentGroupName: String
}

struct BatchSchedulerResult {
    let scoresByAssetID: [UUID: AIScore]
    let groupCommentsByID: [UUID: String]
    let recommendedByGroupID: [UUID: [UUID]]
    let costRecords: [CostRecord]
}

struct BatchScheduler: BatchScheduling {
    func scoreGroups(
        _ groups: [PhotoGroup],
        assetsByID: [UUID: MediaAsset],
        provider: any VisionModelProvider,
        modelConfig: ModelConfig,
        progress: @escaping @Sendable (BatchProgress) -> Void
    ) async throws -> BatchSchedulerResult {
        var scoreMap: [UUID: AIScore] = [:]
        var comments: [UUID: String] = [:]
        var recommendations: [UUID: [UUID]] = [:]
        var costRecords: [CostRecord] = []
        var completedGroups = 0

        let eligibleGroups = groups.filter { group in
            group.assets.contains { assetID in
                if let asset = assetsByID[assetID] {
                    return !asset.isTechnicallyRejected && asset.primaryDisplayURL != nil
                }
                return false
            }
        }

        for group in eligibleGroups {
            let groupAssets = group.assets.compactMap { assetsByID[$0] }
                .filter { !$0.isTechnicallyRejected }

            let preparedImages = try groupAssets.compactMap { asset -> (UUID, ImageData)? in
                guard let sourceURL = asset.primaryDisplayURL else { return nil }
                return (asset.id, try ImagePreprocessor.prepareImage(from: sourceURL))
            }

            guard !preparedImages.isEmpty else {
                continue
            }

            let context = GroupContext(
                groupName: group.name,
                cameraModel: groupAssets.first?.metadata.cameraModel,
                lensModel: groupAssets.first?.metadata.lensModel,
                timeRangeDescription: timeRangeDescription(group.timeRange)
            )

            let result = try await provider.scoreGroup(images: preparedImages.map(\.1), context: context)
            completedGroups += 1
            progress(.init(completedGroups: completedGroups, totalGroups: eligibleGroups.count, currentGroupName: group.name))

            let orderedIDs = preparedImages.map(\.0)
            for photo in result.photoResults {
                guard photo.index > 0, photo.index <= orderedIDs.count else { continue }
                scoreMap[orderedIDs[photo.index - 1]] = photo.score
            }

            comments[group.id] = result.groupComment ?? ""
            recommendations[group.id] = result.photoResults
                .filter { $0.score.recommended }
                .compactMap { scored in
                    guard scored.index > 0, scored.index <= orderedIDs.count else { return nil }
                    return orderedIDs[scored.index - 1]
                }

            if let usage = result.usage {
                costRecords.append(
                    CostRecord(
                        id: UUID(),
                        modelName: modelConfig.name,
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens,
                        cost: calculateCost(usage: usage, config: modelConfig),
                        timestamp: .now
                    )
                )
            }
        }

        return BatchSchedulerResult(
            scoresByAssetID: scoreMap,
            groupCommentsByID: comments,
            recommendedByGroupID: recommendations,
            costRecords: costRecords
        )
    }

    func analyzeDetails(
        assetIDs: [UUID],
        assetsByID: [UUID: MediaAsset],
        groupsByID: [UUID: PhotoGroup],
        provider: any VisionModelProvider,
        modelConfig: ModelConfig
    ) async throws -> ([UUID: EditSuggestions], [CostRecord]) {
        var suggestions: [UUID: EditSuggestions] = [:]
        var costs: [CostRecord] = []

        for assetID in assetIDs {
            guard let asset = assetsByID[assetID], let sourceURL = asset.primaryDisplayURL else { continue }
            let image = try ImagePreprocessor.prepareImage(from: sourceURL)
            let groupName = groupsByID.first(where: { $0.value.assets.contains(assetID) })?.value.name ?? "未命名场景"
            let context = PhotoContext(
                groupName: groupName,
                exifSummary: exifSummary(for: asset),
                initialScore: asset.aiScore?.overall
            )
            let result = try await provider.detailedAnalysis(image: image, context: context)
            suggestions[assetID] = result.suggestions

            if let usage = result.usage {
                costs.append(
                    CostRecord(
                        id: UUID(),
                        modelName: modelConfig.name,
                        inputTokens: usage.inputTokens,
                        outputTokens: usage.outputTokens,
                        cost: calculateCost(usage: usage, config: modelConfig),
                        timestamp: .now
                    )
                )
            }
        }

        return (suggestions, costs)
    }

    private func calculateCost(usage: TokenUsage, config: ModelConfig) -> Double {
        let inputCost = (Double(usage.inputTokens) * (config.costPerInputToken ?? 0))
        let outputCost = (Double(usage.outputTokens) * (config.costPerOutputToken ?? 0))
        return inputCost + outputCost
    }

    private func exifSummary(for asset: MediaAsset) -> String {
        [
            asset.metadata.aperture.map { String(format: "f/%.1f", $0) },
            asset.metadata.shutterSpeed,
            asset.metadata.iso.map { "ISO \($0)" },
            asset.metadata.focalLength.map { String(format: "%.0fmm", $0) }
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func timeRangeDescription(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }
}
