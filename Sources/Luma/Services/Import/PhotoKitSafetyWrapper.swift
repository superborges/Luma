import Foundation

/// PhotoKit 调用的超时防御层。
///
/// macOS 上 `PHAsset.fetchAssets` / `PHAssetCollection.fetchAssetCollections` 在 Photos.app
/// 同时导入时可能导致 `photolibraryd` 崩溃或挂起（Apple FB13178379）。
/// 用 timeout 包裹，超时返回 fallback 值，避免 Luma 卡死。
enum PhotoKitSafetyWrapper {

    static func withTimeout<T: Sendable>(
        _ timeout: TimeInterval,
        fallback: T,
        operation: @Sendable @escaping () async -> T
    ) async -> T {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            for await result in group {
                if let value = result {
                    group.cancelAll()
                    return value
                }
                // timeout task returned nil — cancel the (possibly hanging) operation immediately
                group.cancelAll()
                RuntimeTrace.event(
                    "photokit_timeout",
                    category: "import",
                    metadata: ["timeout_seconds": String(format: "%.1f", timeout)]
                )
                return fallback
            }
            group.cancelAll()
            return fallback
        }
    }
}

// Estimate.timeoutFallback 已移除：v2 月份选择器不再使用单独的 estimate 流程。
