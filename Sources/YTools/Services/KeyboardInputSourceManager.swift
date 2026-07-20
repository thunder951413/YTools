import Carbon
import Foundation

struct KeyboardInputSourceOption: Identifiable, Hashable {
    let id: String
    let name: String
}

@MainActor
enum KeyboardInputSourceManager {
    private static var cachedOptions: [KeyboardInputSourceOption]?

    static func availableInputSources() -> [KeyboardInputSourceOption] {
        if let cachedOptions { return cachedOptions }
        let properties = [
            kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource!,
            kTISPropertyInputSourceIsSelectCapable: kCFBooleanTrue as Any
        ] as CFDictionary
        let sources = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray
        var seen: Set<String> = []
        let options = sources.compactMap { value -> KeyboardInputSourceOption? in
            let source = value as! TISInputSource
            guard let id = stringProperty(source, key: kTISPropertyInputSourceID),
                  let name = stringProperty(source, key: kTISPropertyLocalizedName),
                  seen.insert(id).inserted else { return nil }
            return KeyboardInputSourceOption(id: id, name: name)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cachedOptions = options
        return options
    }

    @discardableResult
    static func select(_ inputSourceID: String) -> Bool {
        guard !inputSourceID.isEmpty else { return true }
        let properties = [kTISPropertyInputSourceID: inputSourceID] as CFDictionary
        let sources = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray
        guard let source = sources.firstObject as! TISInputSource? else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private static func stringProperty(_ source: TISInputSource, key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return unsafeBitCast(pointer, to: CFString.self) as String
    }
}
