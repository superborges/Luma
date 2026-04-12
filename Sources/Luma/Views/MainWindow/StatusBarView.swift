import SwiftUI

struct StatusBarView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xxl) {
                Text(store.projectName)
                    .font(.headline.weight(.medium))
                    .kerning(DesignType.titleKerning)

                HStack(spacing: AppSpacing.xs) {
                    Text("\(store.assets.count)")
                        .font(.callout.monospacedDigit().weight(.medium))
                    Text("张")
                        .font(.caption.weight(.light))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.quaternary)
                    Text("\(store.groups.count)")
                        .font(.callout.monospacedDigit().weight(.medium))
                    Text("组")
                        .font(.caption.weight(.light))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 14)

                statusPill("已选", value: store.pickedCount, tint: LumaSemantic.pick)
                statusPill("待定", value: store.pendingCount, tint: LumaSemantic.pending)
                statusPill("拒绝", value: store.rejectedCount, tint: LumaSemantic.reject)
                statusPill("推荐", value: store.recommendedCount, tint: LumaSemantic.recommend)

                Spacer()

                if store.isLocalScoring {
                    HStack(spacing: 5) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("本地评估 \(store.localScoringCompleted)/\(store.localScoringTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if store.isCloudScoring {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundStyle(LumaSemantic.ai)
                        Text("AI 评分中 \(store.cloudScoringCompleted)/\(store.cloudScoringTotal)")
                            .font(.caption.weight(.light))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if store.importProgress?.phase == .paused {
                    Text("导入已暂停")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if store.costTracker.totalCost > 0 {
                    Text(String(format: "已花费 $%.2f", store.costTracker.totalCost))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if store.isLocalScoring {
                ProgressView(value: store.localScoringFraction)
                    .progressViewStyle(.linear)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }

            if store.isCloudScoring {
                ProgressView(value: store.cloudScoringFraction)
                    .progressViewStyle(.linear)
                    .tint(LumaSemantic.ai)
                    .frame(height: 3)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, AppSpacing.section)
        .padding(.vertical, AppSpacing.lg)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func statusPill(_ title: String, value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint.opacity(0.9))
                .frame(width: 6, height: 6)
            Text("\(title) \(value)")
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .kerning(DesignType.bodyKerning)
        }
    }
}
