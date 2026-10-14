import Foundation

public enum ResultIcon: Equatable, Sendable {
    case system(String)
    case application(URL)
    case file(URL)
    /// A colour swatch, `#RRGGBB`.
    case color(String)
    /// A short glyph such as an emoji or symbol drawn as the icon.
    case glyph(String)
}

/// The complete action vocabulary available to a compiled module. Deliberately
/// excludes arbitrary shell commands, scripts, dynamic code and URL opening.
public enum ResultAction: Equatable, Sendable {
    case copy(String)
    case open(URL)
    case reveal(URL)
    case navigate(String)
    /// Replaces the launcher query with plain text (no file access implied).
    case editQuery(String)
    /// Shows the text as a QR code generated on this device.
    case showQRCode(String)
    case hideApplication(String)
    case quitApplication(String)
    case showTrash
    case emptyTrash
    case startScreenSaver
    case sleepDisplays
    case openFocusSettings
    case openAppearanceSettings
    case openSettings
    case lockScreen
    case ejectDisks
    case toggleMute
    /// Sets the output volume, 0–100.
    case setVolume(Int)
    case sleepComputer
    case restartComputer
    case shutDownComputer
    /// Copies the text and, when enabled and permitted, pastes it into the
    /// previously active application.
    case paste(String)
    case none
}

public struct LauncherResult: Identifiable, Equatable, Sendable {
    public let id: String
    public let moduleID: String
    public let title: String
    public let subtitle: String
    public let icon: ResultIcon
    public let score: Int
    public let action: ResultAction

    public init(
        id: String,
        moduleID: String,
        title: String,
        subtitle: String,
        icon: ResultIcon,
        score: Int,
        action: ResultAction
    ) {
        self.id = id
        self.moduleID = moduleID
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.score = score
        self.action = action
    }

    public var fileURL: URL? {
        if case let .file(url) = icon { return url }
        return nil
    }

    public var resourceURL: URL? {
        switch icon {
        case let .application(url), let .file(url): url
        case .system, .color, .glyph: nil
        }
    }

    public var isApplication: Bool {
        if case .application = icon { return true }
        return false
    }

    public func withScore(_ newScore: Int) -> LauncherResult {
        LauncherResult(
            id: id,
            moduleID: moduleID,
            title: title,
            subtitle: subtitle,
            icon: icon,
            score: newScore,
            action: action
        )
    }

    public func hosted(by moduleID: String, scoreRange: ClosedRange<Int>) -> LauncherResult {
        LauncherResult(
            id: id,
            moduleID: moduleID,
            title: title,
            subtitle: subtitle,
            icon: icon,
            score: min(max(score, scoreRange.lowerBound), scoreRange.upperBound),
            action: action
        )
    }
}
