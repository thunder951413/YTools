import Foundation

/// Host-side validation for source-compiled modules. Capability declarations
/// are not trusted by themselves; the host must also grant each capability.
public struct ModuleResultPolicy: Sendable {
    public let allowedCapabilities: Set<ModuleCapability>
    public let scoreRange: ClosedRange<Int>
    public let allowsPrivilegedActions: Bool

    public init(
        allowedCapabilities: Set<ModuleCapability> = [],
        scoreRange: ClosedRange<Int> = -10_000...10_000,
        allowsPrivilegedActions: Bool = false
    ) {
        self.allowedCapabilities = allowedCapabilities
        self.scoreRange = scoreRange
        self.allowsPrivilegedActions = allowsPrivilegedActions
    }

    public func permits(_ descriptor: ModuleDescriptor) -> Bool {
        guard !descriptor.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              descriptor.id.count <= 100,
              !descriptor.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              descriptor.name.count <= 200,
              descriptor.capabilities.isSubset(of: allowedCapabilities) else { return false }
        return true
    }

    public func sanitize(
        _ result: LauncherResult,
        from descriptor: ModuleDescriptor
    ) -> LauncherResult? {
        guard permits(descriptor),
              !result.id.isEmpty,
              result.id.count <= 500,
              !result.title.isEmpty,
              result.title.count <= 1_000,
              result.subtitle.count <= 4_000,
              permits(result.icon, descriptor: descriptor),
              permits(result.action, descriptor: descriptor) else { return nil }
        return result.hosted(by: descriptor.id, scoreRange: scoreRange)
    }

    private func permits(_ icon: ResultIcon, descriptor: ModuleDescriptor) -> Bool {
        switch icon {
        case let .system(name):
            return !name.isEmpty && name.count <= 200
        case let .application(url), let .file(url):
            return descriptor.capabilities.contains(.localFileRead) && url.isFileURL
        case let .color(hex):
            return hex.count == 7 && hex.hasPrefix("#") && hex.dropFirst().allSatisfy(\.isHexDigit)
        case let .glyph(text):
            return !text.isEmpty && text.count <= 4 && text.unicodeScalars.count <= 16
        }
    }

    private func permits(_ action: ResultAction, descriptor: ModuleDescriptor) -> Bool {
        switch action {
        case let .copy(text), let .paste(text):
            return text.count <= 1_000_000
        case .none, .openSettings:
            return true
        case let .open(url), let .reveal(url):
            return descriptor.capabilities.contains(.localFileRead) && url.isFileURL
        case let .navigate(path):
            return descriptor.capabilities.contains(.localFileRead)
                && path.count <= 4_096
                && (path.hasPrefix("/") || path.hasPrefix("~"))
        case let .editQuery(text):
            return text.count <= 1_000 && !text.contains(where: \.isNewline)
        case let .showQRCode(text):
            return !text.isEmpty && text.utf8.count <= 1_200
        case let .hideApplication(bundleID), let .quitApplication(bundleID):
            return allowsPrivilegedActions && !bundleID.isEmpty && bundleID.count <= 255
        case .showTrash, .emptyTrash, .startScreenSaver, .sleepDisplays,
             .openFocusSettings, .openAppearanceSettings,
             .lockScreen, .ejectDisks, .toggleMute,
             .sleepComputer, .restartComputer, .shutDownComputer:
            return allowsPrivilegedActions
        case let .setVolume(percent):
            return allowsPrivilegedActions && (0...100).contains(percent)
        }
    }
}
