import XCTest
@testable import Luma

final class ImportSourceDescriptorTests: XCTestCase {
    func testFolderStableIDAndDisplayName() {
        let d = ImportSourceDescriptor.folder(
            path: "/Volumes/x/inbox",
            displayName: "Inbox"
        )
        XCTAssertEqual(d.stableID, "folder:/Volumes/x/inbox")
        XCTAssertEqual(d.displayName, "Inbox")
    }

    func testPhotosLibraryStableIDEncodesNilAlbum() {
        let p = ImportSourceDescriptor.photosLibrary(
            albumLocalIdentifier: nil,
            limit: 200,
            displayName: "All"
        )
        XCTAssertTrue(p.stableID.contains("all"))
        XCTAssertTrue(p.stableID.contains("200"))
    }

    func testSDCardAndIPhoneStableIDs() {
        let sd = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/EOS", displayName: "Card")
        XCTAssertEqual(sd.stableID, "sd:/Volumes/EOS")
        let phone = ImportSourceDescriptor.iPhone(deviceID: "abc", deviceName: "iPhone")
        XCTAssertEqual(phone.stableID, "iphone:abc")
    }

    func testImportSourceDescriptorJSONRoundTrips() throws {
        let cases: [ImportSourceDescriptor] = [
            .folder(path: "/tmp/inbox", displayName: "Inbox"),
            .sdCard(volumePath: "/Volumes/X", displayName: "SD"),
            .iPhone(deviceID: "udid-1", deviceName: "My Phone"),
            .photosLibrary(albumLocalIdentifier: "L/alb", limit: 50, displayName: "Album")
        ]
        for original in cases {
            let data = try JSONEncoder.lumaEncoder.encode(original)
            let decoded = try JSONDecoder.lumaDecoder.decode(ImportSourceDescriptor.self, from: data)
            XCTAssertEqual(decoded, original, "\(original.stableID)")
        }
    }
}

final class ImportSessionProgressTests: XCTestCase {
    func testProgressSummaryByPhase() {
        let base = Date(timeIntervalSince1970: 0)
        func session(phase: ImportPhase) -> ImportSession {
            ImportSession(
                id: UUID(),
                source: .folder(path: "/tmp", displayName: "T"),
                projectDirectory: nil,
                projectName: nil,
                createdAt: base,
                updatedAt: base,
                phase: phase,
                status: .running,
                totalItems: 4,
                completedThumbnails: 1,
                completedPreviews: 2,
                completedOriginals: 3,
                lastError: nil,
                completedAt: nil,
                importedAssetIDs: []
            )
        }
        XCTAssertTrue(session(phase: .scanning).progressSummary.contains("扫描"))
        XCTAssertTrue(session(phase: .preparingThumbnails).progressSummary.contains("缩略图"))
        XCTAssertTrue(session(phase: .copyingPreviews).progressSummary.contains("预览"))
        XCTAssertTrue(session(phase: .copyingOriginals).progressSummary.contains("原图"))
        XCTAssertTrue(session(phase: .finalizing).progressSummary.contains("整理"))
        var paused = session(phase: .paused)
        paused.lastError = "eject"
        XCTAssertTrue(paused.progressSummary.contains("eject"))
    }

    func testDisplayProjectNameFallsBackToSourceDisplayName() {
        let base = Date(timeIntervalSince1970: 0)
        let s = ImportSession(
            id: UUID(),
            source: .folder(path: "/x", displayName: "SourceName"),
            projectDirectory: nil,
            projectName: nil,
            createdAt: base,
            updatedAt: base,
            phase: .scanning,
            status: .running,
            totalItems: 0,
            completedThumbnails: 0,
            completedPreviews: 0,
            completedOriginals: 0,
            lastError: nil,
            completedAt: nil,
            importedAssetIDs: []
        )
        XCTAssertEqual(s.displayProjectName, "SourceName")
        var named = s
        named.projectName = "OnDisk"
        XCTAssertEqual(named.displayProjectName, "OnDisk")
    }

    func testProgressSummaryUsesDenominatorAtLeastOneWhenTotalIsZero() {
        let base = Date(timeIntervalSince1970: 0)
        let s = ImportSession(
            id: UUID(),
            source: .folder(path: "/y", displayName: "Y"),
            projectDirectory: nil,
            projectName: nil,
            createdAt: base,
            updatedAt: base,
            phase: .preparingThumbnails,
            status: .running,
            totalItems: 0,
            completedThumbnails: 0,
            completedPreviews: 0,
            completedOriginals: 0,
            lastError: nil,
            completedAt: nil,
            importedAssetIDs: []
        )
        XCTAssertTrue(s.progressSummary.contains("/1"))
    }
}

final class PendingImportPromptTests: XCTestCase {
    func testImportSourcePromptIDsAndCopy() {
        let src = ImportSourceDescriptor.folder(path: "/p", displayName: "Vol")
        let prompt = PendingImportPrompt.importSource(src)
        XCTAssertEqual(prompt.id, "import:\(src.stableID)")
        XCTAssertTrue(prompt.title.contains("导入"))
        XCTAssertEqual(prompt.confirmTitle, "开始导入")
        XCTAssertTrue(prompt.message.contains("Vol"))
    }

    func testResumeSessionPromptIDsAndMessage() throws {
        try TestFixtures.withTemporaryDirectory { dir in
            let session = TestFixtures.makeImportSession(
                projectDirectory: dir,
                projectName: "ResumeMe",
                phase: .copyingPreviews,
                status: .running
            )
            let prompt = PendingImportPrompt.resumeSession(session)
            XCTAssertTrue(prompt.id.hasPrefix("resume:"))
            XCTAssertTrue(prompt.id.contains(session.id.uuidString))
            XCTAssertEqual(prompt.confirmTitle, "继续导入")
            XCTAssertTrue(prompt.message.contains("ResumeMe"))
            XCTAssertTrue(prompt.message.contains("预览") || prompt.message.contains("拷贝"))
        }
    }
}
