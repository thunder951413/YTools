import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var hotKey: HotKeyDefinition

    func makeNSView(context: Context) -> RecorderView {
        RecorderView(hotKey: hotKey) { hotKey = $0 }
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.hotKey = hotKey
        view.onChange = { hotKey = $0 }
        view.needsDisplay = true
    }
}

final class RecorderView: NSView {
    var hotKey: HotKeyDefinition
    var onChange: (HotKeyDefinition) -> Void
    private var isRecording = false

    init(hotKey: HotKeyDefinition, onChange: @escaping (HotKeyDefinition) -> Void) {
        self.hotKey = hotKey
        self.onChange = onChange
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: 30))
        setAccessibilityRole(.button)
        setAccessibilityLabel("录制快捷键")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 170, height: 30) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
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
        window?.makeFirstResponder(nil)
        needsDisplay = true
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
