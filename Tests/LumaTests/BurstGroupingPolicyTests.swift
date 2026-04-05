import XCTest
@testable import Luma

final class BurstGroupingPolicyTests: XCTestCase {
    func testSubgroupAssetsMergesShortContinuousSequence() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7001", second: 0),
            makeBurstAsset(baseName: "IMG_7002", second: 2),
            makeBurstAsset(baseName: "IMG_7003", second: 4),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.10,
                    pairKey(assets[0], assets[2]): 0.18,
                    pairKey(assets[1], assets[2]): 0.14,
                ]
            )
        }

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].map(\.id), assets.map(\.id))
    }

    func testSubgroupAssetsRejectsSingleLinkDriftViaCompleteDistance() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7101", second: 0),
            makeBurstAsset(baseName: "IMG_7102", second: 2),
            makeBurstAsset(baseName: "IMG_7103", second: 4),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.10,
                    pairKey(assets[0], assets[2]): 0.20,
                    pairKey(assets[1], assets[2]): 0.41,
                ]
            )
        }

        XCTAssertEqual(groups.map(\.count), [2, 1])
        XCTAssertEqual(groups[0].map(\.id), [assets[0].id, assets[1].id])
        XCTAssertEqual(groups[1].map(\.id), [assets[2].id])
    }

    func testSubgroupAssetsSplitsWhenBurstSpanExceedsThreshold() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7201", second: 0),
            makeBurstAsset(baseName: "IMG_7202", second: 9),
            makeBurstAsset(baseName: "IMG_7203", second: 18),
            makeBurstAsset(baseName: "IMG_7204", second: 27),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.09,
                    pairKey(assets[0], assets[2]): 0.15,
                    pairKey(assets[1], assets[2]): 0.12,
                    pairKey(assets[0], assets[3]): 0.13,
                    pairKey(assets[1], assets[3]): 0.16,
                    pairKey(assets[2], assets[3]): 0.14,
                ]
            )
        }

        XCTAssertEqual(groups.map(\.count), [3, 1])
        XCTAssertEqual(groups[0].map(\.id), [assets[0].id, assets[1].id, assets[2].id])
        XCTAssertEqual(groups[1].map(\.id), [assets[3].id])
    }

    func testSubgroupAssetsSplitsWhenOrientationChanges() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7301", second: 0, width: 6000, height: 4000),
            makeBurstAsset(baseName: "IMG_7302", second: 2, width: 4000, height: 6000),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.08,
                ]
            )
        }

        XCTAssertEqual(groups.map(\.count), [1, 1])
    }

    func testSubgroupAssetsAllowsElevenSecondGapWithinBurstWindow() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7401", second: 0),
            makeBurstAsset(baseName: "IMG_7402", second: 11),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.10,
                ]
            )
        }

        XCTAssertEqual(groups.map(\.count), [2])
    }

    func testSubgroupAssetsAllowsBorderlineDistanceForSingletonPair() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7501", second: 0),
            makeBurstAsset(baseName: "IMG_7502", second: 11),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.34,
                ]
            )
        }

        XCTAssertEqual(groups.map(\.count), [2])
    }

    func testSubgroupAssetsStillRejectsBorderlineAnchorForMultiImageBurst() {
        let assets = [
            makeBurstAsset(baseName: "IMG_7601", second: 0),
            makeBurstAsset(baseName: "IMG_7602", second: 2),
            makeBurstAsset(baseName: "IMG_7603", second: 4),
        ]

        let groups = BurstGroupingPolicy().subgroupAssets(in: assets) { lhs, rhs in
            distance(
                between: lhs,
                and: rhs,
                mapping: [
                    pairKey(assets[0], assets[1]): 0.10,
                    pairKey(assets[0], assets[2]): 0.34,
                    pairKey(assets[1], assets[2]): 0.18,
                ]
            )
        }

        XCTAssertEqual(groups.map(\.count), [2, 1])
    }
}

private func makeBurstAsset(
    baseName: String,
    second: Int,
    focalLength: Double = 50,
    width: Int = 6000,
    height: Int = 4000
) -> MediaAsset {
    MediaAsset(
        id: UUID(),
        importResumeKey: baseName.lowercased(),
        baseName: baseName,
        source: .folder(path: "/tmp/source"),
        previewURL: nil,
        rawURL: nil,
        livePhotoVideoURL: nil,
        depthData: false,
        thumbnailURL: nil,
        metadata: EXIFData(
            captureDate: TestFixtures.makeDate(hour: 9, minute: 0, second: second),
            gpsCoordinate: nil,
            focalLength: focalLength,
            aperture: 2.8,
            shutterSpeed: "1/250",
            iso: 100,
            cameraModel: "Test Camera",
            lensModel: "Test Lens",
            imageWidth: width,
            imageHeight: height
        ),
        mediaType: .photo,
        importState: .complete,
        aiScore: nil,
        editSuggestions: nil,
        userDecision: .pending,
        userRating: nil,
        issues: []
    )
}

private func pairKey(_ lhs: MediaAsset, _ rhs: MediaAsset) -> String {
    [lhs.id.uuidString, rhs.id.uuidString].sorted().joined(separator: "|")
}

private func distance(
    between lhs: MediaAsset,
    and rhs: MediaAsset,
    mapping: [String: Float]
) -> Float? {
    if lhs.id == rhs.id {
        return 0
    }
    return mapping[pairKey(lhs, rhs)]
}
