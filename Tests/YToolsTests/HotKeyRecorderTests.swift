import AppKit
import Carbon
import XCTest
@testable import YTools

final class HotKeyRecorderTests: XCTestCase {
    @MainActor
    func testAccessiblePressAndEscapeCancelWithoutChangingShortcut() throws {
        var changed = false
        let recorder = RecorderView(hotKey: .launcherDefault, label: "启动器快捷键") { _ in changed = true }
        let window = makeWindow(recorder)
        defer { window.close() }
        XCTAssertTrue(recorder.isAccessibilityElement())
        XCTAssertEqual(recorder.accessibilityLabel(), "启动器快捷键")
        XCTAssertEqual(recorder.accessibilityValue() as? String, HotKeyDefinition.launcherDefault.displayString)
        XCTAssertTrue(recorder.accessibilityPerformPress())
        XCTAssertTrue(recorder.isRecording)
        recorder.keyDown(with: try event(key: UInt16(kVK_Escape)))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(changed)
        XCTAssertEqual(recorder.hotKey, .launcherDefault)
        XCTAssertEqual(recorder.accessibilityValue() as? String, HotKeyDefinition.launcherDefault.displayString)
    }

    @MainActor
    func testRecorderCapturesModifiedKeyOnlyAfterRecordingStarts() throws {
        var changes: [HotKeyDefinition] = []
        let recorder = RecorderView(hotKey: .launcherDefault) { changes.append($0) }
        let window = makeWindow(recorder)
        defer { window.close() }
        recorder.keyDown(with: try event(key: UInt16(kVK_Return)))
        XCTAssertTrue(recorder.isRecording)
        recorder.keyDown(with: try event(key: UInt16(kVK_ANSI_F), modifiers: .command))
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(changes, [HotKeyDefinition(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(cmdKey))])
    }

    @MainActor
    private func makeWindow(_ recorder: RecorderView) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = recorder
        return window
    }

    private func event(key: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: key))
    }
}
