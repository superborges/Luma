import SwiftUI

/// 选片工作区顶部的细线评分进度条 + 状态行。
///
/// 设计取舍：默认折叠为单行（progress bar + 数字 + 美元 + 暂停按钮）；不引入展开折叠动画，
/// 避免视觉干扰。空闲状态完全隐藏（`store.cloudScoringStatus == .idle && progress == nil`）。
struct ScoringProgressBar: View {
    @Bindable var store: ProjectStore

    var body: some View {
        if shouldShow {
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(red: 0.06, green: 0.06, blue: 0.06))
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(height: 1),
                    alignment: .top
                )
        }
    }

    private var shouldShow: Bool {
        // 仅在评分跑过 / 正在跑 / 失败 / 暂停时展示
        switch store.cloudScoringStatus {
        case .idle: return false
        case .running, .paused, .failed, .completed: return store.cloudScoringProgress != nil
        }
    }

    @ViewBuilder
    private var content: some View {
        let progress = store.cloudScoringProgress
        let total = progress?.totalGroups ?? 0
        let completed = progress?.completedGroups ?? 0
        let failed = progress?.failedGroups ?? 0
        let fraction = progress?.progressFraction ?? 0

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                statusDot
                Text(statusTitle)
                    .font(StitchTypography.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.85))
                if let modelName = progress?.currentModelDisplayName {
                    Text("· \(modelName)")
                        .font(StitchTypography.font(size: 11, weight: .regular))
                        .foregroundStyle(Color(white: 0.55))
                }
                Spacer(minLength: 0)
                Text("\(completed) / \(total)")
                    .font(StitchTypography.font(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(white: 0.85))
                if failed > 0 {
                    Text("· 失败 \(failed)")
                        .font(StitchTypography.font(size: 11, weight: .regular))
                        .foregroundStyle(LumaSemantic.reject)
                }
                if let budget = progress?.budget {
                    Text("· \(budget.prettyUSD)")
                        .font(StitchTypography.font(size: 11, weight: .regular).monospacedDigit())
                        .foregroundStyle(Color(white: 0.65))
                }
                actionButton
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(progressTint)
                .frame(height: 4)

            if let message = progress?.message ?? store.cloudScoringErrorMessage, !message.isEmpty {
                Text(message)
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(Color(white: 0.55))
                    .lineLimit(1)
            }
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(progressTint)
            .frame(width: 7, height: 7)
    }

    private var statusTitle: String {
        switch store.cloudScoringStatus {
        case .idle: return "AI 评分"
        case .running: return "云端评分中"
        case .paused: return "已暂停"
        case .completed: return "评分完成"
        case .failed: return "评分失败"
        }
    }

    private var progressTint: Color {
        switch store.cloudScoringStatus {
        case .running: return StitchTheme.primary
        case .completed: return LumaSemantic.pick
        case .failed: return LumaSemantic.reject
        case .paused: return Color(white: 0.55)
        case .idle: return Color(white: 0.55)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch store.cloudScoringStatus {
        case .running:
            Button("暂停") {
                store.cancelCloudScoring()
            }
            .buttonStyle(.plain)
            .font(StitchTypography.font(size: 11, weight: .semibold))
            .foregroundStyle(Color(white: 0.85))
            .lumaTrack("culling.scoring.pause", kind: "button")
        case .paused, .failed:
            Button("继续") {
                Task { await store.startCloudScoring(strategy: store.scoringStrategy) }
            }
            .buttonStyle(.plain)
            .font(StitchTypography.font(size: 11, weight: .semibold))
            .foregroundStyle(StitchTheme.primary)
            .lumaTrack("culling.scoring.resume", kind: "button")
        default:
            EmptyView()
        }
    }
}
