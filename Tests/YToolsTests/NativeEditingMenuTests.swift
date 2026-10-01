import AppKit
import XCTest
@testable import YTools

final class NativeEditingMenuTests: XCTestCase {
    @MainActor
    func testUndoAndRedoMenuActionsUseEditorsUndoManager() {
        let app = NSApplication.shared
        let oldMenu = app.mainMenu
        let mainMenu = NSMenu()
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 300, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        text.allowsUndo = true
        let editing = NativeEditingMenu.make(undoManager: { text.undoManager })
        mainMenu.addItem(withTitle: "编辑", action: nil, keyEquivalent: "").submenu = editing
        app.mainMenu = mainMenu
        window.contentView = text
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(text)
        defer { window.close(); app.mainMenu = oldMenu }
        text.insertText("fixture", replacementRange: NSRange(location: 0, length: 0))
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        XCTAssertTrue(text.undoManager?.canUndo == true)
        editing.update()
        editing.performActionForItem(at: 0)
        XCTAssertEqual(text.string, "")
        XCTAssertTrue(text.undoManager?.canRedo == true)
        editing.update()
        editing.performActionForItem(at: 1)
        XCTAssertEqual(text.string, "fixture")
    }
}
