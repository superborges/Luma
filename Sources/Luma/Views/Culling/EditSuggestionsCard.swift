import SwiftUI

/// 单张照片的修图建议可视化卡片。
///
/// 展示：
/// - 顶部：滤镜风格标签 + 参考字符串
/// - 裁切预览：长方形 outline + 比例 + 方向描述
/// - 关键调整滑块（不可拖动，仅展示数值）
/// - HSL 色块矩阵
/// - 局部建议 bullet
/// - 中文 narrative
struct EditSuggestionsCard: View {
    let suggestions: EditSuggestions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let filter = suggestions.filterStyle {
                filterRow(filter)
            }
            // 仅当模型显式标记 needed 时绘制裁切预览；否则避免误导（"以为要裁切"）。
            if let crop = suggestions.crop, crop.needed {
                cropPreview(crop)
            }
            if let adjustments = suggestions.adjustments {
                adjustmentsRows(adjustments)
            }
            if let hsl = suggestions.hslAdjustments, !hsl.isEmpty {
                hslMatrix(hsl)
            }
            if let local = suggestions.localEdits, !local.isEmpty {
                localEditsList(local)
            }
            if !suggestions.narrative.isEmpty {
                narrativeText(suggestions.narrative)
            }
        }
    }

    // MARK: - Filter style

    private func filterRow(_ filter: FilterSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "camera.filters")
                    .font(.system(size: 10))
                    .foregroundStyle(StitchTheme.outline)
                Text(filter.primary.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(StitchTypography.font(size: 11, weight: .semibold))
                    .foregroundStyle(Color(white: 0.92))
            }
            Text("\(filter.reference) · \(filter.mood)")
                .font(StitchTypography.font(size: 10, weight: .regular))
                .foregroundStyle(Color(white: 0.6))
        }
    }

    // MARK: - Crop preview

    private func cropPreview(_ crop: CropSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "crop")
                    .font(.system(size: 10))
                    .foregroundStyle(StitchTheme.outline)
                Text("裁切建议")
                    .font(StitchTypography.font(size: 10, weight: .semibold))
                    .foregroundStyle(StitchTheme.outline)
                    .textCase(.uppercase)
                    .tracking(0.6)
                Spacer()
                Text(crop.ratio)
                    .font(StitchTypography.font(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(white: 0.85))
            }
            // 缩略可视化：原图占位长方形 + 裁切框（按 top/bottom/left/right 0-1 百分比绘制）
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    // 原始边界
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                    // 裁切框
                    let left = CGFloat(crop.left ?? 0)
                    let top = CGFloat(crop.top ?? 0)
                    let right = CGFloat(crop.right ?? 1)
                    let bottom = CGFloat(crop.bottom ?? 1)
                    let cropW = max(0, right - left) * geo.size.width
                    let cropH = max(0, bottom - top) * geo.size.height
                    let cropX = left * geo.size.width
                    let cropY = top * geo.size.height
                    Rectangle()
                        .stroke(StitchTheme.primary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: cropW, height: cropH)
                        .offset(x: cropX, y: cropY)
                }
            }
            .frame(height: 84)
            if !crop.direction.isEmpty {
                Text(crop.direction)
                    .font(StitchTypography.font(size: 10, weight: .regular))
                    .foregroundStyle(Color(white: 0.6))
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Adjustments

    private func adjustmentsRows(_ adj: AdjustmentValues) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("基础调整", iconName: "slider.horizontal.3")
            if let v = adj.exposure {
                adjustmentRow(label: "曝光", value: String(format: "%+.1f EV", v), normalized: v / 3.0)
            }
            if let v = adj.contrast {
                adjustmentRow(label: "对比度", value: signedString(v), normalized: Double(v) / 100.0)
            }
            if let v = adj.highlights {
                adjustmentRow(label: "高光", value: signedString(v), normalized: Double(v) / 100.0)
            }
            if let v = adj.shadows {
                adjustmentRow(label: "阴影", value: signedString(v), normalized: Double(v) / 100.0)
            }
            if let v = adj.temperature {
                adjustmentRow(label: "色温", value: signedString(v), normalized: Double(v) / 2000.0)
            }
            if let v = adj.saturation {
                adjustmentRow(label: "饱和度", value: signedString(v), normalized: Double(v) / 100.0)
            }
        }
    }

    /// 在 -1...1 区间画一个左/右偏移的小条；0 居中。
    private func adjustmentRow(label: String, value: String, normalized: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(StitchTypography.font(size: 10, weight: .medium))
                .foregroundStyle(StitchTheme.outline)
                .frame(width: 38, alignment: .trailing)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 3)
                    let clamped = min(max(normalized, -1), 1)
                    let mid = geo.size.width / 2
                    let barWidth = abs(CGFloat(clamped)) * mid
                    let barX = clamped >= 0 ? mid : (mid - barWidth)
                    Capsule()
                        .fill(clamped >= 0 ? StitchTheme.primary : LumaSemantic.reject)
                        .frame(width: barWidth, height: 3)
                        .offset(x: barX)
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 1, height: 6)
                        .offset(x: mid)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 10)
            Text(value)
                .font(StitchTypography.font(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color(white: 0.85))
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func signedString(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    // MARK: - HSL

    private func hslMatrix(_ adjustments: [HSLAdjustment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("HSL", iconName: "paintpalette")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(adjustments.enumerated()), id: \.offset) { _, h in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(hslSwatchColor(h.color))
                            .frame(width: 10, height: 10)
                        Text(h.color)
                            .font(StitchTypography.font(size: 10, weight: .regular))
                            .foregroundStyle(Color(white: 0.78))
                            .frame(width: 56, alignment: .leading)
                        if let hue = h.hue {
                            Text("H \(signedString(hue))").hslChip()
                        }
                        if let sat = h.saturation {
                            Text("S \(signedString(sat))").hslChip()
                        }
                        if let lum = h.luminance {
                            Text("L \(signedString(lum))").hslChip()
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private func hslSwatchColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "aqua", "cyan": return .cyan
        case "blue": return .blue
        case "purple", "violet": return .purple
        case "magenta", "pink": return .pink
        default: return Color(white: 0.5)
        }
    }

    // MARK: - Local edits

    private func localEditsList(_ edits: [LocalEdit]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("局部调整", iconName: "scribble")
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(edits.enumerated()), id: \.offset) { _, e in
                    HStack(alignment: .top, spacing: 6) {
                        Text("·")
                            .foregroundStyle(StitchTheme.outline)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.area)
                                .font(StitchTypography.font(size: 10, weight: .semibold))
                                .foregroundStyle(Color(white: 0.85))
                            Text(e.action)
                                .font(StitchTypography.font(size: 10, weight: .regular))
                                .foregroundStyle(Color(white: 0.65))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Narrative

    private func narrativeText(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeader("修图思路", iconName: "text.alignleft")
            Text(text)
                .font(StitchTypography.font(size: 11, weight: .regular))
                .foregroundStyle(Color(white: 0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, iconName: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 9))
                .foregroundStyle(StitchTheme.outline)
            Text(title)
                .font(StitchTypography.font(size: 10, weight: .semibold))
                .foregroundStyle(StitchTheme.outline)
                .textCase(.uppercase)
                .tracking(0.6)
        }
    }
}

private extension Text {
    func hslChip() -> some View {
        self.font(StitchTypography.font(size: 9, weight: .medium).monospacedDigit())
            .foregroundStyle(Color(white: 0.78))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 3))
    }
}
