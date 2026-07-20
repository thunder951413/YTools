import XCTest
import YToolsCore

final class SearchTextNormalizerTests: XCTestCase {
    func testCreatesPinyinAndInitialForms() {
        let forms = SearchTextNormalizer().forms(for: "微信")
        XCTAssertEqual(forms.transliteration, "weixin")
        XCTAssertEqual(forms.transliterationInitials, "wx")
        XCTAssertEqual(forms.abbreviation, "wx")
    }

    func testCreatesMultiwordAbbreviation() {
        XCTAssertEqual(
            SearchTextNormalizer().forms(for: "Visual Studio Code").abbreviation,
            "vsc"
        )
    }

    func testScoresOrderedFuzzyMatches() {
        let normalizer = SearchTextNormalizer()
        XCTAssertNotNil(normalizer.fuzzyScore(query: "slk", candidate: "Slack"))
        XCTAssertNotNil(normalizer.fuzzyScore(query: "vsd", candidate: "Visual Studio Code"))
    }

    func testRejectsOutOfOrderAndMissingFuzzyMatches() {
        let normalizer = SearchTextNormalizer()
        XCTAssertNil(normalizer.fuzzyScore(query: "ks", candidate: "Slack"))
        XCTAssertNil(normalizer.fuzzyScore(query: "slz", candidate: "Slack"))
    }

    func testRewardsCompactFuzzyMatches() throws {
        let normalizer = SearchTextNormalizer()
        let compact = try XCTUnwrap(normalizer.fuzzyScore(query: "abc", candidate: "abcd"))
        let scattered = try XCTUnwrap(normalizer.fuzzyScore(query: "abc", candidate: "a123b123c"))
        XCTAssertGreaterThan(compact, scattered)
    }
}

final class ApplicationAliasMatcherTests: XCTestCase {
    func testParsesLocalizedSeparatorsAndPreservesPhrases() {
        let aliases = ApplicationAliasMatcher().aliases(from: "微信，weixin; wx\nWork Chat")
        XCTAssertEqual(aliases, ["微信", "weixin", "wx", "Work Chat"])
    }

    func testMatchesChineseAliasByPinyinAndInitials() {
        let matcher = ApplicationAliasMatcher()
        XCTAssertNotNil(matcher.score(query: "weixin", aliases: ["微信"]))
        XCTAssertNotNil(matcher.score(query: "wx", aliases: ["微信"]))
    }

    func testExactAliasRanksAboveFuzzyAlias() throws {
        let matcher = ApplicationAliasMatcher()
        let exact = try XCTUnwrap(matcher.score(query: "chat", aliases: ["chat"]))
        let fuzzy = try XCTUnwrap(matcher.score(query: "cht", aliases: ["chat"]))
        XCTAssertGreaterThan(exact, fuzzy)
    }
}

final class ClipboardTextPolicyTests: XCTestCase {
    func testRejectsTextBeyondConfiguredCharacterLimit() {
        let policy = ClipboardTextPolicy(maximumCharacters: 100)
        XCTAssertTrue(policy.shouldStore(String(repeating: "字", count: 100)))
        XCTAssertFalse(policy.shouldStore(String(repeating: "字", count: 101)))
    }

    func testRejectsEmptyText() {
        XCTAssertFalse(ClipboardTextPolicy(maximumCharacters: 100).shouldStore(""))
    }
}
