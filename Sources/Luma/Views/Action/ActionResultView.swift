import AppKit
import SwiftUI

struct ActionResultView: View {
    @Bindable var store: LibraryStore
    let result: ExportResult

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    metricsRow
                    if let url = result.destinationURL {
                        infoLine(label: "输出目录", value: url.path, icon: "folder")
                    } else {
                        infoLine(label: "目标", value: result.destinationDescription, icon: "square.and.arrow.up")
                    }
                    if !result.failures.isEmpty {
                        failuresSection
                    }
                }
                .padding(20)
            }
            Divider()
            actionBar
        }
        .frame(minWidth: 520, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: result.failures.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(result.failures.isEmpty ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.failures.isEmpty ? "操作完成" : "操作完成（含失败项）")
                    .font(.title3.weight(.semibold))
                Text("成功 \(result.exportedCount)" + (result.failures.isEmpty ? "" : " · 失败 \(result.failures.count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var metricsRow: some View {
        HStack(spacing: 12) {
            metricCard(title: "成功", value: "\(result.exportedCount)", tint: .green, icon: "checkmark.circle.fill")
            if !result.failures.isEmpty {
                metricCard(title: "失败", value: "\(result.failures.count)", tint: .orange, icon: "xmark.octagon")
            }
            if result.skippedCount > 0 {
                metricCard(title: "跳过", value: "\(result.skippedCount)", tint: .gray, icon: "forward.end")
            }
        }
    }

    private func metricCard(title: String, value: String, tint: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title.monospacedDigit().weight(.semibold))
                .foregroundStyle(tint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infoLine(label: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
    }

    private var failuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("失败明细")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(result.failures.count) 项")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(result.failures.prefix(20)) { failure in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(failure.fileName)
                                .font(.callout.weight(.medium))
                            Text(failure.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    Divider().opacity(0.4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            if let url = result.destinationURL {
                Button {
                    store.revealInFinder(url: url)
                } label: {
                    Label("在访达中显示", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button("完成") {
                store.dismissActionResult()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
