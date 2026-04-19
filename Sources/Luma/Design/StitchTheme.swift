import SwiftUI

/// Material 3 tokens from Stitch screen `9bd72cc1` (tailwind `dark` theme).
enum StitchTheme {
    static let background = Color(red: 0.075, green: 0.075, blue: 0.075) // #131313 surface
    static let surfaceContainerLowest = Color(red: 0.055, green: 0.055, blue: 0.055) // #0e0e0e
    static let surfaceContainerLow = Color(red: 0.11, green: 0.106, blue: 0.106) // #1c1b1b
    static let surfaceContainerHigh = Color(red: 0.165, green: 0.165, blue: 0.165) // #2a2a2a
    static let surfaceContainerHighest = Color(red: 0.208, green: 0.208, blue: 0.204) // #353534
    static let onSurface = Color(red: 0.898, green: 0.886, blue: 0.882) // #e5e2e1
    static let outline = Color(red: 0.545, green: 0.565, blue: 0.627) // #8b90a0
    static let outlineVariant = Color(red: 0.255, green: 0.278, blue: 0.333) // #414755
    static let primary = Color(red: 0.678, green: 0.776, blue: 1.0) // #adc6ff
    static let primaryContainer = Color(red: 0.294, green: 0.557, blue: 1.0) // #4b8eff
    static let onPrimary = Color(red: 0.0, green: 0.18, blue: 0.412) // #002e69
    static let tertiary = Color(red: 1.0, green: 0.71, blue: 0.584) // #ffb595
    static let sidebarBackground = Color(red: 0.09, green: 0.09, blue: 0.09) // neutral-900 ~#171717
    static let sidebarActiveBackground = Color(white: 0.15).opacity(0.8) // neutral-800/80
    static let sidebarInactiveText = Color(red: 0.64, green: 0.64, blue: 0.64) // neutral-400
    static let sidebarActiveText = Color(red: 0.38, green: 0.65, blue: 0.98) // blue-400
    static let surface = Color(red: 0.075, green: 0.075, blue: 0.075) // #131313
    static let surfaceContainer = Color(red: 0.125, green: 0.122, blue: 0.122) // #201f1f
    static let surfaceVariant = Color(red: 0.208, green: 0.208, blue: 0.204) // #353534
    static let onSurfaceVariant = Color(red: 0.757, green: 0.776, blue: 0.843) // #c1c6d7
    static let onPrimaryContainer = Color(red: 0.0, green: 0.157, blue: 0.361) // #00285c
    static let topBarBackground = Color(red: 0.04, green: 0.04, blue: 0.04).opacity(0.8) // neutral-950/80
    static let glassCard = Color(red: 0.208, green: 0.208, blue: 0.204).opacity(0.7) // rgba(53,53,52,0.7)
}
