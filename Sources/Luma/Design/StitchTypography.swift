import AppKit
import SwiftUI

/// Typography tokens from Stitch `9bd72cc1` (Inter + Tailwind scale). Uses Inter when installed, else San Francisco with matching point sizes.
enum StitchTypography {
    private static func interAvailable(size: CGFloat) -> Bool {
        NSFont(name: "Inter", size: size) != nil
            || NSFont(name: "Inter-Regular", size: size) != nil
    }

    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if interAvailable(size: size) {
            return .custom("Inter", size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    // Tailwind mapping from 9bd72cc1
    static let libraryTitle = font(size: 30, weight: .heavy) // text-3xl font-extrabold
    static let librarySubtitle = font(size: 14, weight: .regular) // text-sm text-outline
    static let sectionHeading = font(size: 14, weight: .bold) // text-sm font-bold uppercase
    static let viewAllLink = font(size: 12, weight: .medium) // text-xs font-medium
    static let newSessionLabel = font(size: 14, weight: .bold) // text-sm font-bold
    static let newSessionIcon: CGFloat = 14 // material text-sm
    static let featuredTitle = font(size: 24, weight: .bold) // text-2xl font-bold
    static let latestSyncBadge = font(size: 10, weight: .bold) // text-[10px] font-bold
    static let featuredMeta = font(size: 14, weight: .regular) // text-sm
    static let secondaryTitle = font(size: 14, weight: .bold) // text-sm font-bold
    static let secondaryMeta = font(size: 10, weight: .regular) // text-[10px]
    static let listRowTitle = font(size: 14, weight: .semibold) // text-sm font-semibold
    static let listRowMeta = font(size: 10, weight: .regular) // text-[10px] uppercase
    static let listRawMono = mono(size: 12, weight: .regular) // text-xs font-mono
    static let listSecondaryLine = font(size: 10, weight: .regular)
    static let archiveRowLabel = font(size: 12, weight: .medium) // text-xs font-medium
    static let archiveMono = mono(size: 12, weight: .regular)
    static let vaultHeading = font(size: 12, weight: .bold) // text-xs font-bold
    static let vaultBody = font(size: 10, weight: .regular) // text-[10px]
    static let integrityButton = font(size: 12, weight: .bold) // text-xs font-bold
    static let archiveHealthCaption = font(size: 10, weight: .bold)
    static let archiveHealthValue = font(size: 12, weight: .semibold) // text-xs font-semibold
    static let searchField = font(size: 14, weight: .regular)

    /// `tracking-[0.2em]` on 14px section labels
    static let sectionHeadingTracking: CGFloat = 2.8
}
