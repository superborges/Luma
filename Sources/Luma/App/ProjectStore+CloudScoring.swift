import Foundation

/// `ProjectStore` 与 V2 云端评分管线的接入点。
///
/// 设计取舍：放在独立文件而不是塞进 2k+ 行的 `ProjectStore.swift`；
/// 编排逻辑全部在 `CloudScoringCoordinator`，本扩展只负责"把结果落到 manifest + 维护 UI 状态"。
extension ProjectStore {

    // MARK: - 公共 API

    /// 启动云端评分。`.local` 策略直接 no-op（本地评分已在导入阶段完成）。
    func startCloudScoring(strategy: ScoringStrategy) async {
        guard strategy != .local else {
            cloudScoringErrorMessage = "选择了「省钱（仅本地）」策略，不需要发起云端评分。"
            return
        }
        guard let currentSession, let projectDirectory = currentProjectDirectory else {
            cloudScoringErrorMessage = "未打开项目，无法发起评分。"
            return
        }
        let groups = currentSession.groups
        let assets = currentSession.assets
        cloudScoringErrorMessage = nil
        cloudScoringStatus = .running

        // ensureCloudScoringCoordinator 内部已建立进度订阅；此处直接 start，无需再挂监听。
        let coordinator = ensureCloudScoringCoordinator()
        do {
            try await coordinator.start(
                strategy: strategy,
                groups: groups,
                assets: assets,
                in: projectDirectory,
                thresholdUSD: scoringBudgetThreshold
            ) { [weak self] groupID, result, primary in
                await self?.applyGroupScoreResult(groupID: groupID, result: result, providerConfig: primary)
            }
        } catch {
            cloudScoringErrorMessage = error.localizedDescription
            cloudScoringStatus = .failed
        }
    }

    /// 取消当前评分批次（结果保留）。
    func cancelCloudScoring() {
        cloudScoringCoordinator?.cancel()
        cloudScoringStatus = .paused
    }

    /// 把单组评分结果写回 `MediaAsset.aiScore` 与 `PhotoGroup.recommendedAssets / groupComment`。
    /// `groupBest` 是 1-indexed（对应发送的图像顺序）；本函数负责转换。
    /// 同时**保留** asset 现有的 `issues`（本地 Core ML 的废片标签不被覆盖）。
    func applyGroupScoreResult(
        groupID: UUID,
        result: GroupScoreResult,
        providerConfig: ModelConfig
    ) async {
        guard let i = activeSessionIndexInternal,
              let groupIndex = sessions[i].groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        let assetIDs = sessions[i].groups[groupIndex].assets
        let providerString = "cloud:\(providerConfig.apiProtocol.rawValue):\(providerConfig.modelID)"
        let now = Date()

        let calibration = providerConfig.calibration

        for perPhoto in result.perPhoto {
            let zeroBased = perPhoto.index - 1
            guard zeroBased >= 0, zeroBased < assetIDs.count else { continue }
            let assetID = assetIDs[zeroBased]
            guard let assetIndex = sessions[i].assets.firstIndex(where: { $0.id == assetID }) else { continue }

            let finalScores: PhotoScores
            let finalOverall: Int
            if let cal = calibration {
                (finalScores, finalOverall) = ScoreCalibrator.normalize(
                    scores: perPhoto.scores, overall: perPhoto.overall, using: cal
                )
            } else {
                finalScores = perPhoto.scores
                finalOverall = perPhoto.overall
            }

            let aiScore = AIScore(
                provider: providerString,
                scores: finalScores,
                overall: finalOverall,
                comment: perPhoto.comment,
                recommended: perPhoto.recommended,
                timestamp: now
            )
            sessions[i].assets[assetIndex].aiScore = aiScore
        }

        // 把 group_best (1-based) 转成 asset UUID 写入 recommendedAssets
        let recommended = result.groupBest.compactMap { idx1Based -> UUID? in
            let zeroBased = idx1Based - 1
            return assetIDs.indices.contains(zeroBased) ? assetIDs[zeroBased] : nil
        }
        sessions[i].groups[groupIndex].recommendedAssets = recommended
        sessions[i].groups[groupIndex].groupComment = result.groupComment
        sessions[i].updatedAt = now

        // 必须主动失效 derived state 缓存：上面是深层路径写入（绕过 assets / groups setter），
        // 否则 assetLookupCache / groupLookupCache 仍是旧值，selectedAsset 在 UI 中不更新。
        invalidateAllCachesAfterDirectMutation()

        // 立即落盘（断点续传场景，每组写一次）
        persistManifestNow()
    }
}

// MARK: - AI 组名生成

extension ProjectStore {

    /// 手动或自动触发 AI 组名生成。串行对每组调用 primary 模型。
    func generateAIGroupNames() async {
        guard let i = activeSessionIndexInternal else { return }
        let groups = sessions[i].groups
        let assets = sessions[i].assets
        guard !groups.isEmpty else { return }

        let primary: ModelConfig
        let apiKey: String
        do {
            let configs = try modelConfigStore.loadConfigs()
            guard let p = configs.first(where: { $0.isActive && $0.role == .primary }) else { return }
            primary = p
            guard let key = try modelConfigStore.apiKey(for: primary.id), !key.isEmpty else { return }
            apiKey = key
        } catch {
            RuntimeTrace.event(
                "ai_group_naming_failed",
                category: "ai_scoring",
                metadata: ["error": error.localizedDescription]
            )
            return
        }

        await AIGroupNamer.generateNames(
            groups: groups,
            assets: assets,
            config: primary,
            apiKey: apiKey
        ) { [weak self] result in
            self?.applyGroupName(result)
        }
    }

    /// 将 AI 生成的组名写入 PhotoGroup.name 并持久化。
    private func applyGroupName(_ result: AIGroupNamer.NamingResult) {
        guard result.isAIGenerated,
              let i = activeSessionIndexInternal,
              let groupIndex = sessions[i].groups.firstIndex(where: { $0.id == result.groupID }) else {
            return
        }

        sessions[i].groups[groupIndex].name = result.name
        sessions[i].updatedAt = .now
        invalidateAllCachesAfterDirectMutation()
        persistManifestNow()
    }
}

// MARK: - 内部辅助

extension ProjectStore {
    /// 暴露给 extension 的 activeSessionIndex 桥接。原 private 不可见，故做一个 public-internal 包装。
    var activeSessionIndexInternal: Int? {
        guard let activeSessionID else { return nil }
        return sessions.firstIndex { $0.id == activeSessionID }
    }

    /// 立即写盘（不走 debounced manifestSaveTask），用于云端评分单组完成后。
    func persistManifestNow() {
        guard let currentProjectDirectory, let i = activeSessionIndexInternal else { return }
        let manifest = SessionManifest(id: currentManifestID, session: sessions[i])
        let url = AppDirectories.manifestURL(in: currentProjectDirectory)
        do {
            let data = try JSONEncoder.lumaEncoder.encode(manifest)
            try data.write(to: url, options: [.atomic])
        } catch {
            // 不阻塞流程；上层会在下次 debounced flush 时再试。
            RuntimeTrace.event(
                "scoring_manifest_flush_failed",
                category: "ai_scoring",
                metadata: ["error": error.localizedDescription]
            )
        }
    }

    /// 懒加载 Coordinator。本对象与 ProjectStore 同生命周期。
    /// **关键**：创建时立即订阅 progress 流，确保 `start()` 触发的首批事件不会因订阅滞后而遗漏。
    func ensureCloudScoringCoordinator() -> CloudScoringCoordinator {
        if let existing = cloudScoringCoordinator { return existing }
        let coord = CloudScoringCoordinator(modelConfigStore: modelConfigStore)
        cloudScoringCoordinator = coord

        // 立即挂监听；不依赖任何 start() 调用顺序。
        scoringProgressTask?.cancel()
        scoringProgressTask = Task { @MainActor [weak self] in
            for await event in coord.progressEvents {
                self?.cloudScoringProgress = event
                self?.cloudScoringStatus = event.status
                self?.currentBudgetSnapshot = event.budget
                if event.budget.exceededThreshold {
                    self?.budgetExceededAlertVisible = true
                }
                if event.status == .completed {
                    // 评分完成后自动触发 AI 组名生成
                    Task { @MainActor [weak self] in
                        await self?.generateAIGroupNames()
                    }
                    // 延迟 3 秒自动收起进度条
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        guard self?.cloudScoringStatus == .completed else { return }
                        self?.cloudScoringStatus = .idle
                        self?.cloudScoringProgress = nil
                    }
                }
            }
        }
        return coord
    }
}
