import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private var keyMonitor: Any?

    init(
        preferences: AppPreferences,
        clipboard: ClipboardHistoryManager,
        snippets: SnippetManager,
        recentDocuments: RecentDocumentsManager
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "YTools 设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 720, height: 500)
        // Settings controls become difficult to scan when macOS Zoom stretches
        // rows across an entire display. Keep the window generously resizable,
        // but cap it at a desktop-friendly reading width and height.
        window.maxSize = NSSize(width: 1_100, height: 900)
        window.contentViewController = NSHostingController(
            rootView: SettingsRootView(
                preferences: preferences,
                clipboardManager: clipboard,
                snippets: snippets,
                recentDocuments: recentDocuments
            )
        )
        super.init(window: window)
        window.delegate = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard window.isKeyWindow else { return event }
            if event.keyCode == 13, event.modifierFlags.contains(.command) {
                window.performClose(nil)
                return nil
            }
            if event.keyCode == 3, event.modifierFlags.contains(.command) {
                NotificationCenter.default.post(name: .focusYToolsSettingsSearch, object: nil)
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func show() {
        guard let window else { return }
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
