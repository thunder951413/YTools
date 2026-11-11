import XCTest
import YToolsCore

final class PanelCommandRouterTests: XCTestCase {
    private let router = PanelCommandRouter()

    func testClipboardPreviewShortcutOnlyMatchesItsExactModifiers() {
        XCTAssertEqual(router.command(for: PanelKeyEvent(keyCode: 35, modifiers: .command), mode: .clipboard), .toggleClipboardPreview)
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 35, modifiers: [.command, .shift]), mode: .clipboard))
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 35, modifiers: .command), mode: .launcher))
    }

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
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 29, modifiers: .command),
                mode: .launcher
            ),
            .activateResult(9)
        )
        XCTAssertEqual(
            router.command(
                for: PanelKeyEvent(keyCode: 29, modifiers: .command),
                mode: .clipboard
            ),
            .activateResult(9)
        )
    }

    func testExactModifierMatchingDoesNotHijackSelectionOrCombinedModifiers() {
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 123, modifiers: .shift), mode: .launcher))
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 124, modifiers: .shift), mode: .launcher))
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 125, modifiers: .shift), mode: .launcher))
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 18, modifiers: [.command, .option]), mode: .launcher))
        XCTAssertNil(router.command(for: PanelKeyEvent(keyCode: 125, modifiers: [.command, .option]), mode: .launcher))
    }

    func testClipboardCopyOnlyAndNumberShortcuts() {
        XCTAssertEqual(router.command(for: PanelKeyEvent(keyCode: 36, modifiers: .command), mode: .clipboard),
                       .copyClipboardItemOnly)
        XCTAssertEqual(router.command(for: PanelKeyEvent(keyCode: 36, modifiers: .command), mode: .launcher),
                       .revealSelected)
        XCTAssertEqual(router.command(for: PanelKeyEvent(keyCode: 18, modifiers: .command), mode: .clipboard),
                       .activateResult(0))
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
