import Foundation
import YToolsCore
import YToolsModuleKit

private enum CheckFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case let .message(value): value
        }
    }
}

@main
struct YToolsCoreChecks {
    static func main() throws {
        try checkCalculator()
        try checkPanelCommandRouter()
        try checkFirstKeyBackspacePolicy()
        try checkSearchNormalization()
        try checkClipboardPolicy()
        try checkClipboardRetentionPolicy()
        try checkRelativePanelPlacement()
        try checkModuleBoundary()
        print("YToolsCore checks passed")
    }

    private static func checkCalculator() throws {
        let calculator = ExpressionCalculator()
        let cases: [(String, Double)] = [
            ("2 + 3 * 4", 14),
            ("(2 + 3) ^ 2", 25),
            ("2 ^ 3 ^ 2", 512),
            ("-2 × 4 + 10 ÷ 2", -3),
            ("sqrt(16) + abs(-2)", 6),
            ("round(pi)", 3)
        ]
        for (expression, expected) in cases {
            let actual = try calculator.evaluate(expression)
            guard actual == expected else {
                throw CheckFailure.message("Calculator mismatch for \(expression): \(actual) != \(expected)")
            }
        }
        do {
            _ = try calculator.evaluate("1 / 0")
            throw CheckFailure.message("Calculator accepted division by zero")
        } catch CalculatorError.divisionByZero {
            // Expected.
        }
    }

    private static func checkPanelCommandRouter() throws {
        let router = PanelCommandRouter()
        let first = router.command(
            for: PanelKeyEvent(keyCode: 18, modifiers: .command),
            mode: .launcher
        )
        guard first == .activateResult(0) else {
            throw CheckFailure.message("Command + 1 mapping failed")
        }
        let buffered = router.command(
            for: PanelKeyEvent(keyCode: 125, modifiers: .option),
            mode: .launcher
        )
        guard buffered == .addSelectedToBuffer(moveToNext: true) else {
            throw CheckFailure.message("Option + Down mapping failed")
        }
        let clipboardPreview = router.command(
            for: PanelKeyEvent(keyCode: 16, modifiers: .command),
            mode: .clipboard
        )
        guard clipboardPreview == nil else {
            throw CheckFailure.message("Launcher-only command escaped into clipboard mode")
        }
    }

    private static func checkFirstKeyBackspacePolicy() throws {
        var policy = FirstKeyBackspacePolicy()
        policy.beginPresentation()
        guard policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: []),
            isEditingText: true,
            hasMarkedText: false
        ), !policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: []),
            isEditingText: true,
            hasMarkedText: false
        ) else {
            throw CheckFailure.message("First-key Backspace policy did not clear exactly once")
        }

        policy.beginPresentation()
        guard !policy.shouldClearQuery(
            for: PanelKeyEvent(keyCode: 51, modifiers: .option),
            isEditingText: true,
            hasMarkedText: false
        ) else {
            throw CheckFailure.message("First-key Backspace policy intercepted a modified shortcut")
        }
    }

    private static func checkModuleBoundary() throws {
        let descriptor = ModuleDescriptor(
            id: "example",
            name: "Example",
            capabilities: [.localFileRead]
        )
        guard descriptor.capabilities == [.localFileRead] else {
            throw CheckFailure.message("Module capability declaration failed")
        }
        let result = LauncherResult(
            id: "example:result",
            moduleID: "untrusted-value",
            title: "Result",
            subtitle: "",
            icon: .system("checkmark"),
            score: 99_999,
            action: .copy("Result")
        ).hosted(by: descriptor.id, scoreRange: -10_000...10_000)
        guard result.moduleID == descriptor.id, result.score == 10_000 else {
            throw CheckFailure.message("Module result host normalization failed")
        }

        let noCapabilities = ModuleDescriptor(id: "safe", name: "Safe")
        let policy = ModuleResultPolicy()
        let external = LauncherResult(
            id: "external",
            moduleID: "safe",
            title: "External",
            subtitle: "",
            icon: .system("link"),
            score: 1,
            action: .open(URL(string: "ztools-test://blocked")!)
        )
        guard policy.sanitize(external, from: noCapabilities) == nil else {
            throw CheckFailure.message("Module policy accepted an external URL")
        }
        let copied = LauncherResult(
            id: "copy",
            moduleID: "wrong",
            title: "Copy",
            subtitle: "",
            icon: .system("doc.on.doc"),
            score: 1,
            action: .copy("value")
        )
        guard policy.sanitize(copied, from: noCapabilities)?.moduleID == "safe" else {
            throw CheckFailure.message("Module policy rejected a safe copy result")
        }
        let dictionaryLookup = LauncherResult(
            id: "dictionary:hello",
            moduleID: "dictionary",
            title: "hello",
            subtitle: "definition",
            icon: .system("character.book.closed"),
            score: 100,
            action: .openDictionary("hello")
        )
        guard policy.sanitize(dictionaryLookup, from: noCapabilities) == nil,
              ModuleResultPolicy(allowsDictionaryLookup: true)
                .sanitize(dictionaryLookup, from: noCapabilities) != nil else {
            throw CheckFailure.message("Dictionary lookup action policy failed")
        }
        let privileged = LauncherResult(
            id: "system",
            moduleID: "wrong",
            title: "Sleep displays",
            subtitle: "",
            icon: .system("display"),
            score: 1,
            action: .sleepDisplays
        )
        guard policy.sanitize(privileged, from: noCapabilities) == nil,
              ModuleResultPolicy(allowsPrivilegedActions: true)
                .sanitize(privileged, from: noCapabilities) != nil else {
            throw CheckFailure.message("Privileged module action policy failed")
        }
        let emptyTrash = LauncherResult(
            id: "empty-trash",
            moduleID: "wrong",
            title: "Empty Trash",
            subtitle: "",
            icon: .system("trash.slash"),
            score: 1,
            action: .emptyTrash
        )
        guard policy.sanitize(emptyTrash, from: noCapabilities) == nil,
              ModuleResultPolicy(allowsPrivilegedActions: true)
                .sanitize(emptyTrash, from: noCapabilities) != nil else {
            throw CheckFailure.message("Empty Trash privileged action policy failed")
        }
    }

    private static func checkSearchNormalization() throws {
        let forms = SearchTextNormalizer().forms(for: "微信")
        guard forms.abbreviation == "wx",
              forms.transliteration == "weixin",
              forms.transliterationInitials == "wx" else {
            throw CheckFailure.message(
                "Pinyin normalization failed: \(forms.transliteration), \(forms.transliterationInitials)"
            )
        }
        let camel = SearchTextNormalizer().forms(for: "Visual Studio Code")
        guard camel.abbreviation == "vsc" else {
            throw CheckFailure.message("Application abbreviation normalization failed")
        }
        guard let compact = SearchTextNormalizer().fuzzyScore(query: "slk", candidate: "Slack"),
              SearchTextNormalizer().fuzzyScore(query: "ks", candidate: "Slack") == nil,
              compact > 0 else {
            throw CheckFailure.message("Ordered fuzzy matching failed")
        }
    }

    private static func checkClipboardPolicy() throws {
        let policy = ClipboardTextPolicy(maximumCharacters: 100)
        guard policy.shouldStore(String(repeating: "字", count: 100)),
              !policy.shouldStore(String(repeating: "字", count: 101)) else {
            throw CheckFailure.message("Clipboard text length policy failed")
        }
    }

    private static func checkClipboardRetentionPolicy() throws {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let old = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let policy = ClipboardRetentionPolicy(retentionDays: 7, maximumItems: 0)
        guard !policy.shouldRetain(createdAt: old, useCount: 4, isPinned: false, now: now),
              policy.shouldRetain(createdAt: old, useCount: 5, isPinned: false, now: now),
              policy.limitedCount(10_000) == 10_000 else {
            throw CheckFailure.message("Clipboard retention or unlimited-item policy failed")
        }
    }

    private static func checkRelativePanelPlacement() throws {
        guard let placement = RelativePanelPlacement(
            left: 360,
            top: 681,
            visibleOriginX: 0,
            visibleOriginY: 24,
            visibleWidth: 1_440,
            visibleHeight: 876
        ) else {
            throw CheckFailure.message("Relative panel placement rejected valid geometry")
        }
        let left = placement.resolvedLeft(visibleOriginX: 1_440, visibleWidth: 1_920)
        let top = placement.resolvedTop(visibleOriginY: 0, visibleHeight: 1_080)
        guard abs(left - 1_920) < 0.001, abs(top - 810) < 0.001 else {
            throw CheckFailure.message("Relative panel placement did not scale with the display")
        }
    }
}
