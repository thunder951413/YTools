import XCTest
import YToolsCore

final class FirstKeyBackspacePolicyTests: XCTestCase {
    func testPlainBackspaceAsFirstKeyClearsQueryOnce() {
        var policy = FirstKeyBackspacePolicy()
        policy.beginPresentation()

        XCTAssertTrue(policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: []),
            isEditingText: true,
            hasMarkedText: false
        ))
        XCTAssertFalse(policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: []),
            isEditingText: true,
            hasMarkedText: false
        ))
    }

    func testOtherFirstKeyDisarmsClearBehavior() {
        var policy = FirstKeyBackspacePolicy()
        policy.beginPresentation()

        XCTAssertFalse(policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 0, modifiers: []),
            isEditingText: true,
            hasMarkedText: false
        ))
        XCTAssertFalse(policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: []),
            isEditingText: true,
            hasMarkedText: false
        ))
    }

    func testDoesNotOverrideModifiedBackspaceOrInputMethodComposition() {
        var policy = FirstKeyBackspacePolicy()
        policy.beginPresentation()
        XCTAssertFalse(policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: .option),
            isEditingText: true,
            hasMarkedText: false
        ))

        policy.beginPresentation()
        XCTAssertFalse(policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: []),
            isEditingText: true,
            hasMarkedText: true
        ))
    }
}
