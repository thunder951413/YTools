import AppKit

/// Standard fixed responder actions keep native editor shortcuts available in
/// the accessory app, which has no storyboard-provided application menu.
@MainActor
final class NativeEditingMenu: NSMenu, NSMenuItemValidation {
    private var currentUndoManager: () -> UndoManager? = {
        NSApp.keyWindow?.firstResponder?.undoManager ?? NSApp.keyWindow?.undoManager
    }

    static func make(undoManager: (() -> UndoManager?)? = nil) -> NSMenu {
        let menu = NativeEditingMenu(title: "编辑")
        if let undoManager { menu.currentUndoManager = undoManager }
        menu.addItem(withTitle: "撤销", action: #selector(undo(_:)), keyEquivalent: "z").target = menu
        let redo = menu.addItem(withTitle: "重做", action: #selector(redo(_:)), keyEquivalent: "Z")
        redo.target = menu
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    @objc private func undo(_ sender: Any?) { currentUndoManager()?.undo() }
    @objc private func redo(_ sender: Any?) { currentUndoManager()?.redo() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) { return currentUndoManager()?.canUndo == true }
        if menuItem.action == #selector(redo(_:)) { return currentUndoManager()?.canRedo == true }
        return true
    }
}
