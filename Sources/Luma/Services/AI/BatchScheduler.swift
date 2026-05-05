import Foundation

/// 一个待评分组：包含 ID、名称与"如何评分"的闭包。
///
/// 设计取舍：闭包形式而非直接传 `VisionModelProvider`，让 BatchScheduler 不感知具体 Provider，
/// 也方便单测注入 stub 闭包验证调度逻辑（重试、并发、取消）。
struct ScoringTask: Sendable {
    let groupID: UUID
    let groupName: String
    /// 真实评分逻辑。返回 `(result, modelDisplayName)`，模型名用于 UI 进度展示。
    let work: @Sendable () async throws -> (GroupScoreResult, String)
}

/// 把一批 `ScoringTask` 调度执行：限并发、指数退避、按完成顺序回调。
///
/// 设计取舍：
/// - 用 `TaskGroup` + 内部信号量（计数 actor）实现真并发上限
/// - 重试在单组内部循环：1s → 4s → 16s 三次后放弃
/// - 取消 / 暂停语义：调用方持有 `Task` 并 `cancel()` 即可；scheduler 内部检查
///   `Task.isCancelled` 决定是否继续
/// - 不做"暂停"概念——暂停 = 取消 + 保留已完成结果（由 Coordinator 承担）
struct BatchScheduler: Sendable {

    let maxConcurrency: Int
    let maxRetries: Int

    init(maxConcurrency: Int = 4, maxRetries: Int = 3) {
        self.maxConcurrency = max(1, maxConcurrency)
        self.maxRetries = max(0, maxRetries)
    }

    /// 执行一批任务。`onCompleted` 在每个 group 完成（成功或失败）后**串行**回调。
    /// 串行 = 同一时刻只有一个回调在执行；用 actor 串行化便于上层不加锁更新状态。
    func run(
        tasks: [ScoringTask],
        onCompleted: @escaping @Sendable (UUID, String /*groupName*/, Result<(GroupScoreResult, String), Error>) async -> Void
    ) async {
        guard !tasks.isEmpty else { return }

        let semaphore = ConcurrencySemaphore(limit: maxConcurrency)

        await withTaskGroup(of: Void.self) { group in
            for task in tasks {
                group.addTask { [maxRetries] in
                    await semaphore.acquire()

                    if Task.isCancelled {
                        await semaphore.release()
                        await onCompleted(task.groupID, task.groupName, .failure(CancellationError()))
                        return
                    }

                    let result = await Self.runWithRetry(task: task, maxRetries: maxRetries)
                    // 立即同步释放信号量，避免并发槽位泄漏导致短暂超出 maxConcurrency。
                    // 不能用 defer + Task.detached：那样下一个 acquire 看不到 release，会误打开新槽位。
                    await semaphore.release()
                    await onCompleted(task.groupID, task.groupName, result)
                }
            }
            await group.waitForAll()
        }
    }

    // MARK: - Retry

    /// 按 1s → 4s → 16s 间隔重试，最多 maxRetries 次。
    /// 取消错误（CancellationError）不重试，立即返回。
    /// HTTP 4xx 中除 429 / 408 外不重试（鉴权 / 请求格式错误重试无意义）。
    static func runWithRetry(
        task: ScoringTask,
        maxRetries: Int
    ) async -> Result<(GroupScoreResult, String), Error> {
        var lastError: Error?
        for attempt in 0...maxRetries {
            if Task.isCancelled {
                return .failure(CancellationError())
            }
            do {
                let value = try await task.work()
                return .success(value)
            } catch is CancellationError {
                return .failure(CancellationError())
            } catch let LumaError.aiProvider(code, message) where !shouldRetry(httpStatus: code) {
                // 保留首次抛出的具体错误消息（如 "401 Invalid API Key"），不要被 lastError 覆盖。
                return .failure(LumaError.aiProvider(code: code, message: message))
            } catch {
                lastError = error
                if attempt == maxRetries { break }
                let delay = retryDelay(for: attempt)
                RuntimeTrace.event(
                    "scoring_group_retry",
                    category: "ai_scoring",
                    metadata: [
                        "group_id": task.groupID.uuidString,
                        "attempt": String(attempt + 1),
                        "delay_seconds": String(format: "%.0f", delay),
                        "error": error.localizedDescription
                    ]
                )
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        return .failure(lastError ?? LumaError.networkFailed("评分失败"))
    }

    /// 4xx 中只有 408（请求超时）和 429（限速）值得重试；其他不重试。
    /// 5xx 全部值得重试。负数（自定义 normalizer 错误）也重试一次以应对偶发响应畸变。
    private static func shouldRetry(httpStatus: Int) -> Bool {
        if httpStatus == 408 || httpStatus == 429 { return true }
        if (500..<600).contains(httpStatus) { return true }
        if httpStatus < 0 { return true }
        return false
    }

    private static func retryDelay(for attempt: Int) -> TimeInterval {
        switch attempt {
        case 0: return 1
        case 1: return 4
        default: return 16
        }
    }
}

// MARK: - 内部信号量

/// 简单的计数 actor 实现并发上限。比 `DispatchSemaphore` 更适合 Swift Concurrency。
actor ConcurrencySemaphore {
    private let limit: Int
    private var inUse: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if inUse < limit {
            inUse += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        } else {
            inUse = max(0, inUse - 1)
        }
    }
}
