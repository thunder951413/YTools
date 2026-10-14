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
    func pasteIntoPreviousApplication(delay: Duration = .milliseconds(80)) -> Bool {
        guard isTrusted, let application = previousApplication, !application.isTerminated else { return false }
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            application.activate()
            try? await Task.sleep(for: .milliseconds(120))
            Self.postKeyStroke(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
        }
        return true
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
