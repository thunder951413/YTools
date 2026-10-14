import Foundation

/// Random secrets for the `pwd` / `uuid` launcher keywords. Uses the system
/// CSPRNG through `SystemRandomNumberGenerator`; generator injection keeps
/// tests deterministic. Mirrored by `Core/Generators.cs`.
public enum PasswordGenerator {
    public static let lowercase = Array("abcdefghijkmnopqrstuvwxyz")
    public static let uppercase = Array("ABCDEFGHJKLMNPQRSTUVWXYZ")
    public static let digits = Array("23456789")
    public static let symbols = Array("!@#$%^&*-_=+?")

    public static let lengthRange = 8...64

    /// Every password contains at least one character from each enabled class
    /// and avoids look-alike characters (0/O, 1/l/I).
    public static func generate<G: RandomNumberGenerator>(length: Int, includeSymbols: Bool, using generator: inout G) -> String {
        let length = min(max(length, lengthRange.lowerBound), lengthRange.upperBound)
        var classes = [lowercase, uppercase, digits]
        if includeSymbols { classes.append(symbols) }
        let all = classes.flatMap { $0 }
        var characters = classes.map { $0.randomElement(using: &generator)! }
        while characters.count < length {
            characters.append(all.randomElement(using: &generator)!)
        }
        characters.shuffle(using: &generator)
        return String(characters)
    }

    public static func generate(length: Int, includeSymbols: Bool) -> String {
        var generator = SystemRandomNumberGenerator()
        return generate(length: length, includeSymbols: includeSymbols, using: &generator)
    }

    /// Accepts `pwd`, `pwd 24`, `password 32`, `密码 16`.
    public static func parse(_ rawQuery: String, defaultLength: Int) -> Int? {
        let parts = rawQuery.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ")
        guard let keyword = parts.first, ["pwd", "password", "密码", "生成密码"].contains(String(keyword)) else { return nil }
        if parts.count == 1 { return defaultLength }
        guard parts.count == 2, let length = Int(parts[1]), lengthRange.contains(length) else { return nil }
        return length
    }
}

public enum UUIDGenerator {
    public static func matches(_ rawQuery: String) -> Bool {
        ["uuid", "guid"].contains(rawQuery.trimmingCharacters(in: .whitespaces).lowercased())
    }

    public static func generate(uppercase: Bool) -> String {
        let value = UUID().uuidString
        return uppercase ? value : value.lowercased()
    }
}

/// `qr <text>` / `二维码 <text>`.
public enum QRCodeQuery {
    public static let maximumLength = 1_200

    public static func text(from rawQuery: String) -> String? {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        for prefix in ["qr ", "二维码 "] where trimmed.lowercased().hasPrefix(prefix) {
            let text = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text.utf8.count <= maximumLength else { return nil }
            return text
        }
        return nil
    }
}

/// Colour literals: `#RGB`, `#RRGGBB`, `rgb(r, g, b)`, `hsl(h, s%, l%)`.
public struct ColorValue: Equatable, Sendable {
    public let red: Int
    public let green: Int
    public let blue: Int

    public init(red: Int, green: Int, blue: Int) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
    }

    public var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    public var rgb: String { "rgb(\(red), \(green), \(blue))" }

    public var hsl: String {
        let r = Double(red) / 255, g = Double(green) / 255, b = Double(blue) / 255
        let maximum = max(r, g, b), minimum = min(r, g, b)
        let lightness = (maximum + minimum) / 2
        var hue = 0.0, saturation = 0.0
        let delta = maximum - minimum
        if delta > 0 {
            saturation = delta / (1 - abs(2 * lightness - 1))
            switch maximum {
            case r: hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            case g: hue = 60 * ((b - r) / delta + 2)
            default: hue = 60 * ((r - g) / delta + 4)
            }
            if hue < 0 { hue += 360 }
        }
        return "hsl(\(Int(hue.rounded())), \(Int((saturation * 100).rounded()))%, \(Int((lightness * 100).rounded()))%)"
    }

    public static func parse(_ rawQuery: String) -> ColorValue? {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if query.hasPrefix("#") {
            let digits = Array(query.dropFirst())
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            let expanded: [Character]
            switch digits.count {
            case 3: expanded = digits.flatMap { [$0, $0] }
            case 6: expanded = digits
            default: return nil
            }
            guard let value = Int(String(expanded), radix: 16) else { return nil }
            return ColorValue(red: value >> 16 & 0xFF, green: value >> 8 & 0xFF, blue: value & 0xFF)
        }
        if let arguments = functionArguments(query, name: "rgb"), arguments.count == 3 {
            let values = arguments.compactMap { Int($0) }
            guard values.count == 3, values.allSatisfy({ (0...255).contains($0) }) else { return nil }
            return ColorValue(red: values[0], green: values[1], blue: values[2])
        }
        if let arguments = functionArguments(query, name: "hsl"), arguments.count == 3,
           let hue = Double(arguments[0]),
           let saturation = Double(arguments[1].replacingOccurrences(of: "%", with: "")),
           let lightness = Double(arguments[2].replacingOccurrences(of: "%", with: "")),
           (0...360).contains(hue), (0...100).contains(saturation), (0...100).contains(lightness) {
            return fromHSL(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
        }
        return nil
    }

    private static func functionArguments(_ query: String, name: String) -> [String]? {
        guard query.hasPrefix(name + "("), query.hasSuffix(")") else { return nil }
        return query.dropFirst(name.count + 1).dropLast()
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func fromHSL(hue: Double, saturation: Double, lightness: Double) -> ColorValue {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let segment = hue / 60
        let x = chroma * (1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double)
        switch segment {
        case ..<1: (r, g, b) = (chroma, x, 0)
        case ..<2: (r, g, b) = (x, chroma, 0)
        case ..<3: (r, g, b) = (0, chroma, x)
        case ..<4: (r, g, b) = (0, x, chroma)
        case ..<5: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        let m = lightness - chroma / 2
        return ColorValue(red: Int(((r + m) * 255).rounded()), green: Int(((g + m) * 255).rounded()), blue: Int(((b + m) * 255).rounded()))
    }
}
