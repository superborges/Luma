import XCTest
@testable import Luma

@MainActor
final class UITraceTests: XCTestCase {
    func testStandardMetadataTwoArgOverloadReadsFromSharedRegistry() {
        let id = "uitrace.test.shared_registry_overload"
        UIRegistry.shared.register(id: id, kind: "label", frame: CGRect(x: 1, y: 2, width: 3, height: 4), metadata: [:])
        defer { UIRegistry.shared.clear() }

        let meta = UITrace.standardMetadata(for: id)

        XCTAssertEqual(meta["element_id"], id)
        XCTAssertEqual(meta["kind"], "label")
        XCTAssertEqual(meta["frame_x"], "1.0")
    }

    func testStandardMetadataAlwaysIncludesElementID() {
        let registry = UIRegistry()
        let meta = UITrace.standardMetadata(for: "culling.bottom.action.pick", registry: registry)
        XCTAssertEqual(meta["element_id"], "culling.bottom.action.pick")
        XCTAssertNil(meta["kind"], "Without registration the metadata must NOT pretend to know the kind")
        XCTAssertNil(meta["frame_x"])
    }

    func testStandardMetadataIncludesFrameWhenRegistered() {
        let registry = UIRegistry()
        registry.register(
            id: "culling.center.large_image",
            kind: "image",
            frame: CGRect(x: 12.4, y: 84.0, width: 600.5, height: 400.0),
            metadata: ["asset_id": "ABC"]
        )

        let meta = UITrace.standardMetadata(for: "culling.center.large_image", registry: registry)

        XCTAssertEqual(meta["element_id"], "culling.center.large_image")
        XCTAssertEqual(meta["kind"], "image")
        XCTAssertEqual(meta["frame_x"], "12.4")
        XCTAssertEqual(meta["frame_y"], "84.0")
        XCTAssertEqual(meta["frame_w"], "600.5")
        XCTAssertEqual(meta["frame_h"], "400.0")
    }

    func testStandardMetadataMergesBaseWithoutOverridingElementID() {
        let registry = UIRegistry()
        registry.register(id: "x", kind: "button", frame: .zero, metadata: [:])

        let meta = UITrace.standardMetadata(
            for: "x",
            base: ["element_id": "should_be_overridden", "action": "tap"],
            registry: registry
        )

        XCTAssertEqual(meta["element_id"], "x", "Caller-supplied element_id must be overwritten by canonical id")
        XCTAssertEqual(meta["action"], "tap", "Other base keys must be preserved")
        XCTAssertEqual(meta["kind"], "button")
    }

    func testStandardMetadataFrameValuesAreFormattedConsistently() {
        let registry = UIRegistry()
        registry.register(
            id: "rounding",
            kind: "view",
            frame: CGRect(x: 1.0 / 3.0, y: 2.0 / 7.0, width: 100, height: 200),
            metadata: [:]
        )
        let meta = UITrace.standardMetadata(for: "rounding", registry: registry)
        // 1/3 = 0.333… → "0.3"; 2/7 = 0.285… → "0.3"
        XCTAssertEqual(meta["frame_x"], "0.3")
        XCTAssertEqual(meta["frame_y"], "0.3")
        XCTAssertEqual(meta["frame_w"], "100.0")
        XCTAssertEqual(meta["frame_h"], "200.0")
    }
}
