import AppKit
import ApplicationServices
import Carbon

/// Pastes into the application that was frontmost before YTools appeared.
/// Requires the Accessibility permission to post ⌘V; without it callers fall
/// back to "copy only" so nothing is lost.
@MainActor
final class PasteService {
    static let shared = PasteService()

    private(set) var previousApplication: NSRunningApplication?

    /// Call before YTools activates itself.
    func rememberFrontmostApplication() {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previousApplication = front
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to Privacy & Security › Accessibility.
    func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Re-activates the previous app and sends ⌘V. Returns false when the
    /// permission is missing or there is no app to paste into.
    @discardableResult
    func pasteIntoPreviousApplication(delay: Duration = .milliseconds(60)) -> Bool {
        guard isTrusted, let application = previousApplication, !application.isTerminated else { return false }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            // Hand activation over explicitly; macOS 14 ignores a plain
            // activate() request coming from an app that is not frontmost.
            NSApp.yieldActivation(to: application)
            application.activate()
            // Send ⌘V only once the target owns the keyboard, otherwise the
            // keystroke lands in YTools or nowhere.
            for _ in 0..<40 where NSWorkspace.shared.frontmostApplication?.processIdentifier != application.processIdentifier {
                try? await Task.sleep(for: .milliseconds(15))
            }
            try? await Task.sleep(for: .milliseconds(40))
            Self.postKeyStroke(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        }
        return true
    }

    private var promptedThisSession = false

    /// Explains why a choice was only copied. The first time in a session it
    /// also opens the system permission prompt.
    func reportPasteUnavailable() {
        guard !isTrusted else {
            ToastPresenter.show("已复制；没有可粘贴的目标应用", systemImage: "doc.on.clipboard")
            return
        }
        ToastPresenter.show("已复制。自动粘贴需要“辅助功能”权限；若列表里已勾选 YTools，请移除后重新添加",
                            systemImage: "hand.raised.fill", duration: .seconds(4))
        if !promptedThisSession {
            promptedThisSession = true
            requestTrust()
        }
    }

    nonisolated static func postKeyStroke(_ key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
