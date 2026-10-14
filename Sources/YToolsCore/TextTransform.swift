import CryptoKit
import Foundation

/// Offline text conversions offered by the `tx` launcher keyword. Every
/// transform is pure and returns nil when it does not apply (e.g. invalid JSON
/// or Base64) so the launcher only lists meaningful results. The Windows port
/// in `Core/TextTransform.cs` must produce identical output.
public enum TextTransform: String, CaseIterable, Sendable {
    case uppercase
    case lowercase
    case titleCase
    case camelCase
    case snakeCase
    case kebabCase
    case trimWhitespace
    case removeBlankLines
    case sortLines
    case uniqueLines
    case reverseLines
    case jsonPretty
    case jsonMinify
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case htmlEscape
    case htmlUnescape
    case md5
    case sha1
    case sha256

    public static let maximumInputLength = 200_000

    public var title: String {
        switch self {
        case .uppercase: "全部大写"
        case .lowercase: "全部小写"
        case .titleCase: "首字母大写"
        case .camelCase: "驼峰命名"
        case .snakeCase: "蛇形命名"
        case .kebabCase: "短横线命名"
        case .trimWhitespace: "去除首尾空白"
        case .removeBlankLines: "删除空行"
        case .sortLines: "按行排序"
        case .uniqueLines: "按行去重"
        case .reverseLines: "行顺序反转"
        case .jsonPretty: "JSON 格式化"
        case .jsonMinify: "JSON 压缩"
        case .base64Encode: "Base64 编码"
        case .base64Decode: "Base64 解码"
        case .urlEncode: "URL 编码"
        case .urlDecode: "URL 解码"
        case .htmlEscape: "HTML 转义"
        case .htmlUnescape: "HTML 反转义"
        case .md5: "MD5"
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        }
    }

    /// Words accepted after `tx` to pick one transform (`tx json`, `tx 大写`).
    public var keywords: [String] {
        switch self {
        case .uppercase: ["upper", "大写"]
        case .lowercase: ["lower", "小写"]
        case .titleCase: ["title", "首字母"]
        case .camelCase: ["camel", "驼峰"]
        case .snakeCase: ["snake", "蛇形"]
        case .kebabCase: ["kebab", "短横线"]
        case .trimWhitespace: ["trim", "去空白"]
        case .removeBlankLines: ["noblank", "删空行"]
        case .sortLines: ["sort", "排序"]
        case .uniqueLines: ["uniq", "unique", "去重"]
        case .reverseLines: ["reverse", "反转"]
        case .jsonPretty: ["json", "格式化"]
        case .jsonMinify: ["minify", "压缩"]
        case .base64Encode: ["b64", "base64"]
        case .base64Decode: ["unb64", "b64d"]
        case .urlEncode: ["url", "urlencode"]
        case .urlDecode: ["unurl", "urldecode"]
        case .htmlEscape: ["html", "escape"]
        case .htmlUnescape: ["unhtml", "unescape"]
        case .md5: ["md5"]
        case .sha1: ["sha1"]
        case .sha256: ["sha256", "sha", "hash", "哈希"]
        }
    }

    public static func matching(keyword: String) -> TextTransform? {
        let lowered = keyword.lowercased()
        return allCases.first { $0.keywords.contains(lowered) }
    }

    public func apply(_ input: String) -> String? {
        guard !input.isEmpty, input.utf8.count <= Self.maximumInputLength else { return nil }
        let output: String?
        switch self {
        case .uppercase: output = input.uppercased()
        case .lowercase: output = input.lowercased()
        case .titleCase: output = Self.titleCased(input)
        case .camelCase: output = Self.joinWords(input, style: .camel)
        case .snakeCase: output = Self.joinWords(input, style: .snake)
        case .kebabCase: output = Self.joinWords(input, style: .kebab)
        case .trimWhitespace:
            output = Self.lines(input).map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        case .removeBlankLines:
            output = Self.lines(input).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
        case .sortLines:
            output = Self.lines(input).sorted { $0.compare($1, options: [.numeric]) == .orderedAscending }.joined(separator: "\n")
        case .uniqueLines:
            var seen = Set<String>()
            output = Self.lines(input).filter { seen.insert($0).inserted }.joined(separator: "\n")
        case .reverseLines: output = Self.lines(input).reversed().joined(separator: "\n")
        case .jsonPretty: output = Self.json(input, pretty: true)
        case .jsonMinify: output = Self.json(input, pretty: false)
        case .base64Encode: output = Data(input.utf8).base64EncodedString()
        case .base64Decode: output = Self.base64Decoded(input)
        case .urlEncode: output = input.addingPercentEncoding(withAllowedCharacters: Self.urlUnreserved)
        case .urlDecode:
            let decoded = input.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
            output = decoded == input ? nil : decoded
        case .htmlEscape: output = Self.htmlEscaped(input)
        case .htmlUnescape: output = Self.htmlUnescaped(input)
        case .md5: output = Self.hex(Insecure.MD5.hash(data: Data(input.utf8)))
        case .sha1: output = Self.hex(Insecure.SHA1.hash(data: Data(input.utf8)))
        case .sha256: output = Self.hex(SHA256.hash(data: Data(input.utf8)))
        }
        guard let output, !output.isEmpty, output != input else { return nil }
        return output
    }

    // MARK: - Helpers

    /// RFC 3986 unreserved characters; everything else is percent-encoded.
    private static let urlUnreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func lines(_ input: String) -> [String] {
        input.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    private static func titleCased(_ input: String) -> String {
        var result = ""
        var atWordStart = true
        for character in input {
            if character.isLetter || character.isNumber {
                result += atWordStart ? character.uppercased() : character.lowercased()
                atWordStart = false
            } else {
                result.append(character)
                atWordStart = true
            }
        }
        return result
    }

    private enum WordStyle { case camel, snake, kebab }

    /// Splits on non-alphanumerics and on lower→upper boundaries
    /// (`fooBar`, `foo_bar`, `Foo Bar` all become `foo`, `bar`).
    static func words(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousWasLower = false
        for character in input {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty { words.append(current); current = "" }
                previousWasLower = false
                continue
            }
            if character.isUppercase, previousWasLower, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
            previousWasLower = character.isLowercase || character.isNumber
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.lowercased() }
    }

    private static func joinWords(_ input: String, style: WordStyle) -> String? {
        let parts = words(input)
        guard !parts.isEmpty else { return nil }
        switch style {
        case .camel:
            return parts.enumerated().map { index, word in
                index == 0 ? word : word.prefix(1).uppercased() + word.dropFirst()
            }.joined()
        case .snake: return parts.joined(separator: "_")
        case .kebab: return parts.joined(separator: "-")
        }
    }

    private static func json(_ input: String, pretty: Bool) -> String? {
        guard let data = input.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              object is [Any] || object is [String: Any] else { return nil }
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if pretty { options.formUnion([.prettyPrinted, .sortedKeys]) }
        guard let output = try? JSONSerialization.data(withJSONObject: object, options: options) else { return nil }
        return String(data: output, encoding: .utf8)
    }

    private static func base64Decoded(_ input: String) -> String? {
        var normalized = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard normalized.count % 4 != 1 else { return nil }
        while normalized.count % 4 != 0 { normalized += "=" }
        guard let data = Data(base64Encoded: normalized),
              let text = String(data: data, encoding: .utf8) else { return nil }
        let allowedControls: Set<Unicode.Scalar> = ["\n", "\r", "\t"]
        for scalar in text.unicodeScalars
        where scalar.properties.generalCategory == .control && !allowedControls.contains(scalar) {
            return nil
        }
        return text
    }

    private static let htmlEntities: [(String, String)] = [
        ("&", "&amp;"), ("<", "&lt;"), (">", "&gt;"), ("\"", "&quot;"), ("'", "&#39;")
    ]

    private static func htmlEscaped(_ input: String) -> String {
        htmlEntities.reduce(input) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }

    private static func htmlUnescaped(_ input: String) -> String {
        var output = input.replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
        for (character, entity) in htmlEntities.reversed() {
            output = output.replacingOccurrences(of: entity, with: character)
        }
        return output
    }

    private static func hex<D: Digest>(_ digest: D) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Parses `tx …` launcher queries.
public struct TextTransformQuery: Equatable, Sendable {
    public let transform: TextTransform?
    /// Explicit text after the keyword; nil means "use the clipboard".
    public let text: String?

    public static let prefixes = ["tx", "转换"]

    public init(transform: TextTransform?, text: String?) {
        self.transform = transform
        self.text = text
    }

    public static func parse(_ query: String) -> TextTransformQuery? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let prefix = prefixes.first(where: {
            trimmed.lowercased() == $0 || trimmed.lowercased().hasPrefix($0 + " ")
        }) else { return nil }
        let rest = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return TextTransformQuery(transform: nil, text: nil) }
        let firstWord = rest.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if let transform = TextTransform.matching(keyword: firstWord) {
            let remainder = rest.dropFirst(firstWord.count).trimmingCharacters(in: .whitespaces)
            return TextTransformQuery(transform: transform, text: remainder.isEmpty ? nil : remainder)
        }
        return TextTransformQuery(transform: nil, text: rest)
    }
}
