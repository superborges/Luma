import XCTest
@testable import Luma

@MainActor
final class ProjectStoreTests: XCTestCase {
    func testSelectionFlowUpdatesVisibleAssetsAndDisplayMode() {
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

        store.assets = [asset1, asset2, asset3]
        store.groups = [groupA, groupB]
        store.selectedAssetID = asset3.id

        store.selectGroup(groupA.id)

        XCTAssertEqual(store.selectedGroupID, groupA.id)
        XCTAssertEqual(store.visibleAssets.map(\.id), [asset1.id, asset2.id])
        XCTAssertEqual(store.selectedAssetID, asset1.id)

        store.moveSelection(by: 1)
        XCTAssertEqual(store.selectedAssetID, asset2.id)

        store.moveSelection(by: 10)
        XCTAssertEqual(store.selectedAssetID, asset2.id)

        store.toggleDisplayMode()
        XCTAssertEqual(store.displayMode, .single)
    }

    func testSelectRecommendedInCurrentScopeMarksOnlyVisibleRecommendedAssets() {
        let store = ProjectStore()
        let recommendedA = TestFixtures.makeAsset(
            baseName: "IMG_1101",
            captureDate: TestFixtures.makeDate(hour: 10),
            aiScore: TestFixtures.makeAIScore(overall: 92, recommended: true)
        )
        let normalA = TestFixtures.makeAsset(
            baseName: "IMG_1102",
            captureDate: TestFixtures.makeDate(hour: 10, minute: 1),
            aiScore: TestFixtures.makeAIScore(overall: 65, recommended: false)
        )
        let recommendedB = TestFixtures.makeAsset(
            baseName: "IMG_1103",
            captureDate: TestFixtures.makeDate(hour: 10, minute: 2),
            aiScore: TestFixtures.makeAIScore(overall: 90, recommended: true)
        )

        let groupA = TestFixtures.makeGroup(name: "Group A", assets: [recommendedA, normalA], recommendedAssets: [recommendedA.id])
        let groupB = TestFixtures.makeGroup(name: "Group B", assets: [recommendedB], recommendedAssets: [recommendedB.id])

        store.assets = [recommendedA, normalA, recommendedB]
        store.groups = [groupA, groupB]
        store.selectGroup(groupA.id)

        store.selectRecommendedInCurrentScope()

        XCTAssertEqual(store.assets.first(where: { $0.id == recommendedA.id })?.userDecision, .picked)
        XCTAssertEqual(store.assets.first(where: { $0.id == normalA.id })?.userDecision, .pending)
        XCTAssertEqual(store.assets.first(where: { $0.id == recommendedB.id })?.userDecision, .pending)
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
        store.assets = [pending, technicalReject, pickedDespiteIssue, explicitlyRejected]

        let summary = store.summary(for: group)

        XCTAssertEqual(summary.total, 4)
        XCTAssertEqual(summary.picked, 1)
        XCTAssertEqual(summary.rejected, 2)
        XCTAssertEqual(summary.pending, 1)
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
