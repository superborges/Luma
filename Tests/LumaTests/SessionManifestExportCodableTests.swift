import XCTest
@testable import Luma

/// `SessionManifest` 旧盘格式与 `ExportJob` 持久化 JSON 的回归测试。
final class SessionManifestExportCodableTests: XCTestCase {
    // MARK: - SessionManifest (expedition / flat / 当前)

    func testDecodesExpeditionKeyedSessionAsSchemaV1() throws {
        let id = UUID()
        let asset = TestFixtures.makeAsset(
            baseName: "legacy",
            captureDate: TestFixtures.makeDate(hour: 4)
        )
        let session = Session(
            id: id,
            name: "ExpeditionKey",
            createdAt: TestFixtures.makeDate(hour: 1),
            updatedAt: TestFixtures.makeDate(hour: 2),
            location: nil,
            tags: [],
            coverAssetID: asset.id,
            assets: [asset],
            groups: [],
            importSessions: [],
            editingSessions: [],
            exportJobs: []
        )
        let sessionData = try JSONEncoder.lumaEncoder.encode(session)
        let sessionObject = try JSONSerialization.jsonObject(with: sessionData)
        let top: [String: Any] = [
            "id": id.uuidString,
            "expedition": sessionObject
        ]
        let data = try JSONSerialization.data(withJSONObject: top)
        let manifest = try JSONDecoder.lumaDecoder.decode(SessionManifest.self, from: data)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.id, id)
        XCTAssertEqual(manifest.name, "ExpeditionKey")
        XCTAssertEqual(manifest.assets.count, 1)
    }

    func testDecodesFlatTopLevelManifestAsSchemaV1() throws {
        let id = UUID()
        let asset = TestFixtures.makeAsset(
            baseName: "flat",
            captureDate: TestFixtures.makeDate(hour: 5)
        )
        let flat = FlatLegacyTop(
            id: id,
            name: "FlatTop",
            createdAt: TestFixtures.makeDate(hour: 6),
            assets: [asset],
            groups: []
        )
        let data = try JSONEncoder.lumaEncoder.encode(flat)
        let manifest = try JSONDecoder.lumaDecoder.decode(SessionManifest.self, from: data)
        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.id, id)
        XCTAssertEqual(manifest.name, "FlatTop")
        XCTAssertEqual(manifest.session.importSessions, [])
        XCTAssertEqual(manifest.session.exportJobs, [])
    }

    func testCurrentManifestRoundTripUsesSchemaV2() throws {
        let asset = TestFixtures.makeAsset(
            baseName: "v2",
            captureDate: TestFixtures.makeDate(hour: 7)
        )
        let original = TestFixtures.makeManifest(
            name: "Round",
            createdAt: TestFixtures.makeDate(hour: 8),
            assets: [asset],
            groups: []
        )
        let data = try JSONEncoder.lumaEncoder.encode(original)
        let decoded = try JSONDecoder.lumaDecoder.decode(SessionManifest.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, SessionManifest.currentSchemaVersion)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Round")
    }

    // MARK: - ExportJob + ExportFailure

    func testExportJobJSONRoundTripPreservesFailures() throws {
        let opt = ExportOptions.default
        let a1 = UUID()
        let a2 = UUID()
        let job = ExportJob(
            id: UUID(),
            createdAt: TestFixtures.makeDate(hour: 9),
            completedAt: nil,
            status: .failed,
            options: opt,
            targetAssetIDs: [a1, a2],
            exportedCount: 0,
            totalCount: 2,
            speedBytesPerSecond: 12_000,
            estimatedSecondsRemaining: 30,
            destinationDescription: "Photos",
            lastError: "boom",
            cleanedCount: 0,
            cleanupCancelledCount: 1,
            albumDescription: "Luma Picks",
            failures: [ExportFailure(assetID: a1, fileName: "x.jpg", reason: "copy")]
        )
        let data = try JSONEncoder.lumaEncoder.encode(job)
        let out = try JSONDecoder.lumaDecoder.decode(ExportJob.self, from: data)
        XCTAssertEqual(out.id, job.id)
        XCTAssertEqual(out.status, .failed)
        XCTAssertEqual(out.failures?.count, 1)
        XCTAssertEqual(out.failures?.first?.assetID, a1)
        XCTAssertEqual(out.failures?.first?.fileName, "x.jpg")
        XCTAssertEqual(out.cleanedCount, 0)
    }
}

/// 仅用于模拟「更早 flat」manifest：顶层字段无 `session` 包装。
private struct FlatLegacyTop: Encodable {
    let id: UUID
    let name: String
    let createdAt: Date
    let assets: [MediaAsset]
    let groups: [PhotoGroup]
}
