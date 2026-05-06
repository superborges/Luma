import Foundation
import GRDB
import Observation
import os

enum SmartFilter: String, Hashable, CaseIterable, Identifiable, Sendable {
    case all
    case aiRecommended
    case picked
    case rejected
    case pending
    case problematic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "全部照片"
        case .aiRecommended: return "AI 推荐"
        case .picked: return "已选"
        case .rejected: return "未选"
        case .pending: return "未审"
        case .problematic: return "可清理"
        }
    }
}

@MainActor @Observable
final class ExpeditionWorkspaceStore {

    // MARK: - Dependencies

    private let db: LumaDatabase
    private let assetManager: AssetManager
    private let expeditionManager: ExpeditionManager
    private let photoGroupRepo: any PhotoGroupRepository
    private let scoreRepo: any AssetScoreRepository

    private static let logger = Logger(subsystem: "Luma", category: "ExpeditionWorkspaceStore")

    // MARK: - Observable State

    private(set) var currentExpedition: Expedition?
    private(set) var expeditionAssets: [ExpeditionAssetWithMaster] = []
    private(set) var groups: [PhotoGroupWithAssets] = []
    var selectedGroupId: UUID?
    var selectedAssetId: UUID?
    var activeFilter: SmartFilter = .all

    // MARK: - Derived State

    var visibleAssets: [ExpeditionAssetWithMaster] {
        let source: [ExpeditionAssetWithMaster]

        if let groupId = selectedGroupId,
           let group = groups.first(where: { $0.id == groupId }) {
            source = group.assets
        } else {
            source = expeditionAssets
        }

        switch activeFilter {
        case .all:
            return source
        case .aiRecommended:
            return source.filter { $0.decision == .pending && $0.isRecommended }
        case .picked:
            return source.filter { $0.decision == .picked }
        case .rejected:
            return source.filter { $0.decision == .rejected }
        case .pending:
            return source.filter { $0.decision == .pending }
        case .problematic:
            return source.filter { $0.effectiveRating <= 2 }
        }
    }

    var selectedAsset: ExpeditionAssetWithMaster? {
        guard let id = selectedAssetId else { return nil }
        return visibleAssets.first(where: { $0.assetId == id })
            ?? expeditionAssets.first(where: { $0.assetId == id })
    }

    var pickedCount: Int { expeditionAssets.count(where: { $0.decision == .picked }) }
    var rejectedCount: Int { expeditionAssets.count(where: { $0.decision == .rejected }) }
    var pendingCount: Int { expeditionAssets.count(where: { $0.decision == .pending }) }
    var totalCount: Int { expeditionAssets.count }

    var archiveableAssets: [ExpeditionAssetWithMaster] {
        expeditionAssets.filter { $0.decision == .rejected && !$0.expeditionAsset.isArchived }
    }

    // MARK: - Init

    init(
        db: LumaDatabase,
        assetManager: AssetManager,
        expeditionManager: ExpeditionManager,
        photoGroupRepo: any PhotoGroupRepository,
        scoreRepo: any AssetScoreRepository
    ) {
        self.db = db
        self.assetManager = assetManager
        self.expeditionManager = expeditionManager
        self.photoGroupRepo = photoGroupRepo
        self.scoreRepo = scoreRepo
    }

    // MARK: - Expedition Lifecycle

    func openExpedition(id: UUID) throws {
        guard let expedition = try expeditionManager.fetchExpedition(id: id) else {
            throw LumaError.importFailed("找不到 Expedition \(id)")
        }
        currentExpedition = expedition
        activeFilter = .all
        try reloadAssets()
        try reloadGroups()

        if let firstGroup = groups.first {
            selectedGroupId = firstGroup.id
        }
        if let firstAsset = visibleAssets.first {
            selectedAssetId = firstAsset.assetId
        }
    }

    func closeExpedition() {
        currentExpedition = nil
        expeditionAssets = []
        groups = []
        selectedGroupId = nil
        selectedAssetId = nil
        activeFilter = .all
    }

    func refreshGroups() throws {
        try reloadGroups()
    }

    // MARK: - Selection

    func selectGroup(id: UUID?) {
        selectedGroupId = id
        if let firstAsset = visibleAssets.first {
            selectedAssetId = firstAsset.assetId
        } else {
            selectedAssetId = nil
        }
    }

    func selectAsset(id: UUID?) {
        selectedAssetId = id
    }

    func selectAllPhotosOverview() {
        selectedGroupId = nil
        activeFilter = .all
        if let firstAsset = visibleAssets.first {
            selectedAssetId = firstAsset.assetId
        }
    }

    func moveSelection(by offset: Int) {
        let visible = visibleAssets
        guard !visible.isEmpty else { return }

        guard let currentId = selectedAssetId,
              let currentIndex = visible.firstIndex(where: { $0.assetId == currentId }) else {
            selectedAssetId = visible.first?.assetId
            return
        }

        let newIndex = min(max(currentIndex + offset, 0), visible.count - 1)
        selectedAssetId = visible[newIndex].assetId
    }

    // MARK: - Decision & Rating

    func setDecision(assetId: UUID, decision: Decision) throws {
        guard let expeditionId = currentExpedition?.id else { return }
        try assetManager.setDecision(
            expeditionId: expeditionId, assetId: assetId, decision: decision, isUserOverride: true
        )
        try reloadAssets()
        try reloadGroups()
    }

    func togglePicked(assetId: UUID) throws {
        guard let current = expeditionAssets.first(where: { $0.assetId == assetId }) else { return }
        let newDecision: Decision = current.decision == .picked ? .pending : .picked
        try setDecision(assetId: assetId, decision: newDecision)
    }

    func setRating(assetId: UUID, rating: Int?) throws {
        guard let expeditionId = currentExpedition?.id else { return }
        try assetManager.setRating(expeditionId: expeditionId, assetId: assetId, rating: rating)
        try reloadAssets()
        try reloadGroups()
    }

    func applyAIRecommendations(groupId: UUID) throws {
        guard let expeditionId = currentExpedition?.id,
              let group = groups.first(where: { $0.id == groupId }) else { return }
        let targets = group.assets.filter { $0.isRecommended && $0.decision == .pending }
        guard !targets.isEmpty else { return }
        for asset in targets {
            try assetManager.setDecision(
                expeditionId: expeditionId, assetId: asset.assetId, decision: .picked, isUserOverride: false
            )
        }
        try reloadAssets()
        try reloadGroups()
    }

    // MARK: - Group Editing (Product Spec §6.5)

    func mergeGroups(ids: [UUID]) throws {
        guard let expeditionId = currentExpedition?.id,
              ids.count >= 2 else { return }

        let groupsToMerge = groups.filter { ids.contains($0.id) }
        guard groupsToMerge.count >= 2 else { return }

        let targetGroup = groupsToMerge[0]
        let now = Date().timeIntervalSinceReferenceDate

        for sourceGroup in groupsToMerge.dropFirst() {
            let sourceAssets = try photoGroupRepo.fetchAssetsForGroup(sourceGroup.id.uuidString)
            for assetRecord in sourceAssets {
                try photoGroupRepo.removeAsset(groupId: sourceGroup.id.uuidString, assetId: assetRecord.assetId)
                let newRecord = PhotoGroupAssetRecord(
                    groupId: targetGroup.id.uuidString,
                    assetId: assetRecord.assetId,
                    isRecommended: assetRecord.isRecommended
                )
                try? photoGroupRepo.addAsset(newRecord)
            }
            try photoGroupRepo.delete(id: sourceGroup.id.uuidString)
        }

        let updatedRecord = PhotoGroupRecord(
            id: targetGroup.id.uuidString,
            expeditionId: expeditionId.uuidString,
            name: targetGroup.name,
            coverAssetId: targetGroup.coverAssetId?.uuidString,
            groupComment: targetGroup.groupComment,
            timeRangeStart: targetGroup.timeRange?.lowerBound.timeIntervalSinceReferenceDate,
            timeRangeEnd: targetGroup.timeRange?.upperBound.timeIntervalSinceReferenceDate,
            latitude: targetGroup.location?.latitude,
            longitude: targetGroup.location?.longitude,
            reviewed: targetGroup.reviewed,
            createdAt: targetGroup.timeRange?.lowerBound.timeIntervalSinceReferenceDate ?? now,
            updatedAt: now
        )
        try photoGroupRepo.update(updatedRecord)
        try reloadGroups()
    }

    func splitGroup(groupId: UUID, assetIds: Set<UUID>) throws {
        guard let expeditionId = currentExpedition?.id,
              let sourceGroup = groups.first(where: { $0.id == groupId }),
              !assetIds.isEmpty else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let newGroupId = UUID()
        let newRecord = PhotoGroupRecord(
            id: newGroupId.uuidString,
            expeditionId: expeditionId.uuidString,
            name: "\(sourceGroup.name)·拆分",
            coverAssetId: nil,
            groupComment: nil,
            timeRangeStart: sourceGroup.timeRange?.lowerBound.timeIntervalSinceReferenceDate,
            timeRangeEnd: sourceGroup.timeRange?.upperBound.timeIntervalSinceReferenceDate,
            latitude: sourceGroup.location?.latitude,
            longitude: sourceGroup.location?.longitude,
            reviewed: false,
            createdAt: now,
            updatedAt: now
        )
        try photoGroupRepo.insert(newRecord)

        let existingRecords = try photoGroupRepo.fetchAssetsForGroup(groupId.uuidString)
        let existingMap = Dictionary(
            existingRecords.map { ($0.assetId, $0) },
            uniquingKeysWith: { _, b in b }
        )
        for assetId in assetIds {
            let idStr = assetId.uuidString
            guard let found = existingMap[idStr] else { continue }
            try photoGroupRepo.removeAsset(groupId: groupId.uuidString, assetId: idStr)
            let newAssetRecord = PhotoGroupAssetRecord(
                groupId: newGroupId.uuidString,
                assetId: idStr,
                isRecommended: found.isRecommended
            )
            try photoGroupRepo.addAsset(newAssetRecord)
        }

        let remaining = try photoGroupRepo.fetchAssetsForGroup(groupId.uuidString)
        if remaining.isEmpty {
            try photoGroupRepo.delete(id: groupId.uuidString)
        }

        try reloadGroups()
    }

    func removeFromGroup(groupId: UUID, assetIds: Set<UUID>) throws {
        for assetId in assetIds {
            try photoGroupRepo.removeAsset(groupId: groupId.uuidString, assetId: assetId.uuidString)
        }
        let remaining = try photoGroupRepo.fetchAssetsForGroup(groupId.uuidString)
        if remaining.isEmpty {
            try photoGroupRepo.delete(id: groupId.uuidString)
        }
        try reloadGroups()
    }

    func moveToGroup(assetIds: Set<UUID>, targetGroupId: UUID) throws {
        let assetIdStrings = Set(assetIds.map(\.uuidString))
        var preservedRecommended: [String: Bool] = [:]
        for group in groups {
            let groupAssets = try photoGroupRepo.fetchAssetsForGroup(group.id.uuidString)
            for record in groupAssets where assetIdStrings.contains(record.assetId) {
                preservedRecommended[record.assetId] = record.isRecommended
                try photoGroupRepo.removeAsset(groupId: group.id.uuidString, assetId: record.assetId)
            }
            let remaining = try photoGroupRepo.fetchAssetsForGroup(group.id.uuidString)
            if remaining.isEmpty && group.id != targetGroupId {
                try photoGroupRepo.delete(id: group.id.uuidString)
            }
        }

        for assetId in assetIds {
            let idStr = assetId.uuidString
            let record = PhotoGroupAssetRecord(
                groupId: targetGroupId.uuidString,
                assetId: idStr,
                isRecommended: preservedRecommended[idStr] ?? false
            )
            try? photoGroupRepo.addAsset(record)
        }
        try reloadGroups()
    }

    func renameGroup(groupId: UUID, newName: String) throws {
        guard let expeditionId = currentExpedition?.id,
              let group = groups.first(where: { $0.id == groupId }) else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let updatedRecord = PhotoGroupRecord(
            id: group.id.uuidString,
            expeditionId: expeditionId.uuidString,
            name: newName,
            coverAssetId: group.coverAssetId?.uuidString,
            groupComment: group.groupComment,
            timeRangeStart: group.timeRange?.lowerBound.timeIntervalSinceReferenceDate,
            timeRangeEnd: group.timeRange?.upperBound.timeIntervalSinceReferenceDate,
            latitude: group.location?.latitude,
            longitude: group.location?.longitude,
            reviewed: group.reviewed,
            createdAt: group.timeRange?.lowerBound.timeIntervalSinceReferenceDate ?? now,
            updatedAt: now
        )
        try photoGroupRepo.update(updatedRecord)
        try reloadGroups()
    }

    func setGroupCover(groupId: UUID, assetId: UUID) throws {
        guard let expeditionId = currentExpedition?.id,
              let group = groups.first(where: { $0.id == groupId }) else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let updatedRecord = PhotoGroupRecord(
            id: group.id.uuidString,
            expeditionId: expeditionId.uuidString,
            name: group.name,
            coverAssetId: assetId.uuidString,
            groupComment: group.groupComment,
            timeRangeStart: group.timeRange?.lowerBound.timeIntervalSinceReferenceDate,
            timeRangeEnd: group.timeRange?.upperBound.timeIntervalSinceReferenceDate,
            latitude: group.location?.latitude,
            longitude: group.location?.longitude,
            reviewed: group.reviewed,
            createdAt: group.timeRange?.lowerBound.timeIntervalSinceReferenceDate ?? now,
            updatedAt: now
        )
        try photoGroupRepo.update(updatedRecord)
        try reloadGroups()
    }

    private func reloadAssets() throws {
        guard let expeditionId = currentExpedition?.id else {
            expeditionAssets = []
            return
        }

        let expIdStr = expeditionId.uuidString
        let expAssetRecords = try db.dbQueue.read { db in
            try ExpeditionAssetRecord
                .filter(Column("expeditionId") == expIdStr)
                .fetchAll(db)
        }

        let assetIds = expAssetRecords.map(\.assetId)
        guard !assetIds.isEmpty else {
            expeditionAssets = []
            return
        }

        let masterRecords = try db.dbQueue.read { db in
            try MasterAssetRecord.filter(assetIds.contains(Column("id"))).fetchAll(db)
        }
        let masterMap = Dictionary(masterRecords.map { ($0.id, $0) }, uniquingKeysWith: { _, b in b })

        let scoreMap = (try? scoreRepo.fetchLatestByAssets(assetIds)) ?? [:]

        expeditionAssets = expAssetRecords.compactMap { expAssetRecord in
            guard let masterRecord = masterMap[expAssetRecord.assetId],
                  let masterAsset = MasterAsset(record: masterRecord),
                  let expAsset = ExpeditionAsset(record: expAssetRecord) else { return nil }
            return ExpeditionAssetWithMaster(
                expeditionAsset: expAsset,
                masterAsset: masterAsset,
                latestScore: scoreMap[masterRecord.id]
            )
        }
    }

    // MARK: - Scoring

    var isLocalScoring = false
    var localScoringCompleted = 0
    var localScoringTotal = 0

    func triggerLocalScoring() async {
        let masterAssets = expeditionAssets.map(\.masterAsset)
        guard !masterAssets.isEmpty else { return }

        isLocalScoring = true
        localScoringCompleted = 0
        localScoringTotal = masterAssets.count

        let scorer = LocalMLScorer()
        let scoreRepoLocal = scoreRepo

        for (index, masterAsset) in masterAssets.enumerated() {
            let assessment = await scorer.score(masterAsset: masterAsset)
            let record = AssetScoreRecord(
                id: UUID().uuidString,
                assetId: masterAsset.id.uuidString,
                provider: "local_ml",
                composition: assessment.subscores.composition,
                exposure: assessment.subscores.exposure,
                color: assessment.subscores.color,
                sharpness: assessment.subscores.sharpness,
                story: assessment.subscores.story,
                overall: assessment.score,
                comment: assessment.comment,
                recommended: assessment.recommended,
                timestamp: Date().timeIntervalSinceReferenceDate
            )
            try? scoreRepoLocal.insert(record)

            if assessment.recommended, let expeditionId = currentExpedition?.id {
                try? assetManager.setRecommendation(
                    expeditionId: expeditionId,
                    assetId: masterAsset.id,
                    isRecommended: true
                )
            }

            localScoringCompleted = index + 1
        }

        isLocalScoring = false
        try? reloadAssets()
        try? reloadGroups()
    }

    func triggerCloudScoring(
        strategy: ScoringStrategy,
        coordinator: CloudScoringCoordinator,
        projectDirectory: URL,
        thresholdUSD: Double
    ) async throws {
        let masterAssets = expeditionAssets.map(\.masterAsset)
        let v3Groups = groups.map { groupWithAssets -> PhotoGroup in
            PhotoGroup(
                id: groupWithAssets.id,
                name: groupWithAssets.name,
                assets: groupWithAssets.assets.map(\.assetId),
                subGroups: [],
                timeRange: groupWithAssets.timeRange ?? (Date.distantPast...Date.distantFuture),
                location: groupWithAssets.location,
                groupComment: groupWithAssets.groupComment,
                recommendedAssets: groupWithAssets.recommendedAssetIds
            )
        }

        try await coordinator.start(
            strategy: strategy,
            groups: v3Groups,
            masterAssets: masterAssets,
            in: projectDirectory,
            thresholdUSD: thresholdUSD,
            onGroupResult: { [weak self] groupId, result, config in
                await self?.applyCloudScoreResult(groupId: groupId, result: result)
            }
        )
    }

    private func applyCloudScoreResult(groupId: UUID, result: GroupScoreResult) {
        guard let group = groups.first(where: { $0.id == groupId }) else { return }
        let groupAssetIds = group.assets.map(\.assetId)

        for perPhoto in result.perPhoto {
            guard perPhoto.index >= 0, perPhoto.index < groupAssetIds.count else { continue }
            let assetId = groupAssetIds[perPhoto.index]

            let record = AssetScoreRecord(
                id: UUID().uuidString,
                assetId: assetId.uuidString,
                provider: "cloud",
                composition: perPhoto.scores.composition,
                exposure: perPhoto.scores.exposure,
                color: perPhoto.scores.color,
                sharpness: perPhoto.scores.sharpness,
                story: perPhoto.scores.story,
                overall: perPhoto.overall,
                comment: perPhoto.comment,
                recommended: perPhoto.recommended,
                timestamp: Date().timeIntervalSinceReferenceDate
            )
            try? scoreRepo.insert(record)

            if perPhoto.recommended, let expeditionId = currentExpedition?.id {
                try? assetManager.setRecommendation(
                    expeditionId: expeditionId,
                    assetId: assetId,
                    isRecommended: true
                )
            }
        }
        try? reloadAssets()
        try? reloadGroups()
    }

    // MARK: - Private Reload

    private func reloadGroups() throws {
        guard let expeditionId = currentExpedition?.id else {
            groups = []
            return
        }

        let groupRecords = try photoGroupRepo.fetchByExpedition(expeditionId.uuidString)

        let assetMap = Dictionary(
            expeditionAssets.map { ($0.assetId.uuidString, $0) },
            uniquingKeysWith: { _, b in b }
        )

        groups = groupRecords.compactMap { groupRecord in
            let groupAssetRecords = (try? photoGroupRepo.fetchAssetsForGroup(groupRecord.id)) ?? []
            let groupAssets = groupAssetRecords.compactMap { assetMap[$0.assetId] }
            let recommendedIds = groupAssetRecords
                .filter(\.isRecommended)
                .compactMap { UUID(uuidString: $0.assetId) }
            return PhotoGroupWithAssets(
                record: groupRecord,
                assets: groupAssets,
                recommendedAssetIds: recommendedIds
            )
        }
    }
}
