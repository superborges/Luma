import SwiftUI

struct DetailPanel: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            if let asset = store.selectedAsset {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    if asset.mediaType != .photo {
                        Text(detailMediaTypeTitle(asset.mediaType))
                            .font(.title3.weight(.medium))
                            .kerning(DesignType.titleKerning)
                            .accessibilityLabel(Text("\(asset.baseName)，\(detailMediaTypeTitle(asset.mediaType))"))
                    }

                    if let burstContext = store.selectedBurstContext {
                        burstSection(burstContext)
                    }

                    if let score = asset.aiScore {
                        scoreSection(score)
                    }

                    if !asset.issues.isEmpty {
                        issueSection(asset)
                    }

                    if let suggestions = asset.editSuggestions {
                        suggestionSection(suggestions)
                    }

                    infoGrid(asset)
                }
                .padding(AppSpacing.gutter)
            } else {
                ContentUnavailableView(
                    "未选择",
                    systemImage: "rectangle.and.hand.point.up.left",
                    description: Text("在中间网格中选择一张照片查看 EXIF 和 AI 信息。")
                )
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func detailMediaTypeTitle(_ type: MediaType) -> String {
        switch type {
        case .photo:
            return "照片"
        case .livePhoto:
            return "实况照片"
        case .portrait:
            return "人像照片"
        }
    }

    private func burstSection(_ context: BurstSelectionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("连拍组", icon: "square.stack.3d.up")

            detailRow("组内位置", "\(context.burstIndex + 1) / \(context.burstCount)")
            detailRow("候选数量", "\(context.burst.count) 张")
            detailRow("当前照片", "\(context.assetIndex + 1) / \(context.burst.count)")

            if let bestAssetID = context.burst.bestAssetID,
               let bestIndex = context.burst.assets.firstIndex(where: { $0.id == bestAssetID }) {
                detailRow("优选", "第 \(bestIndex + 1) 张")
            }
        }
    }

    private func scoreSection(_ score: AIScore) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("AI 评分", icon: "sparkles")

            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.lg) {
                Text("\(score.overall)")
                    .font(.system(size: 42, weight: .medium, design: .rounded))
                    .foregroundStyle(scoreHue(score.overall))
                if score.recommended {
                    Text("推荐保留")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(LumaSemantic.recommend.opacity(0.92), in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            VStack(spacing: AppSpacing.md) {
                dimensionBar("构图", value: score.scores.composition, color: LumaSemantic.recommend)
                dimensionBar("曝光", value: score.scores.exposure, color: LumaSemantic.pending)
                dimensionBar("色彩", value: score.scores.color, color: .pink)
                dimensionBar("锐度", value: score.scores.sharpness, color: LumaSemantic.pick)
                dimensionBar("故事", value: score.scores.story, color: .purple)
            }

            Text(score.comment)
                .font(.callout.weight(.light))
                .foregroundStyle(.secondary)
                .kerning(DesignType.bodyKerning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func issueSection(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("质量提醒", icon: "exclamationmark.triangle")

            HStack(spacing: AppSpacing.md) {
                ForEach(asset.issues) { issue in
                    SemanticCapsuleBadge(text: issue.label, fill: LumaSemantic.issue)
                }
            }
        }
    }

    private func infoGrid(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("EXIF", icon: "camera")

            Divider().opacity(0.5)

            detailRow("相机", asset.metadata.cameraModel ?? "未知")
            detailRow("镜头", asset.metadata.lensModel ?? "未知")

            Divider().opacity(0.3)

            detailRow("焦距", asset.metadata.focalLength.map { String(format: "%.0f mm", $0) } ?? "未知")
            detailRow("光圈", asset.metadata.aperture.map { String(format: "f/%.1f", $0) } ?? "未知")
            detailRow("快门", asset.metadata.shutterSpeed ?? "未知")
            detailRow("ISO", asset.metadata.iso.map(String.init) ?? "未知")

            Divider().opacity(0.3)

            detailRow("尺寸", asset.dimensionsDescription)
            detailRow("拍摄", detailDateFormatter.string(from: asset.metadata.captureDate))
            if let coordinate = asset.metadata.gpsCoordinate {
                detailRow("位置", String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
            }
        }
    }

    private func suggestionSection(_ suggestions: EditSuggestions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("修图建议", icon: "slider.horizontal.3")

            VStack(alignment: .leading, spacing: 8) {
                if let filter = suggestions.filterStyle {
                    detailRow("风格", "\(filter.primary) · \(filter.reference)")
                    detailRow("氛围", filter.mood)
                }

                if let adjustments = suggestions.adjustments {
                    if let exposure = adjustments.exposure {
                        detailRow("曝光", String(format: "%+.2f EV", exposure))
                    }
                    if let contrast = adjustments.contrast {
                        detailRow("对比", String(format: "%+d", contrast))
                    }
                    if let highlights = adjustments.highlights {
                        detailRow("高光", String(format: "%+d", highlights))
                    }
                    if let shadows = adjustments.shadows {
                        detailRow("阴影", String(format: "%+d", shadows))
                    }
                }
            }
            .padding(AppRadius.chipOuter)
            .background(DesignChrome.cardSurface, in: RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

            Text(suggestions.narrative)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout.weight(.light))
        .kerning(DesignType.bodyKerning)
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.medium))
                .foregroundStyle(sectionIconTint(title))
            Text(title.uppercased())
                .font(DesignType.sectionLabel())
                .tracking(DesignType.sectionTracking)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionIconTint(_ title: String) -> Color {
        switch title {
        case "AI 评分": return LumaSemantic.ai
        case "质量提醒": return LumaSemantic.issue
        case "连拍组": return LumaSemantic.burst
        default: return Color.secondary.opacity(0.85)
        }
    }

    private func scoreHue(_ overall: Int) -> Color {
        if overall >= 80 { return LumaSemantic.pick }
        if overall >= 60 { return LumaSemantic.recommend }
        return LumaSemantic.pending
    }

    private func dimensionBar(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: AppSpacing.md) {
            Text(title)
                .font(.caption.weight(.light))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))

                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(0, geo.size.width * Double(value) / 100.0))
                }
            }
            .frame(height: 6)

            Text("\(value)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}

private let detailDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_Hans")
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}()
