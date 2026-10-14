import Foundation
import YToolsCore

/// Options for the built-in offline tools (text, time, generators, emoji).
/// Stored as one JSON value; unknown or missing keys fall back to defaults so
/// older and newer builds can share the same preferences domain.
struct ToolSettings: Codable, Equatable, Sendable {
    var passwordLength = 20
    var passwordIncludesSymbols = true
    var uuidUppercase = false
    var timestampUnit: TimestampUnit = .automatic
    var worldClockZones: [String] = DateTimeTools.defaultWorldClockZones
    var emojiSkinTone = 0
    /// Selecting an emoji pastes it into the previous app (Accessibility) instead of only copying.
    var emojiPastesDirectly = true
    /// 0x/0b/0o input also lists decimal, hexadecimal and binary values.
    var numberBaseConversion = true
    /// Calculator understands "300 的 20%" and "200+15%".
    var percentExpressions = true

    init() {}

    init(from decoder: any Decoder) throws {
        let defaults = ToolSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        passwordLength = min(max(try container.decodeIfPresent(Int.self, forKey: .passwordLength) ?? defaults.passwordLength,
                                 PasswordGenerator.lengthRange.lowerBound), PasswordGenerator.lengthRange.upperBound)
        passwordIncludesSymbols = try container.decodeIfPresent(Bool.self, forKey: .passwordIncludesSymbols) ?? defaults.passwordIncludesSymbols
        uuidUppercase = try container.decodeIfPresent(Bool.self, forKey: .uuidUppercase) ?? defaults.uuidUppercase
        timestampUnit = (try? container.decodeIfPresent(TimestampUnit.self, forKey: .timestampUnit)) ?? defaults.timestampUnit
        worldClockZones = (try container.decodeIfPresent([String].self, forKey: .worldClockZones) ?? defaults.worldClockZones)
            .filter { TimeZone(identifier: $0) != nil }
        emojiSkinTone = min(max(try container.decodeIfPresent(Int.self, forKey: .emojiSkinTone) ?? 0, 0), 5)
        emojiPastesDirectly = try container.decodeIfPresent(Bool.self, forKey: .emojiPastesDirectly) ?? defaults.emojiPastesDirectly
        numberBaseConversion = try container.decodeIfPresent(Bool.self, forKey: .numberBaseConversion) ?? defaults.numberBaseConversion
        percentExpressions = try container.decodeIfPresent(Bool.self, forKey: .percentExpressions) ?? defaults.percentExpressions
    }
}

/// Confirmation and presentation behaviour for applications and power commands.
struct BehaviorSettings: Codable, Equatable, Sendable {
    var markRunningApplications = true
    var confirmQuitApplication = true
    var confirmPowerActions = true

    init() {}

    init(from decoder: any Decoder) throws {
        let defaults = BehaviorSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        markRunningApplications = try container.decodeIfPresent(Bool.self, forKey: .markRunningApplications) ?? defaults.markRunningApplications
        confirmQuitApplication = try container.decodeIfPresent(Bool.self, forKey: .confirmQuitApplication) ?? defaults.confirmQuitApplication
        confirmPowerActions = try container.decodeIfPresent(Bool.self, forKey: .confirmPowerActions) ?? defaults.confirmPowerActions
    }
}

/// A user rule that keeps matching text out of clipboard history.
struct ClipboardIgnoreRule: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var pattern: String
    var label: String

    /// Invalid patterns never match (and are flagged in settings).
    func matches(_ text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }

    var isValid: Bool { (try? NSRegularExpression(pattern: pattern)) != nil }
}

struct ClipboardBehaviorSettings: Codable, Equatable, Sendable {
    /// Re-activate the previous app and send ⌘V after choosing an item.
    var pasteToFrontApplication = false
    /// Holding ⇧ while choosing pastes/copies plain text only.
    var shiftPastesPlainText = true
    var sequentialPaste = true
    var ignoreRules: [ClipboardIgnoreRule] = []
    /// Minutes after which text that looks like a one-time code or token is
    /// removed from history; 0 disables the cleanup.
    var sensitiveAutoDeleteMinutes = 60

    init() {}

    init(from decoder: any Decoder) throws {
        let defaults = ClipboardBehaviorSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pasteToFrontApplication = try container.decodeIfPresent(Bool.self, forKey: .pasteToFrontApplication) ?? defaults.pasteToFrontApplication
        shiftPastesPlainText = try container.decodeIfPresent(Bool.self, forKey: .shiftPastesPlainText) ?? defaults.shiftPastesPlainText
        sequentialPaste = try container.decodeIfPresent(Bool.self, forKey: .sequentialPaste) ?? defaults.sequentialPaste
        ignoreRules = (try? container.decodeIfPresent([ClipboardIgnoreRule].self, forKey: .ignoreRules)) ?? defaults.ignoreRules
        sensitiveAutoDeleteMinutes = min(max(try container.decodeIfPresent(Int.self, forKey: .sensitiveAutoDeleteMinutes)
            ?? defaults.sensitiveAutoDeleteMinutes, 0), 10_080)
    }
}

enum TerminalApplication: String, Codable, CaseIterable, Identifiable, Sendable {
    case terminal
    case iTerm
    case warp
    case ghostty

    var id: String { rawValue }
    var title: String {
        switch self {
        case .terminal: "终端"
        case .iTerm: "iTerm2"
        case .warp: "Warp"
        case .ghostty: "Ghostty"
        }
    }
    var bundleIdentifier: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iTerm: "com.googlecode.iterm2"
        case .warp: "dev.warp.Warp-Stable"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }
}

struct FileActionSettings: Codable, Equatable, Sendable {
    var terminal: TerminalApplication = .terminal
    var favoriteFolders: [String] = []
    var revealArchiveAfterCompression = true
    var newFileExtension = "txt"
    var previewDocuments = true

    init() {}

    init(from decoder: any Decoder) throws {
        let defaults = FileActionSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        terminal = (try? container.decodeIfPresent(TerminalApplication.self, forKey: .terminal)) ?? defaults.terminal
        favoriteFolders = try container.decodeIfPresent([String].self, forKey: .favoriteFolders) ?? defaults.favoriteFolders
        revealArchiveAfterCompression = try container.decodeIfPresent(Bool.self, forKey: .revealArchiveAfterCompression) ?? defaults.revealArchiveAfterCompression
        let storedExtension = try container.decodeIfPresent(String.self, forKey: .newFileExtension) ?? defaults.newFileExtension
        newFileExtension = Self.sanitizedExtension(storedExtension)
        previewDocuments = try container.decodeIfPresent(Bool.self, forKey: .previewDocuments) ?? defaults.previewDocuments
    }

    static func sanitizedExtension(_ value: String) -> String {
        let cleaned = value.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !cleaned.isEmpty, cleaned.count <= 12, cleaned.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return "txt" }
        return cleaned.lowercased()
    }
}

/// Optional global shortcuts for the newer tools.
struct ToolHotKeySettings: Codable, Equatable, Sendable {
    var recognizeText: HotKeyDefinition? = HotKeyDefinition(keyCode: 31, modifiers: 0x1000 | 0x0800) // ⌃⌥O
    var sequentialPaste: HotKeyDefinition?

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recognizeText = try container.decodeIfPresent(HotKeyDefinition.self, forKey: .recognizeText)
        sequentialPaste = try container.decodeIfPresent(HotKeyDefinition.self, forKey: .sequentialPaste)
    }
}

/// A user-defined global shortcut that opens an app or folder, or pastes a snippet.
struct CustomHotKey: Codable, Equatable, Identifiable, Sendable {
    enum Target: Codable, Equatable, Sendable {
        case application(path: String)
        case folder(path: String)
        case snippet(id: UUID)
    }

    var id = UUID()
    var hotKey: HotKeyDefinition
    var target: Target
    var title: String

    var actionTitle: String {
        switch target {
        case .application: "打开应用"
        case .folder: "打开文件夹"
        case .snippet: "粘贴文本片段"
        }
    }
}
