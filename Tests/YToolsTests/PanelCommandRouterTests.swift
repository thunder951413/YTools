import XCTest
import YToolsCore

final class PanelCommandRouterTests: XCTestCase {
    private let router = PanelCommandRouter()

    func testMapsNumberShortcutsToZeroBasedResults() {
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 18, modifiers: .command),
                mode: .launcher
            ),
            .activateResult(0)
        )
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 25, modifiers: .command),
                mode: .launcher
            ),
            .activateResult(8)
        )
    }

    func testKeepsLauncherOnlyCommandsOutOfClipboardMode() {
        XCTAssertNil(
            router.command(
                for: PanelKeyEvent(keyCode: 16, modifiers: .command),
                mode: .clipboard
            )
        )
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 2, modifiers: .command),
                mode: .clipboard
            ),
            .deleteClipboardItem
        )
    }

    func testOptionArrowsTakePriorityOverNavigation() {
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 125, modifiers: .option),
                mode: .launcher
            ),
            .addSelectedToBuffer(moveToNext: true)
        )
    }

    func testMapsSharedNavigationCommands() {
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 36, modifiers: []),
                mode: .launcher
            ),
            .activateSelected
        )
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 36, modifiers: []),
                mode: .clipboard
            ),
            .activateSelected
        )
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 126, modifiers: []),
                mode: .clipboard
            ),
            .moveSelection(-1)
        )
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 53, modifiers: []),
                mode: .launcher
            ),
            .escape
        )
    }

    func testModifiedReturnKeepsItsDedicatedMeaning() {
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 36, modifiers: .command),
                mode: .launcher
            ),
            .revealSelected
        )
        XCTAssertNil(
            router.command(
                for: PanelKeyEvent(keyCode: 36, modifiers: .shift),
                mode: .launcher
            )
        )
    }

    func testLeavesStandardTextEditingShortcutsToFieldEditor() {
        for keyCode: UInt16 in [0, 6, 7, 8, 9] { // A, Z, X, C, V
            XCTAssertNil(
                router.command(
                    for: PanelKeyEvent(keyCode: keyCode, modifiers: .command),
                    mode: .launcher
                )
            )
        }
    }
}
