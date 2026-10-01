import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var hotKey: HotKeyDefinition
    var label = "启动器快捷键"

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(hotKey: hotKey, label: label) { hotKey = $0 }
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.hotKey = hotKey
        view.setAccessibilityLabel(label)
        view.onChange = { hotKey = $0 }
        view.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var hotKey: HotKeyDefinition { didSet { refreshAccessibilityValue() } }
    var onChange: (HotKeyDefinition) -> Void
    private(set) var isRecording = false

    init(hotKey: HotKeyDefinition, label: String = "录制快捷键", onChange: @escaping (HotKeyDefinition) -> Void) {
        self.hotKey = hotKey
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: 30))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
        setAccessibilityHelp("按 Return 或 Space 开始录制，Esc 取消；组合键须包含 Command、Option 或 Control。")
        refreshAccessibilityValue()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 30) }

    override func mouseDown(with event: NSEvent) {
        _ = beginRecording()
    }

    override func accessibilityPerformPress() -> Bool { beginRecording() }

    private func beginRecording() -> Bool {
        guard window?.makeFirstResponder(self) == true else { return false }
        isRecording = true
        refreshAccessibilityValue()
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshAccessibilityValue()
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            refreshAccessibilityValue()
            window?.makeFirstResponder(nil)
            needsDisplay = true
            return
        }
        if event.keyCode == UInt16(kVK_Tab) {
            isRecording = false
            refreshAccessibilityValue()
            needsDisplay = true
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(nil) }
            else { window?.selectNextKeyView(nil) }
            return
        }
        guard isRecording else {
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_Space) { _ = beginRecording() }
            else { super.keyDown(with: event) }
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }

        let primaryModifiers = UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        guard modifiers & primaryModifiers != 0,
              !Self.modifierOnlyKeyCodes.contains(event.keyCode) else {
            NSSound.beep()
            return
        }
        let definition = HotKeyDefinition(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        hotKey = definition
        onChange(definition)
        isRecording = false
        refreshAccessibilityValue()
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }

    private func refreshAccessibilityValue() {
        setAccessibilityValue(isRecording ? "正在录制，Esc 取消" : hotKey.displayString)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "请按新的组合键…" : hotKey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }

    private static let modifierOnlyKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}
