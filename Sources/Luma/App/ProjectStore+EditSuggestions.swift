import Foundation

/// V2 单张修图建议接入。
///
/// 流程：
/// 1. 用户在右栏点「请求修图建议」
/// 2. ProjectStore 找 `role == .premiumFallback && isActive` 的模型 + Keychain 读 key
/// 3. 用 `ImagePayloadBuilder` 把照片打包成 1024px JPEG
/// 4. Provider 调 `detailedAnalysis(...)` → 拿到 `DetailedAnalysisResult`
/// 5. 写回 `MediaAsset.editSuggestions` + manifest flush
/// 6. UI 通过 `editSuggestionsRequestStatus[assetID]` 状态触发卡片刷新
extension ProjectStore {

    /// 请求单张照片的修图建议。允许并发不同 asset，但同一 asset 不会并发。
    func requestEditSuggestions(for assetID: UUID, providerFactory: ProviderFactory = DefaultProviderFactory()) async {
        // 已在请求中：忽略重复点击
        if case .loading = editSuggestionsRequestStatus[assetID] { return }

        guard let i = activeSessionIndexInternal,
              let assetIndex = sessions[i].assets.firstIndex(where: { $0.id == assetID }) else {
            editSuggestionsRequestStatus[assetID] = .failed(message: "找不到目标照片。")
            return
        }
        let asset = sessions[i].assets[assetIndex]
        let groupName = sessions[i].groups.first(where: { $0.assets.contains(assetID) })?.name ?? asset.baseName

        // 选 premiumFallback 模型；策略 .balanced/.best 都依赖该角色
        let configs: [ModelConfig]
        do {
            configs = try modelConfigStore.loadConfigs()
        } catch {
            editSuggestionsRequestStatus[assetID] = .failed(message: "读取模型配置失败：\(error.localizedDescription)")
            return
        }
        guard let premium = configs.first(where: { $0.isActive && $0.role == .premiumFallback }) else {
            editSuggestionsRequestStatus[assetID] = .failed(message: "未配置 premiumFallback 模型。请去设置页添加角色为「精评」的模型。")
            return
        }
        let apiKey: String?
        do {
            apiKey = try modelConfigStore.apiKey(for: premium.id)
        } catch {
            editSuggestionsRequestStatus[assetID] = .failed(message: "读取 API Key 失败：\(error.localizedDescription)")
            return
        }
        guard let apiKey, !apiKey.isEmpty else {
            editSuggestionsRequestStatus[assetID] = .failed(message: "模型 \(premium.name) 的 API Key 未配置。")
            return
        }

        // 标记 loading
        editSuggestionsRequestStatus[assetID] = .loading

        // 准备 image payload
        guard let url = asset.previewURL ?? asset.thumbnailURL ?? asset.rawURL else {
            editSuggestionsRequestStatus[assetID] = .failed(message: "找不到照片的预览图。")
            return
        }
        guard let payload = await ImagePayloadBuilder.payload(from: url) else {
            editSuggestionsRequestStatus[assetID] = .failed(message: "无法读取照片预览图。")
            return
        }

        // 调 Provider
        let provider = providerFactory.makeProvider(config: premium, apiKey: apiKey)
        let context = PhotoContext(
            baseName: asset.baseName,
            exif: asset.metadata,
            groupName: groupName,
            initialOverallScore: asset.aiScore?.overall
        )

        do {
            let result = try await provider.detailedAnalysis(image: payload, context: context)
            applyEditSuggestionsResult(assetID: assetID, result: result)
            editSuggestionsRequestStatus[assetID] = .completed
            RuntimeTrace.event(
                "edit_suggestions_completed",
                category: "ai_scoring",
                metadata: [
                    "asset_id": assetID.uuidString,
                    "model": premium.name,
                    "input_tokens": String(result.usage.inputTokens),
                    "output_tokens": String(result.usage.outputTokens)
                ]
            )
        } catch {
            editSuggestionsRequestStatus[assetID] = .failed(message: error.localizedDescription)
            RuntimeTrace.event(
                "edit_suggestions_failed",
                category: "ai_scoring",
                metadata: [
                    "asset_id": assetID.uuidString,
                    "error": error.localizedDescription
                ]
            )
        }
    }

    /// 把 detailed analysis 结果写回 manifest。**保留** `usage` 不入库（修图建议本身不带 token 字段）。
    func applyEditSuggestionsResult(assetID: UUID, result: DetailedAnalysisResult) {
        guard let i = activeSessionIndexInternal,
              let assetIndex = sessions[i].assets.firstIndex(where: { $0.id == assetID }) else {
            return
        }
        let suggestions = EditSuggestions(
            crop: result.crop,
            filterStyle: result.filterStyle,
            adjustments: result.adjustments,
            hslAdjustments: result.hsl,
            localEdits: result.localEdits,
            narrative: result.narrative
        )
        sessions[i].assets[assetIndex].editSuggestions = suggestions
        sessions[i].updatedAt = .now
        // 同 applyGroupScoreResult：深层路径写入需主动失效缓存，否则 UI 拿不到新 editSuggestions
        invalidateAllCachesAfterDirectMutation()
        persistManifestNow()
    }

    /// 是否已有 premiumFallback 模型可用（决定按钮是否启用）。UI 用。
    var hasPremiumFallbackModel: Bool {
        guard let configs = try? modelConfigStore.loadConfigs() else { return false }
        return configs.contains(where: { $0.isActive && $0.role == .premiumFallback })
    }
}
