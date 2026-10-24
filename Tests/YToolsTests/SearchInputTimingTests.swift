import XCTest
import YToolsCore

final class SearchInputTimingTests: XCTestCase {
    func testFirstKeystrokeAndKeystrokeAfterQuietPeriodSearchImmediately() {
        var timing = SearchInputTiming()
        let start = ContinuousClock.now
        let quiet = Duration.milliseconds(150)

        XCTAssertTrue(timing.isLeadingEdge(at: start, quietPeriod: quiet))
        XCTAssertTrue(timing.isLeadingEdge(at: start.advanced(by: .milliseconds(150)), quietPeriod: quiet))
        XCTAssertTrue(timing.isLeadingEdge(at: start.advanced(by: .milliseconds(900)), quietPeriod: quiet))
    }

    func testKeystrokesInsideTheWindowAreCoalesced() {
        var timing = SearchInputTiming()
        let start = ContinuousClock.now
        let quiet = Duration.milliseconds(150)

        XCTAssertTrue(timing.isLeadingEdge(at: start, quietPeriod: quiet))
        XCTAssertFalse(timing.isLeadingEdge(at: start.advanced(by: .milliseconds(60)), quietPeriod: quiet))
        // The window is measured from the previous keystroke, not the last search.
        XCTAssertFalse(timing.isLeadingEdge(at: start.advanced(by: .milliseconds(180)), quietPeriod: quiet))
        XCTAssertTrue(timing.isLeadingEdge(at: start.advanced(by: .milliseconds(330)), quietPeriod: quiet))
    }
}
