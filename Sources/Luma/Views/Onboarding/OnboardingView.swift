import SwiftUI

/// 首启 onboarding：解释 Luma 一次完整流程 + 需要的系统权限。
/// 用户确认后写入 `UserDefaults("Luma.hasSeenOnboarding")`，永久不再显示（除非升级时调高 minVersion 重置）。
struct OnboardingView: View {
    @AppStorage("Luma.hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    flowSection
                    permissionsSection
                    safetySection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 560, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("欢迎使用 Luma")
                    .font(.title2.weight(.semibold))
                Text("一次完整的「导入 → 选片 → 导出」体验")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var flowSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Luma 是怎么工作的")
                .font(.headline)
            stepLine(index: 1, title: "新建 Import Session", detail: "从普通目录、SD 卡、Mac 照片 App、iPhone（USB）中选一个来源开始。")
            stepLine(index: 2, title: "选片", detail: "本地启发式打分 + 连拍择优 + Pick / Reject / 评星。可随时关闭，状态会自动保存。")
            stepLine(index: 3, title: "导出", detail: "支持文件夹 / Lightroom / Mac 照片 App。Photos 路径下可选「同时清理源相册」（系统会再确认）。")
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("会用到的系统权限")
                .font(.headline)
            permissionLine(icon: "photo.on.rectangle.angled", title: "照片库", detail: "读取本地缓存、写入相册、按你确认后删除原图。")
            permissionLine(icon: "iphone", title: "iPhone（USB）", detail: "通过 ImageCapture 读取相机胶卷，需要先解锁手机并选择「信任此电脑」。")
            permissionLine(icon: "folder", title: "文件夹访问", detail: "用 macOS 文件选择器，每次自己点的目录都会被授权。")
        }
    }

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("不会自动做的事")
                .font(.headline)
            bullet("永远不会绕过系统的「删除照片」原生确认弹窗。")
            bullet("不会自动从 iCloud 拉原图，除非你导出阶段明确需要。")
            bullet("不会上传任何 trace 或诊断数据；如需排障请手动发日志。")
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button {
                hasSeenOnboarding = true
                onDismiss()
            } label: {
                Text("开始使用")
                    .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func stepLine(index: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func permissionLine(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}
