import XCTest
@testable import Luma

@MainActor
final class ProjectStoreTests: XCTestCase {
    func testSelectionFlowUpdatesVisibleAssets() {
        let store = ProjectStore()
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_1001",
            captureDate: TestFixtures.makeDate(hour: 9),
            aiScore: TestFixtures.makeAIScore(overall: 80)
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_1002",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 1),
            aiScore: TestFixtures.makeAIScore(overall: 82)
        )
        let asset3 = TestFixtures.makeAsset(
            baseName: "IMG_1003",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 2),
            aiScore: TestFixtures.makeAIScore(overall: 78)
        )
        let groupA = TestFixtures.makeGroup(name: "Group A", assets: [asset1, asset2])
        let groupB = TestFixtures.makeGroup(name: "Group B", assets: [asset3])

        TestFixtures.seedStore(store, assets: [asset1, asset2, asset3], groups: [groupA, groupB])
        store.selectedAssetID = asset3.id

        store.selectGroup(groupA.id)

        XCTAssertEqual(store.selectedGroupID, groupA.id)
        XCTAssertEqual(store.visibleAssets.map(\.id), [asset1.id, asset2.id])
        XCTAssertEqual(store.selectedAssetID, asset1.id)

        store.moveSelection(by: 1)
        XCTAssertEqual(store.selectedAssetID, asset2.id)

        store.moveSelection(by: 10)
        XCTAssertEqual(store.selectedAssetID, asset2.id)
    }

    func testJumpBetweenGroupsCyclesForwardAndBackward() {
        let store = ProjectStore()
        let asset1 = TestFixtures.makeAsset(baseName: "IMG_2A", captureDate: TestFixtures.makeDate(hour: 9))
        let asset2 = TestFixtures.makeAsset(baseName: "IMG_2B", captureDate: TestFixtures.makeDate(hour: 10))
        let asset3 = TestFixtures.makeAsset(baseName: "IMG_2C", captureDate: TestFixtures.makeDate(hour: 11))
        let groupA = TestFixtures.makeGroup(name: "A", assets: [asset1])
        let groupB = TestFixtures.makeGroup(name: "B", assets: [asset2])
        let groupC = TestFixtures.makeGroup(name: "C", assets: [asset3])

        TestFixtures.seedStore(store, assets: [asset1, asset2, asset3], groups: [groupA, groupB, groupC])
        store.selectGroup(groupA.id)

        store.jumpToNextGroup()
        XCTAssertEqual(store.selectedGroupID, groupB.id)

        store.jumpToPreviousGroup()
        XCTAssertEqual(store.selectedGroupID, groupA.id)

        store.jumpToPreviousGroup()
        XCTAssertEqual(store.selectedGroupID, groupC.id, "← from first group should wrap to last")
    }

    func testVisibleSmartGroupCellsFoldsBurstsToSingleRepresentative() {
        let store = ProjectStore()
        let single = TestFixtures.makeAsset(baseName: "IMG_3001", captureDate: TestFixtures.makeDate(hour: 9))
        let burstA = TestFixtures.makeAsset(baseName: "IMG_3010", captureDate: TestFixtures.makeDate(hour: 9, minute: 1))
        let burstB = TestFixtures.makeAsset(baseName: "IMG_3011", captureDate: TestFixtures.makeDate(hour: 9, minute: 1, second: 1))
        let burstC = TestFixtures.makeAsset(baseName: "IMG_3012", captureDate: TestFixtures.makeDate(hour: 9, minute: 1, second: 2))

        let group = PhotoGroup(
            id: UUID(),
            name: "Mixed",
            assets: [single.id, burstA.id, burstB.id, burstC.id],
            subGroups: [
                SubGroup(id: UUID(), assets: [single.id], bestAsset: nil),
                SubGroup(id: UUID(), assets: [burstA.id, burstB.id, burstC.id], bestAsset: burstB.id)
            ],
            timeRange: single.metadata.captureDate ... burstC.metadata.captureDate,
            location: nil,
            groupComment: nil,
            recommendedAssets: []
        )

        TestFixtures.seedStore(store, assets: [single, burstA, burstB, burstC], groups: [group])
        store.selectGroup(group.id)

        let cells = store.visibleSmartGroupCells
        XCTAssertEqual(cells.count, 2, "single asset + 3-asset burst should fold to two cells")

        var sawSingle = false
        var sawBurst = false
        for cell in cells {
            switch cell {
            case .single(let asset):
                XCTAssertEqual(asset.id, single.id)
                sawSingle = true
            case .burst(let burst):
                XCTAssertEqual(burst.count, 3)
                XCTAssertEqual(burst.coverAsset.id, burstB.id)
                sawBurst = true
            }
        }
        XCTAssertTrue(sawSingle && sawBurst)
    }

    func testSelectGroupPicksFirstCellCoverSoBurstAutoOpensInGrid() {
        // 回归用例：选中第一个 cell 是 burst 的组时，selectedAssetID 必须落到 burst.coverAsset.id。
        // 否则 selectedBurstContext 会因为命中"非 burst 中的图"而返回 nil，
        // 导致用户一进入有连拍的组中央却展示成单图，看不到连拍网格预览。
        let store = ProjectStore()
        let burstA = TestFixtures.makeAsset(baseName: "IMG_4001", captureDate: TestFixtures.makeDate(hour: 9))
        let burstB = TestFixtures.makeAsset(baseName: "IMG_4002", captureDate: TestFixtures.makeDate(hour: 9, minute: 0, second: 1))
        let burstC = TestFixtures.makeAsset(baseName: "IMG_4003", captureDate: TestFixtures.makeDate(hour: 9, minute: 0, second: 2))
        let single = TestFixtures.makeAsset(baseName: "IMG_4010", captureDate: TestFixtures.makeDate(hour: 9, minute: 5))

        let group = PhotoGroup(
            id: UUID(),
            name: "BurstFirst",
            assets: [burstA.id, burstB.id, burstC.id, single.id],
            subGroups: [
                SubGroup(id: UUID(), assets: [burstA.id, burstB.id, burstC.id], bestAsset: burstB.id),
                SubGroup(id: UUID(), assets: [single.id], bestAsset: nil)
            ],
            timeRange: burstA.metadata.captureDate ... single.metadata.captureDate,
            location: nil,
            groupComment: nil,
            recommendedAssets: []
        )

        TestFixtures.seedStore(store, assets: [burstA, burstB, burstC, single], groups: [group])
        store.selectGroup(group.id)

        XCTAssertEqual(store.selectedAssetID, burstB.id, "First cell is the burst → selection should land on its cover asset")
        let context = store.selectedBurstContext
        XCTAssertNotNil(context, "Cover-asset selection must yield a real burst context so the center area renders the grid")
        XCTAssertEqual(context?.burst.count, 3)
    }

    func testSummaryCountsTechnicalRejectsUnlessAlreadyPicked() {
        let store = ProjectStore()
        let pending = TestFixtures.makeAsset(
            baseName: "IMG_1201",
            captureDate: TestFixtures.makeDate(hour: 11),
            aiScore: TestFixtures.makeAIScore(overall: 70)
        )
        let technicalReject = TestFixtures.makeAsset(
            baseName: "IMG_1202",
            captureDate: TestFixtures.makeDate(hour: 11, minute: 1),
            aiScore: TestFixtures.makeAIScore(overall: 40, recommended: false),
            issues: [.blurry]
        )
        let pickedDespiteIssue = TestFixtures.makeAsset(
            baseName: "IMG_1203",
            captureDate: TestFixtures.makeDate(hour: 11, minute: 2),
            aiScore: TestFixtures.makeAIScore(overall: 85, recommended: true),
            userDecision: .picked,
            issues: [.underexposed]
        )
        let explicitlyRejected = TestFixtures.makeAsset(
            baseName: "IMG_1204",
            captureDate: TestFixtures.makeDate(hour: 11, minute: 3),
            aiScore: TestFixtures.makeAIScore(overall: 30, recommended: false),
            userDecision: .rejected
        )

        let group = TestFixtures.makeGroup(
            name: "Summary Group",
            assets: [pending, technicalReject, pickedDespiteIssue, explicitlyRejected],
            recommendedAssets: [pickedDespiteIssue.id]
        )
        TestFixtures.seedStore(store, assets: [pending, technicalReject, pickedDespiteIssue, explicitlyRejected])

        let summary = store.summary(for: group)

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.picked, 1)
        // Only explicit userDecision == .rejected counts; technicalReject (issues but no user decision) stays pending
        XCTAssertEqual(summary.rejected, 1)
        XCTAssertEqual(summary.pending, 2)
        XCTAssertEqual(summary.recommended, 1)
    }

    func testOpenProjectLoadsManifestAndRefreshProjectSummariesMarksUnreadableProjects() throws {
        try TestFixtures.withTemporaryDirectory { root in
            try TestFixtures.withAppSupportRootOverride(root) {
                let store = ProjectStore()

                let brokenDirectory = try AppDirectories.projectsRoot().appendingPathComponent("BrokenProject", isDirectory: true)
                try FileManager.default.createDirectory(at: brokenDirectory, withIntermediateDirectories: true)
                try "not json".write(to: AppDirectories.manifestURL(in: brokenDirectory), atomically: true, encoding: .utf8)

                let asset = TestFixtures.makeAsset(
                    baseName: "IMG_1301",
                    captureDate: TestFixtures.makeDate(hour: 12),
                    aiScore: TestFixtures.makeAIScore(overall: 88, recommended: true)
                )
                let group = TestFixtures.makeGroup(name: "Ready Group", assets: [asset], recommendedAssets: [asset.id])
                let readyDirectory = try AppDirectories.createProjectDirectory(named: "Ready Project", createdAt: TestFixtures.makeDate(hour: 12))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Ready Project", createdAt: TestFixtures.makeDate(hour: 12), assets: [asset], groups: [group]),
                    in: readyDirectory
                )

                store.refreshProjectSummaries()

                XCTAssertEqual(store.projectSummaries.count, 2)
                let brokenSummary = try XCTUnwrap(store.projectSummaries.first(where: { $0.name == "BrokenProject" }))
                if case .unavailable = brokenSummary.state {
                } else {
                    XCTFail("Expected broken project summary to be unavailable")
                }

                store.isProjectLibraryPresented = true
                let readySummary = try XCTUnwrap(store.projectSummaries.first(where: { $0.name == "Ready Project" }))
                store.openProject(readySummary)

                XCTAssertEqual(
                    store.currentProjectDirectory?.standardizedFileURL.resolvingSymlinksInPath().path,
                    readyDirectory.standardizedFileURL.resolvingSymlinksInPath().path
                )
                XCTAssertEqual(store.projectName, "Ready Project")
                XCTAssertEqual(store.selectedAssetID, asset.id)
                XCTAssertFalse(store.isProjectLibraryPresented)
            }
        }
    }

    func testMarkSelectionPendingResetsDecisionAndAdvances() {
        let store = ProjectStore()
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_2001",
            captureDate: TestFixtures.makeDate(hour: 11),
            userDecision: .picked
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_2002",
            captureDate: TestFixtures.makeDate(hour: 11, minute: 1),
            userDecision: .rejected
        )
        let group = TestFixtures.makeGroup(name: "Reset", assets: [asset1, asset2])
        TestFixtures.seedStore(store, assets: [asset1, asset2], groups: [group])
        store.selectGroup(group.id)
        store.selectedAssetID = asset1.id

        store.markSelection(.pending)

        XCTAssertEqual(store.assets.first(where: { $0.id == asset1.id })?.userDecision, .pending)
        XCTAssertEqual(store.selectedAssetID, asset2.id, "Pending mark should advance selection like Pick / Reject")
    }

    func testProjectSummaryReflectsDecisionAndExportState() throws {
        try TestFixtures.withTemporaryDirectory { root in
            try TestFixtures.withAppSupportRootOverride(root) {
                let store = ProjectStore()

                let picked = TestFixtures.makeAsset(
                    baseName: "IMG_3001",
                    captureDate: TestFixtures.makeDate(hour: 9),
                    aiScore: TestFixtures.makeAIScore(overall: 90, recommended: true),
                    userDecision: .picked
                )
                let pending = TestFixtures.makeAsset(
                    baseName: "IMG_3002",
                    captureDate: TestFixtures.makeDate(hour: 9, minute: 1),
                    aiScore: TestFixtures.makeAIScore(overall: 70)
                )
                let group = TestFixtures.makeGroup(name: "Group", assets: [picked, pending])

                let directory = try AppDirectories.createProjectDirectory(
                    named: "Progress Project",
                    createdAt: TestFixtures.makeDate(hour: 9)
                )
                var manifest = TestFixtures.makeManifest(
                    name: "Progress Project",
                    createdAt: TestFixtures.makeDate(hour: 9),
                    assets: [picked, pending],
                    groups: [group]
                )
                manifest.session.exportJobs = [
                    ExportJob(
                        id: UUID(),
                        createdAt: TestFixtures.makeDate(hour: 10),
                        completedAt: TestFixtures.makeDate(hour: 10, minute: 1),
                        status: .completed,
                        options: .default,
                        targetAssetIDs: [picked.id],
                        exportedCount: 1,
                        totalCount: 1,
                        speedBytesPerSecond: nil,
                        estimatedSecondsRemaining: nil,
                        destinationDescription: "/tmp/out",
                        lastError: nil,
                        cleanedCount: 0,
                        cleanupCancelledCount: 0,
                        albumDescription: nil,
                        failures: nil
                    )
                ]
                try TestFixtures.writeManifest(manifest, in: directory)

                store.refreshProjectSummaries()
                let summary = try XCTUnwrap(store.projectSummaries.first(where: { $0.name == "Progress Project" }))

                XCTAssertEqual(summary.decidedCount, 1)
                XCTAssertEqual(summary.totalAssetCount, 2)
                XCTAssertEqual(summary.exportJobCount, 1)
                XCTAssertNotNil(summary.lastExportedAt)
                XCTAssertFalse(summary.isCullingComplete)
                XCTAssertFalse(summary.isArchived)

                store.setArchive(summary, archived: true)
                let after = try XCTUnwrap(store.projectSummaries.first(where: { $0.name == "Progress Project" }))
                XCTAssertTrue(after.isArchived)
            }
        }
    }

    func testDeleteProjectRemovesRecoverableSessionAndFallsBackToNextProject() throws {
        try TestFixtures.withTemporaryDirectory { root in
            try TestFixtures.withAppSupportRootOverride(root) {
                let store = ProjectStore()

                let fallbackAsset = TestFixtures.makeAsset(
                    baseName: "IMG_1401",
                    captureDate: TestFixtures.makeDate(hour: 13),
                    aiScore: TestFixtures.makeAIScore(overall: 76)
                )
                let fallbackGroup = TestFixtures.makeGroup(name: "Fallback", assets: [fallbackAsset])
                let fallbackDirectory = try AppDirectories.createProjectDirectory(named: "Fallback Project", createdAt: TestFixtures.makeDate(hour: 13))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Fallback Project", createdAt: TestFixtures.makeDate(hour: 13), assets: [fallbackAsset], groups: [fallbackGroup]),
                    in: fallbackDirectory
                )

                let currentAsset = TestFixtures.makeAsset(
                    baseName: "IMG_1402",
                    captureDate: TestFixtures.makeDate(hour: 14),
                    aiScore: TestFixtures.makeAIScore(overall: 91, recommended: true)
                )
                let currentGroup = TestFixtures.makeGroup(name: "Current", assets: [currentAsset], recommendedAssets: [currentAsset.id])
                let currentDirectory = try AppDirectories.createProjectDirectory(named: "Current Project", createdAt: TestFixtures.makeDate(hour: 14))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Current Project", createdAt: TestFixtures.makeDate(hour: 14), assets: [currentAsset], groups: [currentGroup]),
                    in: currentDirectory
                )

                store.refreshProjectSummaries()
                let currentSummary = try XCTUnwrap(store.projectSummaries.first(where: { $0.name == "Current Project" }))
                store.openProject(currentSummary)

                let session = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000140")!,
                    projectDirectory: currentDirectory,
                    projectName: "Current Project",
                    phase: .paused,
                    status: .paused,
                    lastError: "Resume me"
                )
                try ImportSessionStore.save(session)
                store.recoverableImportSession = session

                store.deleteProject(currentSummary)

                XCTAssertFalse(FileManager.default.fileExists(atPath: currentDirectory.path))
                XCTAssertNil(store.recoverableImportSession)
                XCTAssertEqual(
                    store.currentProjectDirectory?.standardizedFileURL.resolvingSymlinksInPath().path,
                    fallbackDirectory.standardizedFileURL.resolvingSymlinksInPath().path
                )
                XCTAssertEqual(store.projectName, "Fallback Project")
                XCTAssertEqual(store.projectSummaries.count, 1)
                XCTAssertEqual(
                    store.projectSummaries.first?.directory.standardizedFileURL.resolvingSymlinksInPath().path,
                    fallbackDirectory.standardizedFileURL.resolvingSymlinksInPath().path
                )
                XCTAssertFalse(FileManager.default.fileExists(atPath: try AppDirectories.importSessionURL(id: session.id).path))
            }
        }
    }
}
