import AppKit
import SwiftUI

/// macOS 上对根目录 `DESIGN.md`（Figma 营销站黑白铬 + 轻字重 + 等宽大写标签）的务实适配。
/// 结构层仍偏中性；**状态与语义**用 `LumaSemantic` 区分，避免全灰难以扫读。
enum DesignChrome {
    static let glassDark = Color.black.opacity(0.08)
    static let glassLight = Color.white.opacity(0.16)
    static let hairline = Color.primary.opacity(0.10)
    static let selectionFill = Color.primary.opacity(0.07)
    static let selectionStroke = Color.primary
    static let cardSurface = Color.secondary.opacity(0.06)
    static let imageWell = Color.secondary.opacity(0.10)
    /// 药丸/标签填充：随浅色/深色与标签色对齐（等价于「黑底白字 / 白底黑字」互换）
    static let inverseFill = Color(nsColor: .labelColor)
    /// 叠在 `inverseFill` 上的正文色
    static let inverseOnDark = Color(nsColor: .textBackgroundColor)
}

/// 中性铬小标签（如连拍条内 `#1` 序号）；**语义状态**请用 `SemanticCapsuleBadge` + `LumaSemantic`。
struct DesignChromeBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(DesignChrome.inverseOnDark)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(DesignChrome.inverseFill, in: Capsule())
    }
}

/// 业务状态色（顶栏统计、侧栏进度、详情评分、网格角标等共用）。
enum LumaSemantic {
    static let pick = Color.green
    static let reject = Color.red
    static let recommend = Color.blue
    /// 待定 / 中性提醒
    static let pending = Color.orange
    static let burst = Color.orange
    static let ai = Color.blue
    /// 「最佳」连拍：高识别琥珀色
    static let best = Color(red: 0.93, green: 0.62, blue: 0.08)
    static let issue = Color.red
    /// 评星控件弱提示
    static let rating = Color.yellow
}

/// 彩色胶囊标签（白字 + 饱和底），用于 AI / 连拍 / 问题等一眼可辨。
struct SemanticCapsuleBadge: View {
    let text: String
    let fill: Color
    var foreground: Color = .white
    /// 连拍条小图等更紧凑的角标
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? 7 : 8)
            .padding(.vertical, compact ? 4 : 5)
            .background(fill.opacity(0.92), in: Capsule())
    }
}

enum DesignType {
    /// Mono label：小号大写 + 正字距（对应 DESIGN.md figmaMono section label）
    static func sectionLabel() -> Font {
        .system(size: 11, weight: .medium, design: .monospaced)
    }

    static let sectionTracking: CGFloat = 0.55
    static let titleKerning: CGFloat = -0.22
    static let bodyKerning: CGFloat = -0.14
}
