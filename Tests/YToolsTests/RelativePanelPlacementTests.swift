import XCTest
@testable import YToolsCore

final class RelativePanelPlacementTests: XCTestCase {
    func testMapsPositionProportionallyBetweenResolutions() throws {
        let placement = try XCTUnwrap(
            RelativePanelPlacement(
                left: 360,
                top: 681,
                visibleOriginX: 0,
                visibleOriginY: 24,
                visibleWidth: 1_440,
                visibleHeight: 876
            )
        )

        XCTAssertEqual(placement.horizontalFraction, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(placement.topFraction, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(placement.sourceVisibleWidth, 1_440)
        XCTAssertEqual(placement.sourceVisibleHeight, 876)

        XCTAssertEqual(
            placement.resolvedLeft(visibleOriginX: 1_440, visibleWidth: 1_920),
            1_920,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            placement.resolvedTop(visibleOriginY: 0, visibleHeight: 1_080),
            810,
            accuracy: 0.000_001
        )
    }

    func testClampsSavedPositionToUsableAreaFractions() throws {
        let placement = try XCTUnwrap(
            RelativePanelPlacement(
                left: -500,
                top: -500,
                visibleOriginX: 100,
                visibleOriginY: 50,
                visibleWidth: 1_000,
                visibleHeight: 700
            )
        )

        XCTAssertEqual(placement.horizontalFraction, 0)
        XCTAssertEqual(placement.topFraction, 1)
        XCTAssertEqual(placement.resolvedLeft(visibleOriginX: 100, visibleWidth: 1_000), 100)
        XCTAssertEqual(placement.resolvedTop(visibleOriginY: 50, visibleHeight: 700), 50)
    }
}
