import Foundation
import XCTest
@testable import Luma

@MainActor
final class ImportSourceMonitorTests: XCTestCase {
    func testPollNowDetectsOnlyNewSourcesAndDeduplicatesKnownOnes() async {
        let sd = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/CARD_A", displayName: "CARD_A")
        let phone = ImportSourceDescriptor.iPhone(deviceID: "phone-1", deviceName: "Alice iPhone")
        let secondSD = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/CARD_B", displayName: "CARD_B")
        let sequence = SourceSequence([
            [sd, phone],
            [sd, phone],
            [phone, secondSD],
        ])

        let monitor = ImportSourceMonitor(detectSources: {
            await sequence.next()
        })
        monitor.setKnownSourcesForTesting([sd])

        let collector = DetectedSourceCollector()
        await monitor.pollNowForTesting { source in
            collector.record(source)
        }
        await monitor.pollNowForTesting { source in
            collector.record(source)
        }
        await monitor.pollNowForTesting { source in
            collector.record(source)
        }

        let detected = collector.snapshot()
        XCTAssertEqual(detected.map(\.stableID), [phone.stableID, secondSD.stableID])
    }

    func testStopClearsKnownSourcesSoExistingSourceCanBeDetectedAgain() async {
        let sd = ImportSourceDescriptor.sdCard(volumePath: "/Volumes/CARD_A", displayName: "CARD_A")
        let sequence = SourceSequence([[sd]])
        let monitor = ImportSourceMonitor(detectSources: {
            await sequence.next()
        })

        monitor.setKnownSourcesForTesting([sd])
        monitor.stop()

        let collector = DetectedSourceCollector()
        await monitor.pollNowForTesting { source in
            collector.record(source)
        }

        let detected = collector.snapshot()
        XCTAssertEqual(detected.map(\.stableID), [sd.stableID])
    }
}

private actor SourceSequence {
    private let snapshots: [[ImportSourceDescriptor]]
    private var index = 0

    init(_ snapshots: [[ImportSourceDescriptor]]) {
        self.snapshots = snapshots
    }

    func next() -> [ImportSourceDescriptor] {
        guard !snapshots.isEmpty else { return [] }
        let value = snapshots[min(index, snapshots.count - 1)]
        index += 1
        return value
    }
}

private final class DetectedSourceCollector: @unchecked Sendable {
    private let queue = DispatchQueue(label: "DetectedSourceCollector")
    private var sources: [ImportSourceDescriptor] = []

    func record(_ source: ImportSourceDescriptor) {
        queue.sync {
            sources.append(source)
        }
    }

    func snapshot() -> [ImportSourceDescriptor] {
        queue.sync {
            sources
        }
    }
}
