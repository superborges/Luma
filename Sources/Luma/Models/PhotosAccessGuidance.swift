import Foundation

/// 照片库权限或导入争用说明；由主窗口用 SwiftUI `alert` 展示（避免 NSAlert 与暗色主界面不一致）。
enum PhotosAccessGuidance: String, Hashable, Identifiable, Sendable {
    case accessDenied
    /// 用户可能只给「添加照片」、未给读图库；`readWrite` 为 denied 时常见。
    case needFullLibraryRead
    case importInProgress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessDenied: return "需要照片图库访问权限"
        case .needFullLibraryRead: return "需要「读图库」而不仅是添加"
        case .importInProgress: return "请等待当前导入完成"
        }
    }

    var message: String {
        switch self {
        case .accessDenied:
            // 裸二进制 + ad-hoc 重签：TCC 常仍显示 denied，与「系统设置里已开」表观矛盾（见 run-luma.sh 注释）。
            return """
            情况 A：第一次用「从照片导入」时，应由系统弹窗，点「允许」。

            情况 B：你已在系统设置里为 Luma 打开访问，**这里仍失败**时，常见原因是：用 `swift build` 直接跑 **`.build/.../Luma` 裸可执行**；每次重编译为 **ad-hoc 临时签名**会变，TCC 仍绑定**旧可执行/旧 .app**，接口里会一直是 **denied**。

            建议：用项目里 `scripts/run-luma.sh` 启动（会打成 **Luma.app** 并签名）。若已混乱，在终端先执行 `tccutil reset Photos app.luma.Luma`，再 **⌘Q 退出** 后，用 `run-luma.sh` 打开、再点一次「从照片导入」按系统弹窗重新授权。下方按钮仍可调系统「照片」页。
            """
        case .needFullLibraryRead:
            return "系统对 Luma 的「读/访问」与「仅添加」是分开的。从「照片」里导入**必须**能浏览已有图库。请在系统设置中把 Luma 从「无 / 仅添加」改为可访问**所有照片**或完整读图库，然后完全退出 Luma（⌘Q）再开一次。下面按钮可跳转到该设置页。"
        case .importInProgress:
            return "已有导入任务在进行。完成后，你可以再从菜单选择「Mac · 照片 App」继续添加素材。"
        }
    }

    var shouldOfferSystemSettings: Bool {
        switch self {
        case .accessDenied, .needFullLibraryRead: return true
        case .importInProgress: return false
        }
    }
}
