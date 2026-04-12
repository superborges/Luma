import SwiftUI

struct ExportHubView: View {
    @Bindable var store: ProjectStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                ContentUnavailableView(
                    "导出与交付",
                    systemImage: "square.and.arrow.up",
                    description: Text("使用工具栏「导出选中」或打开导出面板；导出记录保存在当前远征。")
                )
                .frame(minHeight: 160)

                if let jobs = store.currentExpedition?.exportJobs, !jobs.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("最近导出")
                            .font(.headline.weight(.medium))
                        ForEach(jobs.suffix(8).reversed()) { job in
                            HStack {
                                Text(job.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(job.status.rawValue)
                                    .font(.caption.monospaced())
                                Spacer()
                                Text("\(job.exportedCount)/\(job.totalCount)")
                                    .font(.caption.monospacedDigit())
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .stitchAdaptiveListRowHover()
                        }
                    }
                    .padding(AppSpacing.gutter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.cardOuter, style: .continuous))
                }

                Button("打开导出面板") {
                    store.openExportPanel()
                }
                .buttonStyle(.borderedProminent)
                .stitchHoverDimming()
                .disabled(store.assets.isEmpty || store.pickedAssetsCount == 0)
            }
            .padding(AppSpacing.gutter)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
