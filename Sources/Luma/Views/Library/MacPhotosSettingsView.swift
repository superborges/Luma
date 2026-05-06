import SwiftUI

struct MacPhotosSettingsView: View {
    @Bindable var store: LibraryStore
    @State private var isConnecting = false
    @State private var connectError: String?
    @State private var showDisconnectConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    if store.macPhotosConnected {
                        connectedCard
                    } else {
                        disconnectedCard
                    }
                }
                .padding(32)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(StitchTheme.background)
        .alert("断开 Mac Photos", isPresented: $showDisconnectConfirm) {
            Button("断开", role: .destructive) {
                store.disconnectMacPhotos()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("断开后不会删除已索引的数据，但 Mac Photos 入口将不再可用。")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "photo.badge.checkmark")
                .font(.system(size: 22))
                .foregroundStyle(.blue)
            Text("Mac Photos")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(StitchTheme.onSurface)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var disconnectedCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 52))
                .foregroundStyle(Color(white: 0.3))

            VStack(spacing: 8) {
                Text("连接 Mac 照片图库")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(StitchTheme.onSurface)
                Text("授权后，Luma 将索引你的照片图库，无需复制原图即可浏览和选片。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            if let error = connectError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            Button(action: {
                isConnecting = true
                connectError = nil
                Task {
                    do {
                        try await store.connectMacPhotos()
                    } catch {
                        connectError = error.localizedDescription
                    }
                    isConnecting = false
                }
            }) {
                HStack(spacing: 8) {
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    }
                    Text(isConnecting ? "正在连接…" : "连接 Mac Photos")
                }
                .frame(minWidth: 160)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isConnecting)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(StitchTheme.surfaceContainerLow)
        .cornerRadius(12)
    }

    private var connectedCard: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("已连接")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StitchTheme.onSurface)
                    Text("Mac 照片图库")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            VStack(spacing: 12) {
                statusRow(label: "已索引照片", value: "\(store.macPhotosTotalCount) 张")

                if let date = store.macPhotosLastSync {
                    statusRow(label: "最近同步", value: DateFormatter.lumaRelative.string(from: date))
                }

                if let progress = store.macPhotosIndexProgress, !progress.isComplete {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("索引中…")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(progress.indexed)/\(progress.total)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(progress.indexed), total: Double(max(progress.total, 1)))
                            .tint(.blue)
                    }
                }

                statusRow(
                    label: "授权状态",
                    value: authStatusText(store.macPhotosAuthStatus)
                )
            }

            Divider()

            HStack(spacing: 12) {
                Button("更新索引") {
                    Task { await store.refreshMacPhotosIndex() }
                }
                .disabled(store.macPhotosIsIndexing)

                Spacer()

                Button("断开连接", role: .destructive) {
                    showDisconnectConfirm = true
                }
                .foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(StitchTheme.surfaceContainerLow)
        .cornerRadius(12)
    }

    private func statusRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(StitchTheme.onSurface)
        }
    }

    private func authStatusText(_ status: PhotoAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "完全授权"
        case .limited: return "有限授权"
        case .denied: return "已拒绝"
        case .restricted: return "受限"
        case .notDetermined: return "未请求"
        }
    }
}

private extension DateFormatter {
    static let lumaRelative: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()
}
