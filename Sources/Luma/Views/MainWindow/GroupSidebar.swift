import SwiftUI

struct GroupSidebar: View {
    @Bindable var store: ProjectStore

    init(store: ProjectStore) {
        self.store = store
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            sidebarBackground
                .ignoresSafeArea()

            ScrollView {
                // VStack：分组数量通常有限，避免 LazyVStack 与 Button 组合时偶发命中区域异常
                VStack(alignment: .leading, spacing: 0) {
                    sidebarSectionHeader(
                        title: "总览",
                        detail: "\(store.assets.count) 张"
                    )

                    sidebarButton(isSelected: store.selectedGroupID == nil) {
                        store.selectGroup(nil)
                    } label: {
                        overviewRow(
                            summary: store.summary(for: nil),
                            isSelected: store.selectedGroupID == nil,
                            showBottomDivider: true
                        )
                    }

                    if !store.groups.isEmpty {
                        sidebarSectionHeader(
                            title: "分组",
                            detail: "\(store.groups.count) 组",
                            topPadding: 14
                        )

                        ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                            let isLastGroup = index == store.groups.count - 1
                            sidebarButton(isSelected: store.selectedGroupID == group.id) {
                                store.selectGroup(group.id)
                            } label: {
                                groupRow(
                                    index: index + 1,
                                    title: group.name,
                                    summary: store.summary(for: group),
                                    isSelected: store.selectedGroupID == group.id,
                                    showBottomDivider: !isLastGroup
                                )
                            }
                        }
                    } else {
                        emptyGroupsState
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackground)
        // 与 HSplitView 自带分隔条重复；叠加时易出现双线，且 Divider 默认命中区域可能吃掉靠右的点击
    }

    private func overviewRow(
        summary: GroupDecisionSummary,
        isSelected: Bool,
        showBottomDivider: Bool
    ) -> some View {
        sidebarRow(isSelected: isSelected, verticalPadding: 14, showBottomDivider: showBottomDivider) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    Text("全部照片")
                        .font(.subheadline.weight(.medium))
                        .kerning(DesignType.titleKerning)
                    Spacer()
                    Text("\(summary.total)")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text("推荐 \(summary.recommended) · 已选 \(summary.picked) · 待定 \(summary.pending)")
                    .font(.caption.weight(.light))
                    .foregroundStyle(.secondary)
                    .kerning(DesignType.bodyKerning)

                GroupProgressBar(summary: summary)
            }
        }
    }

    private func groupRow(
        index: Int,
        title: String,
        summary: GroupDecisionSummary,
        isSelected: Bool,
        showBottomDivider: Bool
    ) -> some View {
        sidebarRow(isSelected: isSelected, verticalPadding: 12, showBottomDivider: showBottomDivider) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%02d", index))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        .frame(width: 22, alignment: .leading)

                    Text(title)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .kerning(DesignType.titleKerning)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(title)

                    Spacer(minLength: 0)
                }

                Text("共 \(summary.total) 张 · 推荐 \(summary.recommended) · 已选 \(summary.picked)")
                    .font(.caption.weight(.light))
                    .foregroundStyle(.secondary)
                    .kerning(DesignType.bodyKerning)

                GroupProgressBar(summary: summary)
            }
        }
    }

    private var emptyGroupsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.title2)
                .foregroundStyle(.quaternary)

            VStack(spacing: 4) {
                Text("暂无分组")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("导入完成后自动按时间和地点聚合。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 20)
    }

    private func sidebarSectionHeader(title: String, detail: String, topPadding: CGFloat = 0) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased())
                .font(DesignType.sectionLabel())
                .tracking(DesignType.sectionTracking)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(detail)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(.quaternary)
        }
        .padding(.top, topPadding)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarButton<Label: View>(
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sidebarBackground)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func sidebarRow<Content: View>(
        isSelected: Bool,
        verticalPadding: CGFloat,
        showBottomDivider: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)

                if isSelected {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: 3)
                }

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, verticalPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())

            if showBottomDivider {
                Divider()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .stitchUnselectedHoverWash(isSelected: isSelected)
    }

    private var sidebarBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }
}

private struct GroupProgressBar: View {
    let summary: GroupDecisionSummary

    var body: some View {
        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let radius = min(size.height, 4.0)
            let bgPath = Path(roundedRect: bounds, cornerRadius: radius)
            context.fill(bgPath, with: .color(.secondary.opacity(0.12)))

            let segments: [(Double, Color)] = [
                (summary.pickedFraction, LumaSemantic.pick),
                (summary.pendingFraction, Color.gray.opacity(0.42)),
                (summary.rejectedFraction, LumaSemantic.reject.opacity(0.92)),
            ]

            var originX = bounds.minX
            for (fraction, color) in segments where fraction > 0 {
                let width = bounds.width * fraction
                let segmentRect = CGRect(x: originX, y: bounds.minY, width: width, height: bounds.height)
                context.fill(Path(roundedRect: segmentRect, cornerRadius: radius), with: .color(color))
                originX += width
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
    }
}
