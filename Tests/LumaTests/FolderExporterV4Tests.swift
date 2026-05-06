import Foundation
import Testing

@testable import Luma

@Suite("FolderExporter V4 Tests")
struct FolderExporterV4Tests {

    private func makeMasterAsset(
        id: UUID = UUID(),
        baseName: String = "IMG_001",
        previewURL: URL? = nil,
        captureDate: Date = Date(),
        cameraModel: String? = nil,
        lensModel: String? = nil,
        iso: Int? = nil,
        focalLength: Double? = nil,
        aperture: Double? = nil
    ) -> MasterAsset? {
        let now = Date().timeIntervalSinceReferenceDate
        let record = MasterAssetRecord(
            id: id.uuidString,
            sourceId: nil, sourceKind: "sdCard", storageMode: "managed",
            externalIdentifier: nil,
            originalURL: previewURL?.absoluteString,
            localManagedURL: nil,
            previewURL: previewURL?.absoluteString,
            rawURL: nil, livePhotoVideoURL: nil,
            thumbnailCacheURL: nil, previewCacheURL: nil,
            fingerprint: nil, contentHash: nil,
            baseName: baseName, mediaType: "photo",
            captureDate: captureDate.timeIntervalSinceReferenceDate,
            latitude: nil, longitude: nil,
            focalLength: focalLength, aperture: aperture,
            shutterSpeed: nil, iso: iso,
            cameraModel: cameraModel, lensModel: lensModel,
            imageWidth: cameraModel != nil ? 4000 : nil,
            imageHeight: cameraModel != nil ? 3000 : nil,
            createdAt: now, updatedAt: now
        )
        return MasterAsset(record: record)
    }

    @Test("Export MasterAssets to byDate folder template")
    func testExportByDate() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderExporterV4Test_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("IMG_001.jpg")
        try Data("fake-image".utf8).write(to: sourceFile)

        guard let asset = makeMasterAsset(baseName: "IMG_001", previewURL: sourceFile) else {
            Issue.record("Failed to create MasterAsset")
            return
        }

        let outputDir = tmpDir.appendingPathComponent("output")
        var opts = ExportOptions.default
        opts.outputPath = outputDir
        opts.folderTemplate = .byDate
        opts.fileNamingRule = .original
        opts.writeXmpSidecar = false

        let exporter = FolderExporter()
        let result = try await exporter.export(
            masterAssets: [asset],
            groups: [],
            options: opts
        )

        #expect(result.exportedCount == 1)
        #expect(result.failures.isEmpty)
        #expect(result.destinationURL == outputDir)
    }

    @Test("Export with byGroup folder template creates Ungrouped dir")
    func testExportByGroup() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderExporterV4Test_group_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("IMG_002.jpg")
        try Data("fake-image-2".utf8).write(to: sourceFile)

        guard let asset = makeMasterAsset(baseName: "IMG_002", previewURL: sourceFile) else {
            Issue.record("Failed to create MasterAsset")
            return
        }

        let outputDir = tmpDir.appendingPathComponent("output")
        var opts = ExportOptions.default
        opts.outputPath = outputDir
        opts.folderTemplate = .byGroup
        opts.fileNamingRule = .original
        opts.writeXmpSidecar = false

        let exporter = FolderExporter()
        let result = try await exporter.export(
            masterAssets: [asset],
            groups: [],
            options: opts
        )

        #expect(result.exportedCount == 1)
        let ungroupedDir = outputDir.appendingPathComponent("Ungrouped")
        #expect(FileManager.default.fileExists(atPath: ungroupedDir.path))
    }

    @Test("Export writes XMP sidecar for MasterAsset")
    func testExportWritesXMP() async throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderExporterV4Test_xmp_\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let sourceDir = tmpDir.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let sourceFile = sourceDir.appendingPathComponent("IMG_003.jpg")
        try Data("fake-image-3".utf8).write(to: sourceFile)

        guard let asset = makeMasterAsset(
            baseName: "IMG_003",
            previewURL: sourceFile,
            cameraModel: "Sony A7C",
            lensModel: "35mm F2.8",
            iso: 200,
            focalLength: 35.0,
            aperture: 2.8
        ) else {
            Issue.record("Failed to create MasterAsset")
            return
        }

        let outputDir = tmpDir.appendingPathComponent("output")
        var opts = ExportOptions.default
        opts.outputPath = outputDir
        opts.folderTemplate = .byDate
        opts.fileNamingRule = .original
        opts.writeXmpSidecar = true

        let exporter = FolderExporter()
        let result = try await exporter.export(
            masterAssets: [asset],
            groups: [],
            ratings: [asset.id: 4],
            options: opts
        )

        #expect(result.exportedCount == 1)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateDir = outputDir.appendingPathComponent(dateFormatter.string(from: Date()))
        let xmpFile = dateDir.appendingPathComponent("IMG_003.xmp")
        #expect(FileManager.default.fileExists(atPath: xmpFile.path))

        let xmpContent = try String(contentsOf: xmpFile, encoding: .utf8)
        #expect(xmpContent.contains("xmp:Rating=\"4\""))
        #expect(xmpContent.contains("Sony A7C"))
    }

    @Test("XMPWriter MasterAsset generates valid XMP with group and rating")
    func testXMPWriterMasterAsset() {
        guard let asset = makeMasterAsset(
            baseName: "test",
            cameraModel: "Nikon Z6"
        ) else {
            Issue.record("Failed to create MasterAsset")
            return
        }

        let xmp = XMPWriter.xmpForMasterAsset(asset, groupName: "Morning", rating: 5)
        #expect(xmp.contains("xmp:Rating=\"5\""))
        #expect(xmp.contains("Nikon Z6"))
        #expect(xmp.contains("Morning"))
    }
}
