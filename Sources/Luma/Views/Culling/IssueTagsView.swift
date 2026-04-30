import SwiftUI

struct IssueTagsView: View {
    let issues: [AssetIssue]

    var body: some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(StitchTheme.outline)
                    Text("废片标签")
                        .font(StitchTypography.font(size: 11, weight: .bold))
                        .foregroundStyle(StitchTheme.onSurface)
                        .textCase(.uppercase)
                        .tracking(0.8)
                }

                FlowLayout(spacing: 6) {
                    ForEach(issues) { issue in
                        Text(issue.label)
                            .font(StitchTypography.font(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tagColor(for: issue), in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func tagColor(for issue: AssetIssue) -> Color {
        switch issue {
        case .blurry, .eyesClosed:
            return .red.opacity(0.8)
        case .overexposed, .underexposed, .unsupportedFormat:
            return .orange.opacity(0.8)
        }
    }
}

/// 自适应换行布局：子元素超出行宽时自动换行。
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            height += row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[Int]] = [[]]
        var currentWidth: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(index)
            currentWidth += size.width + spacing
        }
        return rows
    }
}
