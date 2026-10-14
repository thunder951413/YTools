import Foundation

/// Heuristics for clipboard text that should not linger in history: one-time
/// codes, API keys and long random tokens. Used for the optional automatic
/// cleanup; it never blocks capture on its own. Mirrored by
/// `Core/SensitiveTextDetector.cs`.
public enum SensitiveTextDetector {
    private static let knownPrefixes = [
        "sk-", "sk_live_", "sk_test_", "rk_live_", "pk_live_", "ghp_", "gho_", "ghu_", "ghs_", "github_pat_",
        "glpat-", "xoxb-", "xoxp-", "AKIA", "ASIA", "AIza", "ya29.", "eyJ"
    ]

    public static func looksSensitive(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 4_096, !value.contains(where: \.isWhitespace) else { return false }
        if isOneTimeCode(value) { return true }
        if knownPrefixes.contains(where: { value.hasPrefix($0) }), value.count >= 16 { return true }
        return isRandomToken(value)
    }

    /// 4–8 digit codes, optionally split in the middle (123-456 / 123 456 is excluded by the whitespace check).
    static func isOneTimeCode(_ value: String) -> Bool {
        let digits = value.replacingOccurrences(of: "-", with: "")
        guard (4...8).contains(digits.count), digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return false }
        // Years and other short numbers are common in normal text; require 6+ digits unless split.
        return digits.count >= 6 || value.contains("-")
    }

    /// At least 24 characters mixing lowercase, uppercase and digits with high variety.
    static func isRandomToken(_ value: String) -> Bool {
        guard value.count >= 24, value.allSatisfy({ $0.isASCII && !$0.isWhitespace }) else { return false }
        if value.hasPrefix("http://") || value.hasPrefix("https://") || value.contains("/") && value.contains(".") { return false }
        let hasLower = value.contains(where: \.isLowercase)
        let hasUpper = value.contains(where: \.isUppercase)
        let hasDigit = value.contains(where: \.isNumber)
        let classes = [hasLower, hasUpper, hasDigit].filter { $0 }.count
        // Hex hashes and UUIDs (lowercase + digits) are routinely copied on purpose.
        guard classes >= 3 else { return false }
        let distinct = Set(value).count
        return Double(distinct) / Double(value.count) > 0.35
    }
}
