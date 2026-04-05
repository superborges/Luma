import Foundation
import XCTest
@testable import Luma

@MainActor
final class ProjectStoreBootstrapTests: XCTestCase {
    func testBootstrapLoadsRecoverableSessionManifestProgressAndPrompt() async throws {
        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let store = ProjectStore(enableImportMonitoring: false)

                let asset = TestFixtures.makeAsset(
                    baseName: "IMG_4001",
                    captureDate: TestFixtures.makeDate(hour: 8),
                    aiScore: TestFixtures.makeAIScore(overall: 86, recommended: true)
                )
                let group = TestFixtures.makeGroup(name: "Recoverable Group", assets: [asset], recommendedAssets: [asset.id])
                let projectDirectory = try AppDirectories.createProjectDirectory(named: "Recoverable Project", createdAt: TestFixtures.makeDate(hour: 8))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Recoverable Project", createdAt: TestFixtures.makeDate(hour: 8), assets: [asset], groups: [group]),
                    in: projectDirectory
                )

                let session = TestFixtures.makeImportSession(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
                    projectDirectory: projectDirectory,
                    projectName: "Recoverable Project",
                    phase: .copyingOriginals,
                    status: .paused,
                    totalItems: 3,
                    completedThumbnails: 3,
                    completedPreviews: 3,
                    completedOriginals: 1,
                    lastError: "等待恢复"
                )
                try ImportSessionStore.save(session)

                await store.bootstrap()

                XCTAssertEqual(store.projectName, "Recoverable Project")
                XCTAssertEqual(store.assets.count, 1)
                XCTAssertEqual(store.groups.count, 1)
                XCTAssertEqual(store.selectedAssetID, asset.id)
                XCTAssertEqual(store.recoverableImportSession?.id, session.id)
                XCTAssertEqual(store.importProgress?.phase, .copyingOriginals)
                XCTAssertEqual(store.importProgress?.completed, 1)
                XCTAssertEqual(store.importProgress?.total, 3)
                if case .resumeSession(let promptSession) = store.pendingImportPrompt {
                    XCTAssertEqual(promptSession.id, session.id)
                } else {
                    XCTFail("Expected resume session prompt")
                }
            }
        }
    }

    func testBootstrapLoadsMostRecentProjectWhenNoRecoverableSessionExists() async throws {
        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let store = ProjectStore(enableImportMonitoring: false)

                let firstAsset = TestFixtures.makeAsset(
                    baseName: "IMG_4101",
                    captureDate: TestFixtures.makeDate(hour: 9),
                    aiScore: TestFixtures.makeAIScore(overall: 70)
                )
                let secondAsset = TestFixtures.makeAsset(
                    baseName: "IMG_4102",
                    captureDate: TestFixtures.makeDate(hour: 10),
                    aiScore: TestFixtures.makeAIScore(overall: 92, recommended: true)
                )

                let oldDirectory = try AppDirectories.createProjectDirectory(named: "Old Project", createdAt: TestFixtures.makeDate(hour: 9))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Old Project", createdAt: TestFixtures.makeDate(hour: 9), assets: [firstAsset], groups: [TestFixtures.makeGroup(name: "Old", assets: [firstAsset])]),
                    in: oldDirectory
                )

                let newDirectory = try AppDirectories.createProjectDirectory(named: "New Project", createdAt: TestFixtures.makeDate(hour: 10))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "New Project", createdAt: TestFixtures.makeDate(hour: 10), assets: [secondAsset], groups: [TestFixtures.makeGroup(name: "New", assets: [secondAsset], recommendedAssets: [secondAsset.id])]),
                    in: newDirectory
                )

                await store.bootstrap()

                XCTAssertEqual(store.projectName, "New Project")
                XCTAssertEqual(store.assets.count, 1)
                XCTAssertEqual(store.selectedAssetID, secondAsset.id)
                XCTAssertNil(store.pendingImportPrompt)
                XCTAssertNil(store.recoverableImportSession)
                XCTAssertEqual(store.projectSummaries.count, 2)
                XCTAssertEqual(store.projectSummaries.first?.name, "New Project")
            }
        }
    }

    func testBootstrapIsIdempotentAfterFirstRun() async throws {
        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let store = ProjectStore(enableImportMonitoring: false)
                let firstAsset = TestFixtures.makeAsset(baseName: "IMG_4201", captureDate: TestFixtures.makeDate(hour: 11), aiScore: TestFixtures.makeAIScore(overall: 88))
                let secondAsset = TestFixtures.makeAsset(baseName: "IMG_4202", captureDate: TestFixtures.makeDate(hour: 12), aiScore: TestFixtures.makeAIScore(overall: 91))

                let initialDirectory = try AppDirectories.createProjectDirectory(named: "Initial Project", createdAt: TestFixtures.makeDate(hour: 11))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Initial Project", createdAt: TestFixtures.makeDate(hour: 11), assets: [firstAsset], groups: [TestFixtures.makeGroup(name: "Initial", assets: [firstAsset])]),
                    in: initialDirectory
                )

                await store.bootstrap()

                let newerDirectory = try AppDirectories.createProjectDirectory(named: "Later Project", createdAt: TestFixtures.makeDate(hour: 12))
                try TestFixtures.writeManifest(
                    TestFixtures.makeManifest(name: "Later Project", createdAt: TestFixtures.makeDate(hour: 12), assets: [secondAsset], groups: [TestFixtures.makeGroup(name: "Later", assets: [secondAsset])]),
                    in: newerDirectory
                )

                await store.bootstrap()

                XCTAssertEqual(store.projectName, "Initial Project")
                XCTAssertEqual(store.assets.count, 1)
                XCTAssertEqual(store.selectedAssetID, firstAsset.id)
            }
        }
    }
}
