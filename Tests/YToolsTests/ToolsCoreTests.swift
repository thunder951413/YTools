import Foundation
import XCTest
import YToolsCore

final class TextTransformTests: XCTestCase {
    func testCaseAndNamingTransforms() {
        XCTAssertEqual(TextTransform.uppercase.apply("Hello"), "HELLO")
        XCTAssertEqual(TextTransform.titleCase.apply("hello wORLD-foo"), "Hello World-Foo")
        XCTAssertEqual(TextTransform.camelCase.apply("user_id value"), "userIdValue")
        XCTAssertEqual(TextTransform.snakeCase.apply("userIdValue"), "user_id_value")
        XCTAssertEqual(TextTransform.kebabCase.apply("User ID value"), "user-id-value")
        XCTAssertNil(TextTransform.uppercase.apply("ABC"), "Unchanged output is not offered")
    }

    func testLineTransforms() {
        XCTAssertEqual(TextTransform.sortLines.apply("b\na10\na2"), "a2\na10\nb")
        XCTAssertEqual(TextTransform.uniqueLines.apply("a\nb\na"), "a\nb")
        XCTAssertEqual(TextTransform.removeBlankLines.apply("a\n\n  \nb"), "a\nb")
        XCTAssertEqual(TextTransform.reverseLines.apply("1\r\n2"), "2\n1")
    }

    func testJSONAndEncodings() {
        XCTAssertEqual(TextTransform.jsonMinify.apply("{ \"b\": 1, \"a\": [1, 2] }")?.count, 17)
        XCTAssertEqual(TextTransform.jsonPretty.apply("{\"b\":1,\"a\":2}"), "{\n  \"a\" : 2,\n  \"b\" : 1\n}")
        XCTAssertNil(TextTransform.jsonPretty.apply("not json"))
        XCTAssertEqual(TextTransform.base64Encode.apply("你好"), "5L2g5aW9")
        XCTAssertEqual(TextTransform.base64Decode.apply("5L2g5aW9"), "你好")
        XCTAssertNil(TextTransform.base64Decode.apply("abc"))
        XCTAssertEqual(TextTransform.urlEncode.apply("a b/你"), "a%20b%2F%E4%BD%A0")
        XCTAssertEqual(TextTransform.urlDecode.apply("a%20b%2F%E4%BD%A0"), "a b/你")
        XCTAssertEqual(TextTransform.htmlEscape.apply("<a href=\"x\">&</a>"), "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;")
        XCTAssertEqual(TextTransform.htmlUnescape.apply("&lt;b&gt; &amp;amp;"), "<b> &amp;")
        XCTAssertEqual(TextTransform.md5.apply("hello"), "5d41402abc4b2a76b9719d911017c592")
        XCTAssertEqual(TextTransform.sha256.apply("hello")?.prefix(16), "2cf24dba5fb0a30e")
    }

    func testQueryParsing() {
        XCTAssertEqual(TextTransformQuery.parse("tx"), TextTransformQuery(transform: nil, text: nil))
        XCTAssertEqual(TextTransformQuery.parse("tx json"), TextTransformQuery(transform: .jsonPretty, text: nil))
        XCTAssertEqual(TextTransformQuery.parse("tx upper hello world"), TextTransformQuery(transform: .uppercase, text: "hello world"))
        XCTAssertEqual(TextTransformQuery.parse("转换 你好"), TextTransformQuery(transform: nil, text: "你好"))
        XCTAssertNil(TextTransformQuery.parse("txt"))
    }
}

final class DateTimeToolsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_791_954_000) // 2026-10-14 05:00 UTC
    private var tools: DateTimeTools {
        DateTimeTools(now: now, localTimeZone: TimeZone(identifier: "Asia/Seoul")!,
                      timestampUnit: .automatic, worldClockZones: ["Asia/Tokyo", "Europe/London"])
    }

    func testCurrentAndParsedTimestamps() {
        XCTAssertEqual(tools.results(for: "now").first?.copyText, "1791954000")
        XCTAssertEqual(tools.results(for: "now")[1].copyText, "1791954000000")
        XCTAssertEqual(tools.results(for: "1760000000").first?.copyText, "2025-10-09 17:53:20")
        XCTAssertEqual(tools.results(for: "1760000000000").first?.copyText, "2025-10-09 17:53:20")
        XCTAssertEqual(tools.results(for: "ts 1760000000")[1].copyText, "2025-10-09T08:53:20Z")
        XCTAssertTrue(tools.results(for: "12345").isEmpty, "Short numbers are not timestamps")
    }

    func testDateArithmetic() {
        XCTAssertEqual(tools.results(for: "today+45d").first?.copyText, "2026-11-28")
        XCTAssertEqual(tools.results(for: "今天 + 45 天").first?.title, "2026-11-28 周六")
        XCTAssertEqual(tools.results(for: "2026-12-25 - 2026-10-14").first?.copyText, "72")
        XCTAssertEqual(tools.results(for: "2026-12-25-today").first?.copyText, "72")
        XCTAssertEqual(tools.results(for: "2026-10-14").first?.subtitle.hasPrefix("今天 · 第 42 周"), true)
        XCTAssertTrue(tools.results(for: "2026-02-30").isEmpty)
        XCTAssertTrue(tools.results(for: "hello").isEmpty)
    }

    func testWorldClock() {
        let all = tools.results(for: "time")
        XCTAssertEqual(all.count, 3, "Local zone plus configured zones")
        XCTAssertTrue(all[0].subtitle.hasSuffix("本地"))
        XCTAssertEqual(tools.results(for: "time tokyo").first?.title, "14:00  东京")
        XCTAssertEqual(tools.results(for: "纽约时间").first?.title, "01:00  纽约")
        XCTAssertTrue(tools.results(for: "纽约时间").first?.subtitle.contains("-13 小时") ?? false)
    }
}

final class NumberToolsTests: XCTestCase {
    func testBaseConversion() {
        let hex = NumberBaseConverter.results(for: "0xFF")
        XCTAssertEqual(hex.map(\.title), ["255", "0b1111_1111", "0o377"])
        XCTAssertEqual(NumberBaseConverter.results(for: "255 to hex").map(\.title), ["0xFF"])
        XCTAssertEqual(NumberBaseConverter.results(for: "10 转二进制").map(\.title), ["0b1010"])
        XCTAssertTrue(NumberBaseConverter.results(for: "255").isEmpty, "Plain decimals stay with the calculator")
        XCTAssertTrue(NumberBaseConverter.results(for: "0xZZ").isEmpty)
        XCTAssertEqual(NumberBaseConverter.results(for: "-0x10").first?.title, "-16")
    }

    func testPercentShorthands() {
        XCTAssertEqual(PercentCalculator.evaluate("200+15%")?.value ?? 0, 230, accuracy: 1e-9)
        XCTAssertEqual(PercentCalculator.evaluate("200 - 15%")?.value ?? 0, 170, accuracy: 1e-9)
        XCTAssertEqual(PercentCalculator.evaluate("20% of 300")?.value ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(PercentCalculator.evaluate("300的20%")?.value ?? 0, 60, accuracy: 1e-9)
        XCTAssertNil(PercentCalculator.evaluate("10 % 3"))
    }
}

final class GeneratorTests: XCTestCase {
    func testPasswordsContainEveryClassAndRespectLength() {
        for length in [8, 20, 64] {
            let password = PasswordGenerator.generate(length: length, includeSymbols: true)
            XCTAssertEqual(password.count, length)
            XCTAssertTrue(password.contains(where: { PasswordGenerator.lowercase.contains($0) }))
            XCTAssertTrue(password.contains(where: { PasswordGenerator.uppercase.contains($0) }))
            XCTAssertTrue(password.contains(where: { PasswordGenerator.digits.contains($0) }))
            XCTAssertTrue(password.contains(where: { PasswordGenerator.symbols.contains($0) }))
        }
        XCTAssertFalse(PasswordGenerator.generate(length: 30, includeSymbols: false).contains(where: { PasswordGenerator.symbols.contains($0) }))
        XCTAssertEqual(PasswordGenerator.parse("pwd", defaultLength: 20), 20)
        XCTAssertEqual(PasswordGenerator.parse("密码 32", defaultLength: 20), 32)
        XCTAssertNil(PasswordGenerator.parse("pwd 4", defaultLength: 20))
    }

    func testColorParsingAndConversion() {
        let color = ColorValue.parse("#2f6feb")
        XCTAssertEqual(color?.hex, "#2F6FEB")
        XCTAssertEqual(color?.rgb, "rgb(47, 111, 235)")
        XCTAssertEqual(color?.hsl, "hsl(220, 82%, 55%)")
        XCTAssertEqual(ColorValue.parse("#fff")?.hex, "#FFFFFF")
        XCTAssertEqual(ColorValue.parse("rgb(255, 0, 0)")?.hsl, "hsl(0, 100%, 50%)")
        XCTAssertEqual(ColorValue.parse("hsl(120, 100%, 25%)")?.hex, "#008000")
        XCTAssertNil(ColorValue.parse("#12345"))
        XCTAssertNil(ColorValue.parse("rgb(300, 0, 0)"))
    }

    func testQRAndUUIDQueries() {
        XCTAssertEqual(QRCodeQuery.text(from: "qr https://example.com"), "https://example.com")
        XCTAssertNil(QRCodeQuery.text(from: "qr "))
        XCTAssertTrue(UUIDGenerator.matches("UUID"))
        XCTAssertEqual(UUIDGenerator.generate(uppercase: false).count, 36)
    }
}

final class EmojiCatalogTests: XCTestCase {
    func testEmbeddedCatalogMatchesSharedTSV() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Emoji/emoji.tsv")
        let shared = try String(contentsOf: url, encoding: .utf8)
        let embedded = EmojiCatalog.shared.entries
        XCTAssertEqual(embedded, EmojiCatalog(tsv: shared).entries, "Regenerate EmojiCatalogData.swift from Resources/Emoji/emoji.tsv")
        XCTAssertGreaterThan(embedded.count, 400)
    }

    func testSearchesChineseEnglishAndPinyin() {
        let catalog = EmojiCatalog.shared
        XCTAssertEqual(catalog.search("笑哭").first?.glyph, "😂")
        XCTAssertEqual(catalog.search("thumbs").first?.glyph, "👍")
        XCTAssertEqual(catalog.search("xiaoku").first?.glyph, "😂")
        XCTAssertEqual(catalog.search("cmd").first?.glyph, "⌘")
        XCTAssertEqual(EmojiCatalog.searchText(from: "emoji 火"), "火")
        XCTAssertEqual(EmojiCatalog.searchText(from: ":fire"), "fire")
        XCTAssertNil(EmojiCatalog.searchText(from: "fire"))
    }

    func testSkinToneModifiers() throws {
        let wave = try XCTUnwrap(EmojiCatalog.shared.entries.first { $0.glyph == "👋" })
        XCTAssertEqual(wave.glyph(skinTone: 3), "👋🏽")
        let victory = try XCTUnwrap(EmojiCatalog.shared.entries.first { $0.name == "剪刀手" })
        XCTAssertEqual(victory.glyph(skinTone: 1), "✌🏻")
        let fire = try XCTUnwrap(EmojiCatalog.shared.entries.first { $0.glyph == "🔥" })
        XCTAssertEqual(fire.glyph(skinTone: 3), "🔥")
    }
}
