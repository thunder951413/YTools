import XCTest
import YToolsCore

@MainActor
final class DebouncedActionTests: XCTestCase {
    func testOnlyRunsLatestScheduledAction() async {
        let stale = expectation(description: "stale action")
        stale.isInverted = true
        let latest = expectation(description: "latest action")
        let debouncer = DebouncedAction()

        debouncer.schedule(after: .milliseconds(30)) { stale.fulfill() }
        debouncer.schedule(after: .milliseconds(10)) { latest.fulfill() }

        await fulfillment(of: [latest, stale], timeout: 0.12)
    }

    func testCancelPreventsPendingAction() async {
        let action = expectation(description: "cancelled action")
        action.isInverted = true
        let debouncer = DebouncedAction()

        debouncer.schedule(after: .milliseconds(10)) { action.fulfill() }
        debouncer.cancel()

        await fulfillment(of: [action], timeout: 0.06)
    }
}
