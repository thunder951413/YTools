import AppKit
import SwiftUI

/// A short, non-activating confirmation bubble near the top of the screen.
@MainActor
enum ToastPresenter {
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ message: String, systemImage: String = "checkmark.circle.fill", duration: Duration = .milliseconds(1_800)) {
        let panel = Self.panel ?? makePanel()
        Self.panel = panel
        let hosting = NSHostingView(rootView: ToastView(message: message, systemImage: systemImage))
        panel.contentView = hosting
        let size = hosting.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 48,
                                  width: size.width, height: size.height), display: true)
        }
        panel.orderFrontRegardless()
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            Self.panel?.orderOut(nil)
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }
}

private struct ToastView: View {
    let message: String
    let systemImage: String

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .fixedSize()
            .padding(6)
    }
}
