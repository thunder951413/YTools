import Foundation

public struct ClipboardTextPolicy: Equatable, Sendable {
    public let maximumCharacters: Int

    public init(maximumCharacters: Int) {
        self.maximumCharacters = max(1, maximumCharacters)
    }

    public func shouldStore(_ text: String) -> Bool {
        !text.isEmpty && text.count <= maximumCharacters
    }
}
