import AppKit
import Foundation

/// 在「系统设置」中打开与照片相关的隐私项（多版本回退，适应系统路径变更）。
enum SystemPrivacyURL {
    private static let candidates: [String] = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Photos",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
    ]

    @MainActor
    static func openPhotoLibraryPrivacySettings() {
        for raw in Self.candidates {
            guard let url = URL(string: raw), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }
}
