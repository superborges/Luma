import SwiftUI

struct LumaCommands: Commands {
    let store: ProjectStore

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("项目库") {
                store.openProjectLibrary()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("性能诊断") {
                store.openPerformanceDiagnostics()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("导入文件夹") {
                Task { await store.importFolder() }
            }
            .keyboardShortcut("i", modifiers: [.command])

            Button("导入 SD 卡") {
                Task { await store.importSDCard() }
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("导入 iPhone") {
                Task { await store.importIPhone() }
            }
            .keyboardShortcut("i", modifiers: [.command, .option])

            if store.recoverableImportSession != nil {
                Button("继续导入") {
                    Task { await store.resumeRecoverableImport() }
                }
            }

            Button("导出选中") {
                store.openExportPanel()
            }
            .keyboardShortcut("e", modifiers: [.command])
        }

        CommandMenu("Luma") {
            Button("标记选中") {
                store.markSelection(.picked)
            }
            .keyboardShortcut("p", modifiers: [])

            Button("标记拒绝") {
                store.markSelection(.rejected)
            }
            .keyboardShortcut("x", modifiers: [])

            Button("恢复待定") {
                store.clearSelectionDecision()
            }
            .keyboardShortcut("u", modifiers: [])

            Button("切换预览") {
                store.toggleDisplayMode()
            }
            .keyboardShortcut(.space, modifiers: [])

            Button("上一张") {
                store.moveSelection(by: -1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button("下一张") {
                store.moveSelection(by: 1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Button("跳到下一组") {
                store.jumpToNextGroup()
            }
            .keyboardShortcut(.tab, modifiers: [])

            Button("选中推荐照片") {
                store.selectRecommendedInCurrentScope()
            }
            .keyboardShortcut("a", modifiers: [.command])
        }

        CommandMenu("评分") {
            ForEach(1...5, id: \.self) { rating in
                Button("\(rating) 星") {
                    store.rateSelection(rating)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(rating)")), modifiers: [])
            }
        }
    }
}
