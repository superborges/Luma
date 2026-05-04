import Foundation

/// Provider 工厂：按 `ModelConfig + apiKey` 实例化对应协议的 Provider。
/// 默认实现 `DefaultProviderFactory`；测试用 `MockProviderFactory` 注入 stub。
protocol ProviderFactory: Sendable {
    func makeProvider(config: ModelConfig, apiKey: String) -> any VisionModelProvider
}

struct DefaultProviderFactory: ProviderFactory {
    let httpClient: HTTPClient

    init(httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func makeProvider(config: ModelConfig, apiKey: String) -> any VisionModelProvider {
        switch config.apiProtocol {
        case .openAICompatible:
            return OpenAICompatibleProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .googleGemini:
            return GoogleGeminiProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        case .anthropicMessages:
            return AnthropicMessagesProvider(config: config, apiKey: apiKey, httpClient: httpClient)
        }
    }
}

// MARK: - Coordinator

/// 编排云端批量评分：选模型 → 准备 payload → 调度 BatchScheduler → 回写结果 + 写盘。
///
/// 设计取舍：
/// - 不依赖 ProjectStore；通过 callback 把"组评分完成"事件传给外部消费者（ProjectStore 监听后写入 manifest）
/// - 一次只能跑一个批次；重复 start 会先 cancel 上一批
/// - cancel 语义：取消所有 in-flight，已完成结果通过 callback 已经写出，scoring_job.json 标记为 paused
/// - 暂停 = 取消 + 标记 paused；resume 时调用 `resume(...)` 重启对剩余 pending 的组
@MainActor
final class CloudScoringCoordinator {
    // MARK: - Dependencies

    private let providerFactory: ProviderFactory
    private let modelConfigStore: ModelConfigStore
    private let jobStore: ScoringJobStore
    private let scheduler: BatchScheduler

    // MARK: - State

    private(set) var currentJob: ScoringJob?
    private(set) var currentJobProjectDirectory: URL?
    private var budget: BudgetTracker?
    private var runTask: Task<Void, Never>?
    private var thresholdMonitorTask: Task<Void, Never>?

    /// 外部消费者订阅的进度流。
    let progressEvents: AsyncStream<ScoringProgressEvent>
    private let progressContinuation: AsyncStream<ScoringProgressEvent>.Continuation

    // MARK: - Init

    init(
        providerFactory: ProviderFactory = DefaultProviderFactory(),
        modelConfigStore: ModelConfigStore,
        jobStore: ScoringJobStore = FileScoringJobStore(),
        scheduler: BatchScheduler = BatchScheduler()
    ) {
        self.providerFactory = providerFactory
        self.modelConfigStore = modelConfigStore
        self.jobStore = jobStore
        self.scheduler = scheduler

        var continuationRef: AsyncStream<ScoringProgressEvent>.Continuation!
        self.progressEvents = AsyncStream { continuationRef = $0 }
        self.progressContinuation = continuationRef
    }

    deinit {
        progressContinuation.finish()
    }

    // MARK: - Public API

    /// 启动一次批量评分。
    ///
    /// - Parameters:
    ///   - strategy: 评分策略；`.local` 时直接抛出 `LumaError.unsupported` 拒绝调用方
    ///   - groups: 待评分的 PhotoGroup 列表
    ///   - assets: session 中所有 asset（用于查找每组对应 asset 的 previewURL）
    ///   - projectDirectory: scoring_job.json 落盘目录
    ///   - thresholdUSD: 费用阈值
    ///   - onGroupResult: 每组成功完成时的回调，由 ProjectStore 实现写 manifest
    func start(
        strategy: ScoringStrategy,
        groups: [PhotoGroup],
        assets: [MediaAsset],
        in projectDirectory: URL,
        thresholdUSD: Double,
        onGroupResult: @escaping @MainActor (UUID, GroupScoreResult, ModelConfig) async -> Void
    ) async throws {
        guard strategy != .local else {
            throw LumaError.unsupported("ScoringStrategy.local 不需要调用 Coordinator")
        }
        guard !groups.isEmpty else {
            throw LumaError.configurationInvalid("当前 session 没有可评分的分组")
        }

        // 1. 选 primary 模型
        let configs = try modelConfigStore.loadConfigs()
        guard let primary = configs.first(where: { $0.isActive && $0.role == .primary }) else {
            throw LumaError.configurationInvalid("未配置可用的 primary AI 模型，请先去设置页添加")
        }
        guard let apiKey = try modelConfigStore.apiKey(for: primary.id), !apiKey.isEmpty else {
            throw LumaError.configurationInvalid("模型 \(primary.name) 的 API Key 未配置")
        }
        let provider = providerFactory.makeProvider(config: primary, apiKey: apiKey)

        // 2. 取消上一批次（如果有）
        cancel()

        // 3. 初始化 BudgetTracker、ScoringJob
        let tracker = BudgetTracker(thresholdUSD: thresholdUSD)
        budget = tracker

        // 优先复用磁盘上未完成的 job（断点续传）。要求 strategy/primaryModelID 一致才算"同一批次"。
        let resumed = (try? jobStore.load(in: projectDirectory)).flatMap { $0 }

        // 阈值暂停 + 实际所有组已完成 → 直接 finalize，不重跑。
        // 仅限 .paused 状态；.completed 的旧 job 说明是前一次正常结束，用户要开新批次。
        if let resumed,
           resumed.strategy == strategy,
           resumed.primaryModelID == primary.id,
           resumed.status == .paused,
           resumed.remainingGroups == 0 {
            var done = resumed
            done.status = .completed
            currentJob = done
            try? jobStore.save(done, in: projectDirectory)
            emitProgress(message: "评分完成")
            return
        }

        let initialJob: ScoringJob
        if let resumed,
           resumed.strategy == strategy,
           resumed.primaryModelID == primary.id,
           resumed.status != .completed {
            await tracker.restore(from: resumed.budget)
            // 把 running 状态降级回 pending（重启意味着重做）
            var rebuilt = resumed
            for (id, status) in rebuilt.groupStatuses where status == .running {
                rebuilt.groupStatuses[id] = .pending
            }
            rebuilt.status = .running
            rebuilt.pausedReason = nil
            rebuilt.budget = await tracker.snapshot()
            initialJob = rebuilt
        } else {
            // 新批次
            var statuses: [UUID: GroupScoringStatus] = [:]
            for g in groups { statuses[g.id] = .pending }
            initialJob = ScoringJob(
                id: UUID(),
                strategy: strategy,
                primaryModelID: primary.id,
                premiumModelID: configs.first(where: { $0.isActive && $0.role == .premiumFallback })?.id,
                startedAt: .now,
                totalGroups: groups.count,
                status: .running,
                pausedReason: nil,
                groupStatuses: statuses,
                budget: BudgetSnapshot(inputTokens: 0, outputTokens: 0, usd: 0, thresholdUSD: thresholdUSD)
            )
        }
        currentJob = initialJob
        currentJobProjectDirectory = projectDirectory
        try? jobStore.save(initialJob, in: projectDirectory)

        // 4. 监听 budget 阈值
        thresholdMonitorTask = Task { [weak self] in
            for await snap in tracker.thresholdCrossedStream {
                await MainActor.run { self?.handleBudgetExceeded(snap) }
            }
        }

        // 5. 仅给"未完成"的组准备 ScoringTask
        let pendingGroups = groups.filter { (initialJob.groupStatuses[$0.id] ?? .pending) != .completed }
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })

        let tasks: [ScoringTask] = pendingGroups.compactMap { group in
            // 取该组所有 asset 的预览 URL（最多 8 张，太多会把 token 烧爆）
            let urls: [URL] = group.assets.prefix(8).compactMap { assetID -> URL? in
                guard let asset = assetsByID[assetID] else { return nil }
                return asset.previewURL ?? asset.thumbnailURL
            }
            guard !urls.isEmpty else { return nil }

            let firstAsset = group.assets.compactMap { assetsByID[$0] }.first
            let context = GroupContext(
                groupName: group.name,
                cameraModel: firstAsset?.metadata.cameraModel,
                lensModel: firstAsset?.metadata.lensModel,
                timeRangeDescription: timeRangeDescription(for: group)
            )

            let modelDisplayName = primary.name
            let providerLocal = provider
            return ScoringTask(
                groupID: group.id,
                groupName: group.name,
                work: { @Sendable in
                    var payloads: [ProviderImagePayload] = []
                    for url in urls {
                        if let p = await ImagePayloadBuilder.payload(from: url) {
                            payloads.append(p)
                        }
                    }
                    if payloads.isEmpty {
                        throw LumaError.importFailed("无法读取该分组的预览图")
                    }
                    let result = try await providerLocal.scoreGroup(images: payloads, context: context)
                    return (result, modelDisplayName)
                }
            )
        }

        // 6. 启动调度
        runTask = Task { [weak self, scheduler, primary] in
            await scheduler.run(tasks: tasks) { [weak self] groupID, groupName, result in
                await self?.handleGroupCompleted(
                    groupID: groupID,
                    groupName: groupName,
                    result: result,
                    primaryConfig: primary,
                    onGroupResult: onGroupResult
                )
            }
            await self?.finalizeIfDone()
        }
    }

    /// 取消当前批次。已完成的组结果保留；未完成的组在 scoring_job.json 中维持 pending。
    func cancel() {
        runTask?.cancel()
        runTask = nil
        thresholdMonitorTask?.cancel()
        thresholdMonitorTask = nil

        if var job = currentJob, let dir = currentJobProjectDirectory, job.status == .running {
            job.status = .paused
            job.pausedReason = "用户取消"
            currentJob = job
            try? jobStore.save(job, in: dir)
            emitProgress(message: "已取消")
        }
    }

    /// 阈值超出 → 暂停（同 cancel，但标记原因不同）。
    private func handleBudgetExceeded(_ snap: BudgetSnapshot) {
        guard var job = currentJob, let dir = currentJobProjectDirectory else { return }
        // 如果所有组已完成，没有暂停的必要——避免把 .completed 覆盖成 .paused，
        // 否则"调整阈值并继续"会误以为还有未完成的工作而重新开始。
        guard job.remainingGroups > 0 else { return }
        runTask?.cancel()
        runTask = nil
        thresholdMonitorTask?.cancel()
        thresholdMonitorTask = nil
        job.status = .paused
        job.pausedReason = "费用超过阈值 \(snap.prettyUSD)"
        job.budget = snap
        currentJob = job
        try? jobStore.save(job, in: dir)
        emitProgress(message: job.pausedReason)
    }

    // MARK: - Group 完成

    private func handleGroupCompleted(
        groupID: UUID,
        groupName: String,
        result: Result<(GroupScoreResult, String), Error>,
        primaryConfig: ModelConfig,
        onGroupResult: @MainActor (UUID, GroupScoreResult, ModelConfig) async -> Void
    ) async {
        guard var job = currentJob, let dir = currentJobProjectDirectory else { return }

        switch result {
        case .success(let (groupResult, _)):
            // 1. BudgetTracker 累加
            // 注意：budget.add 内部可能触发 thresholdCrossedStream，
            // 导致 thresholdMonitorTask 在后续 await 暂停点抢先执行 handleBudgetExceeded。
            // 因此必须在任何 await 之前，先把 groupStatuses 标记为 completed 并写盘，
            // 防止 handleBudgetExceeded 保存一份"该组仍 running/pending"的脏快照，
            // 造成断点续传时重复评分。
            let cost = groupResult.usage.cost(
                inputUSDPerMillion: primaryConfig.costPerInputTokenUSD,
                outputUSDPerMillion: primaryConfig.costPerOutputTokenUSD
            )
            let snap: BudgetSnapshot
            if let budget {
                snap = await budget.add(usage: groupResult.usage, cost: cost)
            } else {
                snap = job.budget
            }

            // 2. 先把该组标记 completed 并写盘（必须在所有 await 之前）
            job.groupStatuses[groupID] = .completed
            job.budget = snap
            currentJob = job
            try? jobStore.save(job, in: dir)

            // 3. 通知 ProjectStore 写 manifest（含 await，此后 thresholdMonitorTask 可安全介入）
            await onGroupResult(groupID, groupResult, primaryConfig)

            // 4. UI 进度
            emitProgress(currentGroupName: groupName, currentModelDisplayName: primaryConfig.name)

        case .failure(let error):
            // CancellationError 不计入失败统计
            if error is CancellationError {
                return
            }
            job.groupStatuses[groupID] = .failed
            currentJob = job
            try? jobStore.save(job, in: dir)
            RuntimeTrace.event(
                "scoring_group_failed",
                category: "ai_scoring",
                metadata: [
                    "group_id": groupID.uuidString,
                    "group_name": groupName,
                    "error": error.localizedDescription
                ]
            )
            emitProgress(currentGroupName: groupName, currentModelDisplayName: primaryConfig.name, message: "组评分失败：\(error.localizedDescription)")
        }
    }

    private func finalizeIfDone() async {
        guard var job = currentJob, let dir = currentJobProjectDirectory else { return }
        // 只有 .running 状态才可以过渡到 .completed。
        // 如果 handleBudgetExceeded 已经把 job 设为 .paused，不能覆盖——
        // 否则"调整阈值并继续"会看到 .completed 而误走"新批次"分支，导致全量重跑。
        guard job.status == .running else { return }
        if job.remainingGroups == 0 {
            job.status = .completed
            currentJob = job
            try? jobStore.save(job, in: dir)
            emitProgress(message: "评分完成")
        }
    }

    // MARK: - Progress 推送

    private func emitProgress(
        currentGroupName: String? = nil,
        currentModelDisplayName: String? = nil,
        message: String? = nil
    ) {
        guard let job = currentJob else { return }
        let event = ScoringProgressEvent(
            jobID: job.id,
            totalGroups: job.totalGroups,
            completedGroups: job.completedGroups,
            failedGroups: job.failedGroups,
            currentGroupName: currentGroupName,
            currentModelDisplayName: currentModelDisplayName,
            budget: job.budget,
            status: job.status,
            message: message
        )
        progressContinuation.yield(event)
    }

    // MARK: - 工具

    private func timeRangeDescription(for group: PhotoGroup) -> String? {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "\(formatter.string(from: group.timeRange.lowerBound)) - \(formatter.string(from: group.timeRange.upperBound))"
    }
}
