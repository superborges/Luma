import XCTest
@testable import Luma

final class GroupingEngineTests: XCTestCase {
    func testMakeGroupsSplitsByTimeGap() async {
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_0001",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 0)
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_0002",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 15)
        )
        let asset3 = TestFixtures.makeAsset(
            baseName: "IMG_0003",
            captureDate: TestFixtures.makeDate(hour: 10, minute: 5)
        )

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: [asset3, asset1, asset2])

        // Small scene chunks merge across sub-90min gap when GPS does not block.
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assets, [asset1.id, asset2.id, asset3.id])
        XCTAssertEqual(groups[0].name, "4月4日·上午")
    }

    func testMakeGroupsSplitsByDBSCANLocationClusters() async {
        let locationA = Coordinate(latitude: 31.2304, longitude: 121.4737)
        let locationANear1 = Coordinate(latitude: 31.2305, longitude: 121.4738)
        let locationANear2 = Coordinate(latitude: 31.2306, longitude: 121.4736)
        let locationB = Coordinate(latitude: 31.2450, longitude: 121.4737)
        let locationBNear1 = Coordinate(latitude: 31.2451, longitude: 121.4738)
        let locationBNear2 = Coordinate(latitude: 31.2452, longitude: 121.4736)

        let asset1 = TestFixtures.makeAsset(baseName: "IMG_0101", captureDate: TestFixtures.makeDate(hour: 14, minute: 0), coordinate: locationA)
        let asset2 = TestFixtures.makeAsset(baseName: "IMG_0102", captureDate: TestFixtures.makeDate(hour: 14, minute: 1), coordinate: locationANear1)
        let asset3 = TestFixtures.makeAsset(baseName: "IMG_0103", captureDate: TestFixtures.makeDate(hour: 14, minute: 2), coordinate: locationANear2)
        let asset4 = TestFixtures.makeAsset(baseName: "IMG_0104", captureDate: TestFixtures.makeDate(hour: 14, minute: 8), coordinate: locationB)
        let asset5 = TestFixtures.makeAsset(baseName: "IMG_0105", captureDate: TestFixtures.makeDate(hour: 14, minute: 9), coordinate: locationBNear1)
        let asset6 = TestFixtures.makeAsset(baseName: "IMG_0106", captureDate: TestFixtures.makeDate(hour: 14, minute: 10), coordinate: locationBNear2)

        let namingProvider = StubLocationNamingProvider(names: [
            locationKey(for: locationA): "外滩",
            locationKey(for: locationB): "南京东路",
        ])

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: namingProvider,
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: [asset1, asset2, asset3, asset4, asset5, asset6])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].assets, [asset1.id, asset2.id, asset3.id])
        XCTAssertEqual(groups[1].assets, [asset4.id, asset5.id, asset6.id])
        XCTAssertEqual(groups[0].name, "外滩·下午")
        XCTAssertEqual(groups[1].name, "南京东路·下午")
    }

    func testMakeGroupsKeepsSameLocationAcrossSoftTimeGap() async {
        let location = Coordinate(latitude: 39.9163, longitude: 116.3972)
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_1101",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 0),
            coordinate: location
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_1102",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 40),
            coordinate: location
        )

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(names: [
                locationKey(for: location): "故宫",
            ]),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: [asset1, asset2])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assets, [asset1.id, asset2.id])
        XCTAssertEqual(groups[0].name, "故宫·上午")
    }

    func testMakeGroupsKeepsSameSceneAcrossSoftTimeGapWithoutGPS() async {
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_1201",
            captureDate: TestFixtures.makeDate(hour: 10, minute: 0)
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_1202",
            captureDate: TestFixtures.makeDate(hour: 10, minute: 42)
        )

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(),
            visualSubgroupingProvider: StubVisualSubgroupingProvider(
                continuityDistances: [
                    continuityKey(lhs: [asset1.id], rhs: [asset2.id]): 0.42,
                ]
            )
        ).makeGroups(from: [asset1, asset2])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assets, [asset1.id, asset2.id])
    }

    func testMakeGroupsSplitsAcrossHardTimeGapEvenAtSameLocation() async {
        let location = Coordinate(latitude: 39.9163, longitude: 116.3972)
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_1301",
            captureDate: TestFixtures.makeDate(hour: 9, minute: 0),
            coordinate: location
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_1302",
            captureDate: TestFixtures.makeDate(hour: 11, minute: 5),
            coordinate: location
        )

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(names: [
                locationKey(for: location): "故宫",
            ]),
            visualSubgroupingProvider: StubVisualSubgroupingProvider(
                continuityDistances: [
                    continuityKey(lhs: [asset1.id], rhs: [asset2.id]): 0.35,
                ]
            )
        ).makeGroups(from: [asset1, asset2])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.name), ["故宫·上午", "故宫·上午·2"])
    }

    func testMakeGroupsBuildsVisualBurstSubgroups() async throws {
        let recommendedScore = TestFixtures.makeAIScore(overall: 93, recommended: true)
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_0201",
            captureDate: TestFixtures.makeDate(hour: 16, minute: 0),
            aiScore: recommendedScore
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_0202",
            captureDate: TestFixtures.makeDate(hour: 16, minute: 1),
            aiScore: TestFixtures.makeAIScore(overall: 72, recommended: false)
        )
        let asset3 = TestFixtures.makeAsset(
            baseName: "IMG_0203",
            captureDate: TestFixtures.makeDate(hour: 16, minute: 2),
            aiScore: TestFixtures.makeAIScore(overall: 88, recommended: false)
        )

        let subgroupingProvider = StubVisualSubgroupingProvider(groups: [
            [asset1.id, asset2.id],
            [asset3.id],
        ])

        let grouped = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(),
            visualSubgroupingProvider: subgroupingProvider
        ).makeGroups(from: [asset1, asset2, asset3])
        let group = try XCTUnwrap(grouped.first)

        XCTAssertEqual(group.subGroups.count, 2)
        XCTAssertEqual(group.subGroups[0].assets, [asset1.id, asset2.id])
        XCTAssertEqual(group.subGroups[0].bestAsset, asset1.id)
        XCTAssertEqual(group.subGroups[1].assets, [asset3.id])
        XCTAssertEqual(group.subGroups[1].bestAsset, asset3.id)
        XCTAssertEqual(group.recommendedAssets, [asset1.id])
    }

    func testMergeSmallGroupsPrefersCloserNeighbor() async {
        let base = TestFixtures.makeDate(hour: 9, minute: 0)
        let chunk1 = (0 ..< 4).map { minute in
            TestFixtures.makeAsset(
                baseName: "IMG_M1_\(minute)",
                captureDate: Calendar.current.date(byAdding: .minute, value: minute, to: base)!,
            )
        }
        let gapStart = Calendar.current.date(byAdding: .minute, value: 37, to: chunk1[3].metadata.captureDate)!
        let chunk2 = [0, 1].map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_M2_\(offset)",
                captureDate: Calendar.current.date(byAdding: .minute, value: offset, to: gapStart)!,
            )
        }
        let gapStart3 = Calendar.current.date(byAdding: .minute, value: 39, to: chunk2[1].metadata.captureDate)!
        let chunk3 = (0 ..< 4).map { minute in
            TestFixtures.makeAsset(
                baseName: "IMG_M3_\(minute)",
                captureDate: Calendar.current.date(byAdding: .minute, value: minute, to: gapStart3)!,
            )
        }

        let allAssets = chunk1 + chunk2 + chunk3
        let groups = await GroupingEngine(
            minimumGroupSize: 4,
            wideMergeMaxGroupSize: 4,
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: allAssets)

        XCTAssertEqual(groups.count, 2)
        // Middle pair merges into previous chunk (37m gap vs 39m to next).
        XCTAssertEqual(groups[0].assets.count, 6)
        XCTAssertEqual(groups[1].assets.count, 4)
    }

    func testSmallGroupNotMergedWhenGapExceedsMergeThreshold() async {
        let base = TestFixtures.makeDate(hour: 9, minute: 0)
        let asset1 = TestFixtures.makeAsset(baseName: "IMG_G1", captureDate: base)
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_G2",
            captureDate: Calendar.current.date(byAdding: .minute, value: 1, to: base)!,
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestFixtures.shanghaiTimeZone
        // > wideMergeWindow (30d) so neither short nor wide merge applies; > 30min scene split.
        let asset3 = TestFixtures.makeAsset(
            baseName: "IMG_G3",
            captureDate: calendar.date(byAdding: .day, value: 32, to: asset2.metadata.captureDate)!,
        )
        let asset4 = TestFixtures.makeAsset(
            baseName: "IMG_G4",
            captureDate: calendar.date(byAdding: .minute, value: 1, to: asset3.metadata.captureDate)!,
        )

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: [asset1, asset2, asset3, asset4])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].assets, [asset1.id, asset2.id])
        XCTAssertEqual(groups[1].assets, [asset3.id, asset4.id])
    }

    func testWideMergeSameLocationWithin30Days() async {
        let location = Coordinate(latitude: 39.9163, longitude: 116.3972)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestFixtures.shanghaiTimeZone
        let day1 = TestFixtures.makeDate(hour: 10, minute: 0)
        let chunk1 = (0 ..< 3).map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_W1_\(offset)",
                captureDate: calendar.date(byAdding: .minute, value: offset, to: day1)!,
                coordinate: location,
            )
        }
        let day2 = calendar.date(byAdding: .day, value: 10, to: day1)!
        let chunk2 = (0 ..< 3).map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_W2_\(offset)",
                captureDate: calendar.date(byAdding: .minute, value: offset, to: day2)!,
                coordinate: location,
            )
        }

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(names: [
                locationKey(for: location): "故宫",
            ]),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: chunk1 + chunk2)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assets.count, 6)
        XCTAssertTrue(groups[0].name.contains("故宫"))
        XCTAssertTrue(groups[0].name.contains("多次"))
    }

    func testWideMergeNoGPSWithin30Days() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestFixtures.shanghaiTimeZone
        let day1 = TestFixtures.makeDate(hour: 11, minute: 0)
        let chunk1 = (0 ..< 2).map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_N1_\(offset)",
                captureDate: calendar.date(byAdding: .minute, value: offset, to: day1)!,
            )
        }
        let day2 = calendar.date(byAdding: .day, value: 5, to: day1)!
        let chunk2 = (0 ..< 2).map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_N2_\(offset)",
                captureDate: calendar.date(byAdding: .minute, value: offset, to: day2)!,
            )
        }

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: chunk1 + chunk2)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].assets.count, 4)
        XCTAssertTrue(groups[0].name.contains("多日"))
    }

    func testWideMergeDoesNotJoinDifferentLocations() async {
        let locationA = Coordinate(latitude: 31.2304, longitude: 121.4737)
        let locationB = Coordinate(latitude: 31.2450, longitude: 121.4737)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TestFixtures.shanghaiTimeZone
        let day1 = TestFixtures.makeDate(hour: 15, minute: 0)
        let chunkA = (0 ..< 3).map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_D1_\(offset)",
                captureDate: calendar.date(byAdding: .minute, value: offset, to: day1)!,
                coordinate: locationA,
            )
        }
        let day2 = calendar.date(byAdding: .day, value: 3, to: day1)!
        let chunkB = (0 ..< 3).map { offset in
            TestFixtures.makeAsset(
                baseName: "IMG_D2_\(offset)",
                captureDate: calendar.date(byAdding: .minute, value: offset, to: day2)!,
                coordinate: locationB,
            )
        }

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(names: [
                locationKey(for: locationA): "外滩",
                locationKey(for: locationB): "南京东路",
            ]),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: chunkA + chunkB)

        XCTAssertEqual(groups.count, 2)
    }

    func testMakeGroupsAddsOrdinalSuffixWhenBaseNamesCollide() async {
        let locationA = Coordinate(latitude: 31.2304, longitude: 121.4737)
        let locationB = Coordinate(latitude: 31.2450, longitude: 121.4737)
        let asset1 = TestFixtures.makeAsset(
            baseName: "IMG_0301",
            captureDate: TestFixtures.makeDate(hour: 19, minute: 24),
            coordinate: locationA
        )
        let asset2 = TestFixtures.makeAsset(
            baseName: "IMG_0302",
            captureDate: TestFixtures.makeDate(hour: 19, minute: 25),
            coordinate: locationA
        )
        let asset3 = TestFixtures.makeAsset(
            baseName: "IMG_0303",
            captureDate: TestFixtures.makeDate(hour: 19, minute: 26),
            coordinate: locationA
        )
        let asset4 = TestFixtures.makeAsset(
            baseName: "IMG_0304",
            captureDate: TestFixtures.makeDate(hour: 19, minute: 27),
            coordinate: locationB
        )
        let asset5 = TestFixtures.makeAsset(
            baseName: "IMG_0305",
            captureDate: TestFixtures.makeDate(hour: 19, minute: 28),
            coordinate: locationB
        )
        let asset6 = TestFixtures.makeAsset(
            baseName: "IMG_0306",
            captureDate: TestFixtures.makeDate(hour: 19, minute: 29),
            coordinate: locationB
        )

        let groups = await GroupingEngine(
            namingTimeZone: TestFixtures.shanghaiTimeZone,
            locationNamingProvider: StubLocationNamingProvider(names: [
                locationKey(for: locationA): "外滩",
                locationKey(for: locationB): "外滩",
            ]),
            visualSubgroupingProvider: StubVisualSubgroupingProvider()
        ).makeGroups(from: [asset1, asset2, asset3, asset4, asset5, asset6])

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.map(\.name), ["外滩·夜晚", "外滩·夜晚·2"])
    }
}

private struct StubLocationNamingProvider: GroupLocationNamingProvider {
    var names: [String: String] = [:]

    func name(for coordinate: Coordinate) async -> String? {
        names[locationKey(for: coordinate)]
    }
}

private struct StubVisualSubgroupingProvider: VisualSubgroupingProvider {
    var groups: [[UUID]] = []
    var continuityDistances: [String: Float] = [:]

    func continuityDistance(between lhs: [MediaAsset], and rhs: [MediaAsset]) async -> Float? {
        continuityDistances[continuityKey(lhs: lhs.map(\.id), rhs: rhs.map(\.id))]
    }

    func subgroupAssets(in assets: [MediaAsset]) async -> [[MediaAsset]] {
        guard !groups.isEmpty else {
            return assets.map { [$0] }
        }

        let lookup = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        return groups.map { subgroupIDs in
            subgroupIDs.compactMap { lookup[$0] }
        }
    }
}

private func locationKey(for coordinate: Coordinate) -> String {
    String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
}

private func continuityKey(lhs: [UUID], rhs: [UUID]) -> String {
    let lhsKey = lhs.map(\.uuidString).sorted().joined(separator: ",")
    let rhsKey = rhs.map(\.uuidString).sorted().joined(separator: ",")
    return [lhsKey, rhsKey].sorted().joined(separator: "|")
}
