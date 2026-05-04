import SwiftUI

/// 选片右栏的"AI 增强"区块。
///
/// 内容：
/// - 顶部状态行：当前评分来源 + 当前策略
/// - 「请求修图建议」按钮：仅在已配置 premiumFallback 模型时启用
/// - 修图建议结果卡片（已请求过则展开 EditSuggestionsCard）
/// - 失败 / 加载状态
///
/// 设计取舍：
/// - 区块本身不显示 AI 总分（那是 AIScoreCardView 的职责）
/// - 一次只服务当前选中的 asset；asset 切换时 SwiftUI 自动重渲染
struct AIEnhancementSection: View {
    @Bindable var store: ProjectStore
    let asset: MediaAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            actionRow
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .onChange(of: asset.id) { _, newID in
            // 切到新 asset 时，清掉它残留的 .failed 状态（保留 .loading / .completed）。
            // 这样回到曾失败的 asset 不会一直看到失败提示，但仍能区分"在请求中 vs 已有结果"。
            if case .failed = store.editSuggestionsRequestStatus[newID] {
                store.editSuggestionsRequestStatus[newID] = .idle
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(StitchTheme.outline)
            Text("AI 增强")
                .font(StitchTypography.font(size: 11, weight: .bold))
                .foregroundStyle(StitchTheme.onSurface)
                .textCase(.uppercase)
                .tracking(0.8)
            Spacer()
            Text(store.scoringStrategy.displayName)
                .font(StitchTypography.font(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(StitchTheme.primary.opacity(0.7), in: Capsule())
        }
    }

    // MARK: - Action button

    @ViewBuilder
    private var actionRow: some View {
        let status = store.editSuggestionsRequestStatus[asset.id] ?? .idle
        let hasResult = asset.editSuggestions != nil
        let canTrigger = store.hasPremiumFallbackModel

        switch status {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在生成修图建议…")
                    .font(StitchTypography.font(size: 11, weight: .regular))
                    .foregroundStyle(Color(white: 0.65))
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("请求失败：\(message)")
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(LumaSemantic.reject)
                    .lineLimit(3)
                Button("重试") {
                    Task { await store.requestEditSuggestions(for: asset.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .lumaTrack("culling.ai_enhancement.retry", kind: "button")
            }
        case .idle, .completed:
            if hasResult {
                Button("重新生成修图建议") {
                    Task { await store.requestEditSuggestions(for: asset.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canTrigger)
                .help(canTrigger ? "再请求一次（会消耗一次费用）" : "未配置 premiumFallback 模型")
                .lumaTrack("culling.ai_enhancement.regenerate", kind: "button")
            } else {
                Button {
                    Task { await store.requestEditSuggestions(for: asset.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 11))
                        Text("生成修图建议")
                            .font(StitchTypography.font(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(StitchTheme.primary.opacity(canTrigger ? 0.85 : 0.35), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(!canTrigger)
                .help(canTrigger ? "请求 AI 修图建议（约 ~$0.02 / 张）" : "未配置 premiumFallback 模型，请去设置页添加")
                .lumaTrack("culling.ai_enhancement.generate", kind: "button")
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let suggestions = asset.editSuggestions {
            EditSuggestionsCard(suggestions: suggestions)
        }
    }
}
