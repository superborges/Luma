import SwiftUI

// MARK: - Spacing / radius tokens（与 Artifacts/ui-regions.md 配套，便于颗粒度对齐）

enum AppSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 10
    static let xl: CGFloat = 12
    static let xxl: CGFloat = 16
    static let section: CGFloat = 18
    static let gutter: CGFloat = 20
}

/// 与 DESIGN.md「Comfortable 8px / 小容器 6px」对齐；外层容器略大以免过于锋利。
enum AppRadius {
    static let chip: CGFloat = 8
    static let chipOuter: CGFloat = 12
    static let card: CGFloat = 8
    static let cardOuter: CGFloat = 12
    static let strip: CGFloat = 12
    static let toolbar: CGFloat = 50
}

// MARK: - 稳定区域 ID（对话、注释、日志里引用，不耦合布局逻辑）

enum UILayoutRegion {
    enum Main {
        static let toolbar = "main.toolbar"
        static let statusBar = "main.statusBar"
        static let sidebar = "main.sidebar"
        static let workspace = "main.workspace"
        static let detail = "main.detail"
    }

    enum Sidebar {
        static let sectionHeader = "main.sidebar.sectionHeader"
        static let overview = "main.sidebar.overview"
        static let groupRow = "main.sidebar.groupRow"
        static let empty = "main.sidebar.empty"
    }

    enum Workspace {
        static let grid = "main.workspace.grid"
        static let gridCell = "main.workspace.grid.cell"
        static let burstGrid = "main.workspace.burst.grid"
        static let burstCell = "main.workspace.burst.cell"
        static let burstStrip = "main.workspace.burst.strip"
        static let burstChip = "main.workspace.burst.chip"
        static let single = "main.workspace.single"
        static let singleStage = "main.workspace.single.stage"
        static let singleChrome = "main.workspace.single.chrome"
        static let floatingToolbar = "main.workspace.floatingToolbar"
    }

    enum Detail {
        static let panel = "main.detail"
        static let header = "main.detail.header"
        static let burst = "main.detail.burst"
        static let score = "main.detail.score"
        static let issues = "main.detail.issues"
        static let meta = "main.detail.meta"
    }

    enum Sheet {
        static let export = "sheet.export"
        static let library = "sheet.library"
        static let diagnostics = "sheet.diagnostics"
    }

    enum Overlay {
        static let importProgress = "overlay.import"
    }
}
