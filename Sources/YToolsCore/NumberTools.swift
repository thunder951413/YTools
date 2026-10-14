import Foundation

/// Integer base conversion for `0x`, `0b`, `0o` literals and `255 to hex`.
/// Mirrored by `Core/NumberTools.cs`.
public enum NumberBaseConverter {
    public struct Line: Equatable, Sendable {
        public let title: String
        public let label: String
    }

    public static func results(for rawQuery: String) -> [Line] {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty, query.count <= 80 else { return [] }
        var source = query
        var target: Int?
        for (keyword, base) in [("hex", 16), ("bin", 2), ("oct", 8), ("dec", 10), ("十六进制", 16), ("二进制", 2), ("八进制", 8), ("十进制", 10)] {
            for joiner in [" to ", " in ", " 转 ", "转"] where source.hasSuffix(joiner + keyword) {
                source = String(source.dropLast((joiner + keyword).count)).trimmingCharacters(in: .whitespaces)
                target = base
            }
        }
        guard let value = parse(source) else { return [] }
        // A bare decimal number is only converted when a target base was asked for.
        if target == nil, value.base == 10 { return [] }
        let bases = target.map { [$0] } ?? [10, 16, 2, 8].filter { $0 != value.base }
        return bases.map { base in
            Line(title: format(value.number, base: base), label: label(for: base))
        }
    }

    static func parse(_ text: String) -> (number: Int64, base: Int)? {
        var body = text.replacingOccurrences(of: "_", with: "")
        var negative = false
        if body.hasPrefix("-") { negative = true; body.removeFirst() }
        let base: Int
        if body.hasPrefix("0x") { base = 16; body.removeFirst(2) }
        else if body.hasPrefix("0b") { base = 2; body.removeFirst(2) }
        else if body.hasPrefix("0o") { base = 8; body.removeFirst(2) }
        else { base = 10 }
        guard !body.isEmpty, body.count <= 64, let magnitude = UInt64(body, radix: base) else { return nil }
        if negative {
            guard magnitude <= UInt64(Int64.max) + 1 else { return nil }
            return (magnitude == UInt64(Int64.max) + 1 ? Int64.min : -Int64(magnitude), base)
        }
        guard magnitude <= UInt64(Int64.max) else { return nil }
        return (Int64(magnitude), base)
    }

    static func format(_ value: Int64, base: Int) -> String {
        let prefix: String
        switch base {
        case 16: prefix = "0x"
        case 2: prefix = "0b"
        case 8: prefix = "0o"
        default: return String(value)
        }
        let sign = value < 0 ? "-" : ""
        var digits = String(value.magnitude, radix: base, uppercase: true)
        if base == 2 {
            // Group binary digits in nibbles for readability: 0b1010_1111.
            let padded = String(repeating: "0", count: (4 - digits.count % 4) % 4) + digits
            digits = stride(from: 0, to: padded.count, by: 4).map { start in
                let begin = padded.index(padded.startIndex, offsetBy: start)
                return String(padded[begin..<padded.index(begin, offsetBy: 4)])
            }.joined(separator: "_")
        }
        return sign + prefix + digits
    }

    private static func label(for base: Int) -> String {
        switch base {
        case 16: "十六进制"
        case 2: "二进制"
        case 8: "八进制"
        default: "十进制"
        }
    }
}

/// Percentage shorthands the expression calculator does not cover:
/// `200+15%`, `200-15%`, `20% of 300` and `300 的 20%`.
/// Mirrored by `Core/NumberTools.cs`.
public enum PercentCalculator {
    public struct Result: Equatable, Sendable {
        public let value: Double
        public let explanation: String
    }

    public static func evaluate(_ rawQuery: String, calculator: ExpressionCalculator = ExpressionCalculator()) -> Result? {
        let query = rawQuery.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: "％", with: "%")
        guard query.contains("%"), query.count <= 120 else { return nil }

        // 20% of 300 / 300 的 20%
        if let range = query.range(of: " of ") {
            return percentOf(String(query[..<range.lowerBound]), String(query[range.upperBound...]), calculator)
        }
        if let range = query.range(of: "的") {
            return percentOf(String(query[range.upperBound...]), String(query[..<range.lowerBound]), calculator)
        }
        // A + P% / A - P%
        guard query.hasSuffix("%") else { return nil }
        let body = query.dropLast()
        guard let operatorIndex = body.lastIndex(where: { $0 == "+" || $0 == "-" }),
              operatorIndex != body.startIndex else { return nil }
        let baseText = String(body[..<operatorIndex])
        let percentText = String(body[body.index(after: operatorIndex)...])
        guard let base = try? calculator.evaluate(baseText),
              let percent = Double(percentText.trimmingCharacters(in: .whitespaces)) else { return nil }
        let sign: Double = body[operatorIndex] == "+" ? 1 : -1
        let value = base * (1 + sign * percent / 100)
        guard value.isFinite else { return nil }
        return Result(value: value, explanation: "\(calculator.format(base)) \(sign > 0 ? "+" : "−") \(calculator.format(percent))%")
    }

    private static func percentOf(_ percentText: String, _ baseText: String, _ calculator: ExpressionCalculator) -> Result? {
        let trimmed = percentText.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("%"),
              let percent = Double(trimmed.dropLast().trimmingCharacters(in: .whitespaces)),
              let base = try? calculator.evaluate(baseText) else { return nil }
        let value = base * percent / 100
        guard value.isFinite else { return nil }
        return Result(value: value, explanation: "\(calculator.format(base)) 的 \(calculator.format(percent))%")
    }
}
