import SwiftUI

struct AIScoreCardView: View {
    let aiScore: AIScore?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(StitchTheme.outline)
                Text("AI 评分")
                    .font(StitchTypography.font(size: 11, weight: .bold))
                    .foregroundStyle(StitchTheme.onSurface)
                    .textCase(.uppercase)
                    .tracking(0.8)
                if let badge = sourceBadge(aiScore) {
                    badge
                }
            }

            if let score = aiScore {
                scoreContent(score)
            } else {
                Text("暂无评分")
                    .font(StitchTypography.font(size: 11, weight: .regular))
                    .foregroundStyle(StitchTheme.outline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private func scoreContent(_ score: AIScore) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(score.overall)")
                .font(.system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(overallColor(score.overall))
            if score.recommended {
                Text("推荐")
                    .font(StitchTypography.font(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue, in: Capsule())
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            dimensionBar(label: "构图", value: score.scores.composition)
            dimensionBar(label: "曝光", value: score.scores.exposure)
            dimensionBar(label: "色彩", value: score.scores.color)
            dimensionBar(label: "锐度", value: score.scores.sharpness)
            dimensionBar(label: "故事", value: score.scores.story)
        }

        if !score.comment.isEmpty {
            Text(score.comment)
                .font(StitchTypography.font(size: 10, weight: .regular))
                .foregroundStyle(StitchTheme.onSurfaceVariant)
                .lineLimit(3)
        }
    }

    private func dimensionBar(label: String, value: Int) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(StitchTypography.font(size: 10, weight: .medium))
                .foregroundStyle(StitchTheme.outline)
                .frame(width: 28, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)
                    Capsule()
                        .fill(overallColor(value))
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100)) / 100.0, height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 12)
            Text("\(value)")
                .font(StitchTypography.font(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(StitchTheme.outline)
                .frame(width: 22, alignment: .trailing)
        }
    }

    private func overallColor(_ value: Int) -> Color {
        switch value {
        case 70...: return .green
        case 40..<70: return .yellow
        default: return .red
        }
    }

    /// 评分来源角标。约定：云端模型 provider 字符串以 `cloud:` 开头；其余视为本地。
    private func sourceBadge(_ score: AIScore?) -> AnyView? {
        guard let score else { return nil }
        let isCloud = score.provider.hasPrefix("cloud:")
        let label = isCloud ? "云端" : "本地"
        let color: Color = isCloud ? StitchTheme.primary : Color(white: 0.45)
        let view = HStack(spacing: 3) {
            Image(systemName: isCloud ? "cloud.fill" : "cpu")
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(StitchTypography.font(size: 8, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.85), in: Capsule())
        return AnyView(view)
    }
}
