import AppKit
import SwiftUI

@MainActor
final class LargeTypeWindowController: NSWindowController {
    init() {
        let panel = LargeTypePanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(text: String) {
        guard let window, !text.isEmpty else { return }
        window.contentViewController = NSHostingController(rootView: LargeTypeView(text: text))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class LargeTypePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

private struct LargeTypeView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.25)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(56)
                .frame(maxWidth: .infinity, minHeight: 380)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
