import AppKit

/// Full-screen overlay showing a frozen screenshot. Drag to select a region;
/// Return or mouse-up confirms, Esc cancels. The completion receives the
/// cropped image in pixel space, or nil when cancelled.
@MainActor
final class RegionSelectionWindow: NSPanel {
    private let completion: (CGImage?) -> Void
    private var finished = false

    init(screen: NSScreen, image: CGImage, completion: @escaping (CGImage?) -> Void) {
        self.completion = completion
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = true
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        let view = RegionSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image)
        view.onFinish = { [weak self] cropped in self?.finish(cropped) }
        contentView = view
        setFrame(screen.frame, display: true)
        makeFirstResponder(view)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { finish(nil) }

    private func finish(_ image: CGImage?) {
        guard !finished else { return }
        finished = true
        completion(image)
    }
}

@MainActor
private final class RegionSelectionView: NSView {
    private let image: CGImage
    private var start: NSPoint?
    private var current: NSPoint?
    var onFinish: ((CGImage?) -> Void)?

    init(frame: NSRect, image: CGImage) {
        self.image = image
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(start.x - current.x), height: abs(start.y - current.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)
        context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
        if let selection, selection.width > 1, selection.height > 1 {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(selection)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(1)
            context.stroke(selection.insetBy(dx: 0.5, dy: 0.5))
            let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
            label.draw(at: NSPoint(x: selection.minX, y: max(selection.minY - 18, 4)), withAttributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            ])
        } else {
            context.fill(bounds)
            let hint = "拖动选择要识别文字的区域 · Esc 取消" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 15, weight: .medium)
            ]
            let size = hint.size(withAttributes: attributes)
            hint.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - 80), withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        guard let selection, selection.width >= 4, selection.height >= 4 else {
            start = nil
            current = nil
            needsDisplay = true
            return
        }
        onFinish?(crop(selection))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(nil) } else { super.keyDown(with: event) }
    }

    /// View points (origin bottom-left) → image pixels (origin top-left).
    private func crop(_ rect: NSRect) -> CGImage? {
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let pixelRect = CGRect(
            x: rect.minX * scaleX,
            y: (bounds.height - rect.maxY) * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ).integral
        return image.cropping(to: pixelRect)
    }
}
