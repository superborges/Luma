import CoreGraphics
import Foundation
import XCTest
@testable import Luma

final class ImportManagerTests: XCTestCase {
    func testImportFromSourceBuildsManifestCopiesFilesAndCleansRecoverableSession() async throws {
        let manager = ImportManager()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("ImportSource", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let previewURL = sourceRoot.appendingPathComponent("IMG_2001.JPG")
                let rawURL = sourceRoot.appendingPathComponent("IMG_2001.DNG")
                let liveURL = sourceRoot.appendingPathComponent("IMG_2001.MOV")
                try TestFixtures.makeJPEG(at: previewURL)
                try TestFixtures.createFile(at: rawURL, modifiedAt: TestFixtures.makeDate(hour: 8))
                try TestFixtures.createFile(at: liveURL, modifiedAt: TestFixtures.makeDate(hour: 8, minute: 1))

                let item = DiscoveredItem(
                    id: UUID(),
                    resumeKey: "img_2001",
                    baseName: "IMG_2001",
                    source: .folder(path: sourceRoot.path),
                    previewFile: previewURL,
                    rawFile: rawURL,
                    auxiliaryFile: liveURL,
                    depthData: false,
                    metadata: EXIFData(
                        captureDate: TestFixtures.makeDate(hour: 8),
                        gpsCoordinate: Coordinate(latitude: 31.23, longitude: 121.47),
                        focalLength: 35,
                        aperture: 2.0,
                        shutterSpeed: "1/125",
                        iso: 100,
                        cameraModel: "Test Cam",
                        lensModel: "Test Lens",
                        imageWidth: 3000,
                        imageHeight: 2000
                    ),
                    mediaType: .livePhoto
                )

                let adapter = MockImportAdapter(items: [item])
                let source = ImportSourceDescriptor.folder(path: sourceRoot.path, displayName: "ImportSource")
                let recorder = ImportEventRecorder()

                let imported = try await manager.importFromSource(
                    source,
                    adapter: adapter,
                    progress: { progress in recorder.record(progress: progress) },
                    snapshot: { snapshot in recorder.record(snapshot: snapshot) }
                )

                let events = recorder.snapshot()
                XCTAssertEqual(imported.manifest.assets.count, 1)
                XCTAssertEqual(imported.manifest.groups.count, 1)
                let asset = try XCTUnwrap(imported.manifest.assets.first)
                XCTAssertEqual(asset.importState, .complete)
                XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.thumbnailURL).path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.previewURL).path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.rawURL).path))
                XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.livePhotoVideoURL).path))
                XCTAssertNil(manager.mostRecentRecoverableSession())
                XCTAssertTrue(FileManager.default.fileExists(atPath: AppDirectories.manifestURL(in: imported.directory).path))

                let phases = events.progresses.map(\.phase)
                XCTAssertTrue(phases.contains(.scanning))
                XCTAssertTrue(phases.contains(.preparingThumbnails))
                XCTAssertTrue(phases.contains(.copyingPreviews))
                XCTAssertTrue(phases.contains(.copyingOriginals))
                XCTAssertTrue(phases.contains(.finalizing))
                XCTAssertTrue(events.snapshots.contains { !$0.isFinal })
                XCTAssertTrue(events.snapshots.contains { $0.isFinal })
            }
        }
    }

    func testImportFromSourcePausesSessionWhenCopyOriginalFails() async throws {
        let manager = ImportManager()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("PausedImportSource", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let previewURL = sourceRoot.appendingPathComponent("IMG_2002.JPG")
                let rawURL = sourceRoot.appendingPathComponent("IMG_2002.DNG")
                try TestFixtures.makeJPEG(at: previewURL)
                try TestFixtures.createFile(at: rawURL, modifiedAt: TestFixtures.makeDate(hour: 9))

                let item = DiscoveredItem(
                    id: UUID(),
                    resumeKey: "img_2002",
                    baseName: "IMG_2002",
                    source: .folder(path: sourceRoot.path),
                    previewFile: previewURL,
                    rawFile: rawURL,
                    auxiliaryFile: nil,
                    depthData: false,
                    metadata: EXIFData.empty,
                    mediaType: .photo
                )

                let adapter = MockImportAdapter(items: [item], originalCopyError: "disk full")
                let source = ImportSourceDescriptor.folder(path: sourceRoot.path, displayName: "PausedImportSource")

                await XCTAssertThrowsErrorAsync {
                    _ = try await manager.importFromSource(source, adapter: adapter, progress: { _ in }, snapshot: { _ in })
                } verify: { error in
                    XCTAssertTrue(error.localizedDescription.contains("导入已暂停"))
                }

                let session = try XCTUnwrap(manager.mostRecentRecoverableSession())
                XCTAssertEqual(session.status, .paused)
                XCTAssertEqual(session.phase, .paused)
                XCTAssertEqual(session.completedThumbnails, 1)
                XCTAssertEqual(session.completedPreviews, 1)
                XCTAssertEqual(session.completedOriginals, 0)

                let manifest = try manager.loadManifest(for: session)
                let asset = try XCTUnwrap(manifest.assets.first)
                XCTAssertEqual(asset.importState, .previewCopied)
                XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.previewURL).path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.rawURL).path))
            }
        }
    }

    func testResumeImportCompletesPausedSession() async throws {
        let manager = ImportManager()

        try await TestFixtures.withTemporaryDirectory { root in
            try await TestFixtures.withAppSupportRootOverride(root) {
                let sourceRoot = root.appendingPathComponent("ResumeImportSource", isDirectory: true)
                try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

                let previewURL = sourceRoot.appendingPathComponent("IMG_2003.JPG")
                let rawURL = sourceRoot.appendingPathComponent("IMG_2003.DNG")
                try TestFixtures.makeJPEG(at: previewURL)
                try TestFixtures.createFile(at: rawURL, modifiedAt: TestFixtures.makeDate(hour: 10))

                let item = DiscoveredItem(
                    id: UUID(),
                    resumeKey: "img_2003",
                    baseName: "IMG_2003",
                    source: .folder(path: sourceRoot.path),
                    previewFile: previewURL,
                    rawFile: rawURL,
                    auxiliaryFile: nil,
                    depthData: false,
                    metadata: EXIFData.empty,
                    mediaType: .photo
                )

                let source = ImportSourceDescriptor.folder(path: sourceRoot.path, displayName: "ResumeImportSource")
                let failingAdapter = MockImportAdapter(items: [item], originalCopyError: "temporary offline")
                _ = try? await manager.importFromSource(source, adapter: failingAdapter, progress: { _ in }, snapshot: { _ in })

                let pausedSession = try XCTUnwrap(manager.mostRecentRecoverableSession())
                let succeedingAdapter = MockImportAdapter(items: [item])

                let imported = try await manager.resumeImport(
                    session: pausedSession,
                    adapter: succeedingAdapter,
                    progress: { _ in },
                    snapshot: { _ in }
                )

                XCTAssertNil(manager.mostRecentRecoverableSession())
                let asset = try XCTUnwrap(imported.manifest.assets.first)
                XCTAssertEqual(asset.importState, .complete)
                XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(asset.rawURL).path))
            }
        }
    }
}

private final class MockImportAdapter: ImportSourceAdapter, @unchecked Sendable {
    let displayName: String
    let items: [DiscoveredItem]
    let previewCopyError: String?
    let originalCopyError: String?
    let auxiliaryCopyError: String?
    let states: [ConnectionState]

    init(
        displayName: String = "Mock Import Source",
        items: [DiscoveredItem],
        previewCopyError: String? = nil,
        originalCopyError: String? = nil,
        auxiliaryCopyError: String? = nil,
        states: [ConnectionState] = [.connected]
    ) {
        self.displayName = displayName
        self.items = items
        self.previewCopyError = previewCopyError
        self.originalCopyError = originalCopyError
        self.auxiliaryCopyError = auxiliaryCopyError
        self.states = states
    }

    func enumerate() async throws -> [DiscoveredItem] {
        items
    }

    func fetchThumbnail(_ item: DiscoveredItem) async -> CGImage? {
        guard let sourceURL = item.previewFile ?? item.rawFile else { return nil }
        return EXIFParser.makeThumbnail(from: sourceURL, maxPixelSize: 400)
    }

    func copyPreview(_ item: DiscoveredItem, to destination: URL) async throws {
        try Self.copy(from: item.previewFile, to: destination, failureMessage: previewCopyError)
    }

    func copyOriginal(_ item: DiscoveredItem, to destination: URL) async throws {
        try Self.copy(from: item.rawFile, to: destination, failureMessage: originalCopyError)
    }

    func copyAuxiliary(_ item: DiscoveredItem, to destination: URL) async throws {
        try Self.copy(from: item.auxiliaryFile, to: destination, failureMessage: auxiliaryCopyError)
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            for state in states {
                continuation.yield(state)
            }
            continuation.finish()
        }
    }

    private static func copy(from sourceURL: URL?, to destination: URL, failureMessage: String?) throws {
        if let failureMessage {
            throw LumaError.importFailed(failureMessage)
        }

        guard let sourceURL else { return }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }
}

private final class ImportEventRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ImportEventRecorder")
    private var storedProgresses: [ImportProgress] = []
    private var storedSnapshots: [ImportedProjectSnapshot] = []

    func record(progress: ImportProgress) {
        queue.sync {
            storedProgresses.append(progress)
        }
    }

    func record(snapshot: ImportedProjectSnapshot) {
        queue.sync {
            storedSnapshots.append(snapshot)
        }
    }

    func snapshot() -> (progresses: [ImportProgress], snapshots: [ImportedProjectSnapshot]) {
        queue.sync {
            (storedProgresses, storedSnapshots)
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: @escaping () async throws -> Void,
    verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        verify(error)
    }
}
