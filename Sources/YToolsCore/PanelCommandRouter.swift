public enum PanelInputMode: Sendable {
    case launcher
    case clipboard
}

public struct PanelKeyModifiers: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let command = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let control = Self(rawValue: 1 << 2)
    public static let shift = Self(rawValue: 1 << 3)
}

public struct PanelKeyEvent: Sendable {
    public let keyCode: UInt16
    public let modifiers: PanelKeyModifiers

    public init(keyCode: UInt16, modifiers: PanelKeyModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum PanelCommand: Equatable, Sendable {
    case activateSelected
    case activateResult(Int)
    case addSelectedToBuffer(moveToNext: Bool)
    case removeLastBufferedItem
    case showFileBufferActions
    case clearFileBuffer
    case escape
    case moveSelection(Int)
    case showActions
    case navigateBack
    case deleteClipboardItem
    case saveClipboardAsSnippet
    case togglePreview
    case showLargeType
    case revealSelected
    case openSettings
}

public struct PanelCommandRouter: Sendable {
    private enum KeyCode {
        static let returnKey: UInt16 = 36
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126
        static let delete: UInt16 = 51
        static let escape: UInt16 = 53
        static let d: UInt16 = 2
        static let s: UInt16 = 1
        static let y: UInt16 = 16
        static let l: UInt16 = 37
        static let comma: UInt16 = 43
        static let numberRow: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
    }

    public init() {}

    public func command(for event: PanelKeyEvent, mode: PanelInputMode) -> PanelCommand? {
        if event.modifiers.contains(.command), mode == .launcher,
           let index = resultIndex(forNumberKeyCode: event.keyCode) {
            return .activateResult(index)
        }

        switch (event.keyCode, mode) {
        case (KeyCode.returnKey, _) where event.modifiers.isEmpty:
            return .activateSelected
        case (KeyCode.upArrow, .launcher) where event.modifiers.contains(.option):
            return .addSelectedToBuffer(moveToNext: false)
        case (KeyCode.downArrow, .launcher) where event.modifiers.contains(.option):
            return .addSelectedToBuffer(moveToNext: true)
        case (KeyCode.leftArrow, .launcher) where event.modifiers.contains(.option):
            return .removeLastBufferedItem
        case (KeyCode.rightArrow, .launcher) where event.modifiers.contains(.option):
            return .showFileBufferActions
        case (KeyCode.delete, .launcher) where event.modifiers.contains(.option):
            return .clearFileBuffer
        case (KeyCode.escape, _):
            return .escape
        case (KeyCode.downArrow, _):
            return .moveSelection(1)
        case (KeyCode.upArrow, _):
            return .moveSelection(-1)
        case (KeyCode.rightArrow, .launcher):
            return .showActions
        case (KeyCode.leftArrow, .launcher):
            return .navigateBack
        case (KeyCode.d, .clipboard) where event.modifiers.contains(.command):
            return .deleteClipboardItem
        case (KeyCode.s, .clipboard) where event.modifiers.contains(.command):
            return .saveClipboardAsSnippet
        case (KeyCode.y, .launcher) where event.modifiers.contains(.command):
            return .togglePreview
        case (KeyCode.l, .launcher) where event.modifiers.contains(.command):
            return .showLargeType
        case (KeyCode.returnKey, .launcher) where event.modifiers.contains(.command):
            return .revealSelected
        case (KeyCode.comma, _) where event.modifiers.contains(.command):
            return .openSettings
        default:
            return nil
        }
    }

    private func resultIndex(forNumberKeyCode keyCode: UInt16) -> Int? {
        KeyCode.numberRow.firstIndex(of: keyCode)
    }
}
