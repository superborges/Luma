import SwiftUI

struct DetailPanel: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        ScrollView {
            if let asset = store.selectedAsset {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(asset.baseName)
                            .font(.title3.weight(.semibold))
                        Text(asset.mediaType == .livePhoto ? "Live Photo" : "Photo")
                            .foregroundStyle(.secondary)
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
                .padding(20)
            } else {
                ContentUnavailableView(
                    "No Selection",
                    systemImage: "rectangle.and.hand.point.up.left",
                    description: Text("在中间网格中选择一张照片查看 EXIF 和 AI 信息。")
                )
                .padding()
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func burstSection(_ context: BurstSelectionContext) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BurstSet")
                .font(.headline)

            detailRow("组内位置", "\(context.burstIndex + 1) / \(context.burstCount)")
            detailRow("候选数量", "\(context.burst.count) 张")
            detailRow("当前照片", "\(context.assetIndex + 1) / \(context.burst.count)")

            if let bestAssetID = context.burst.bestAssetID,
               let bestAsset = context.burst.assets.first(where: { $0.id == bestAssetID }) {
                detailRow("优选照片", bestAsset.baseName)
            }
        }
    }

    private func scoreSection(_ score: AIScore) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI 评分")
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(score.overall)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                if score.recommended {
                    Text("推荐保留")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.92), in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            scoreBar("构图", value: score.scores.composition, color: .blue)
            scoreBar("曝光", value: score.scores.exposure, color: .orange)
            scoreBar("色彩", value: score.scores.color, color: .pink)
            scoreBar("锐度", value: score.scores.sharpness, color: .green)
            scoreBar("故事", value: score.scores.story, color: .purple)

            Text(score.comment)
                .foregroundStyle(.secondary)
        }
    }

    private func issueSection(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("质量提醒")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(asset.issues) { issue in
                    Text(issue.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.92), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
    }

    private func infoGrid(_ asset: MediaAsset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXIF")
                .font(.headline)

            detailRow("相机", asset.metadata.cameraModel ?? "Unknown")
            detailRow("镜头", asset.metadata.lensModel ?? "Unknown")
            detailRow("焦距", asset.metadata.focalLength.map { String(format: "%.0f mm", $0) } ?? "Unknown")
            detailRow("光圈", asset.metadata.aperture.map { String(format: "f/%.1f", $0) } ?? "Unknown")
            detailRow("快门", asset.metadata.shutterSpeed ?? "Unknown")
            detailRow("ISO", asset.metadata.iso.map(String.init) ?? "Unknown")
            detailRow("尺寸", asset.dimensionsDescription)
            detailRow("拍摄时间", detailDateFormatter.string(from: asset.metadata.captureDate))
            if let coordinate = asset.metadata.gpsCoordinate {
                detailRow("位置", String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
            }
        }
    }

    private func suggestionSection(_ suggestions: EditSuggestions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("修图建议")
                .font(.headline)

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

            Text(suggestions.narrative)
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
        .font(.callout)
    }

    private func scoreBar(_ title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(value), total: 100)
                .tint(color)
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
