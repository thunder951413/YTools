import XCTest
import YToolsCore

final class SearchPresentationTests: XCTestCase {
    func testPartialProvidersAndNextKeystrokeKeepHeightUntilQueryClears() {
        var state = SearchPresentationState()
        state.beginQuery()
        state.includeResults(count: 1)
        XCTAssertEqual(state.reservedRows, 3)
        state.includeResults(count: 20)
        state.userSelected()
        XCTAssertEqual(state.reservedRows, 6)
        XCTAssertTrue(state.preservesSelection)
        state.beginQuery()
        state.includeResults(count: 0)
        XCTAssertEqual(state.reservedRows, 6)
        XCTAssertFalse(state.preservesSelection)
        state.reset()
        XCTAssertEqual(state.reservedRows, 0)
    }

    func testPagingCountsAllMatchesAndKeepsOlderRecordsReachable() {
        let records = Array(0..<251)
        let first = HistoryPage.select(records, limit: 100) { $0 % 2 == 0 }
        XCTAssertEqual(first.items, Array(stride(from: 0, through: 198, by: 2)))
        XCTAssertEqual(first.totalMatches, 126)
        XCTAssertTrue(first.hasMore)
        let more = HistoryPage.select(records, limit: 200) { $0 % 2 == 0 }
        XCTAssertEqual(Array(more.items.prefix(100)), first.items)
        XCTAssertEqual(more.items.last, 250)
        XCTAssertFalse(more.hasMore)
        let olderOnly = HistoryPage.select(records, limit: 100) { $0 == 250 }
        XCTAssertEqual(olderOnly.items, [250])
        XCTAssertEqual(HistoryPage.select(records, limit: -1) { _ in true }.items, [])
    }
}
