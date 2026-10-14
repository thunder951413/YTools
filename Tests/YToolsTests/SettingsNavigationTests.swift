import XCTest
import YToolsCore
import YToolsModuleKit
@testable import YTools

final class SettingsNavigationTests: XCTestCase {
    func testSidebarSectionsMirrorTheSearchCatalog() {
        XCTAssertEqual(SettingsSection.allCases.map(\.rawValue), SettingsSearchCatalog.sectionIDs)
        for target in SettingsSearchCatalog.targets {
            XCTAssertNotNil(SettingsSection(rawValue: target.sectionID), target.id)
        }
        XCTAssertEqual(SettingsSectionGroup.allCases.flatMap(\.sections), SettingsSection.allCases)
    }

    @MainActor
    func testOpeningATargetSelectsItsSection() throws {
        let navigation = SettingsNavigationModel()
        navigation.searchText = "同步口令"
        navigation.open(try XCTUnwrap(SettingsSearchCatalog.searchTargets("同步口令").first))
        XCTAssertEqual(navigation.selection, .sync)
        XCTAssertEqual(navigation.targetID, "CloudPassphrase")
        XCTAssertTrue(navigation.searchText.isEmpty)
    }

    func testToolSettingsDecodeNewSwitchesWithDefaults() throws {
        let legacy = try JSONDecoder().decode(ToolSettings.self, from: Data(#"{"passwordLength":12}"#.utf8))
        XCTAssertEqual(legacy.passwordLength, 12)
        XCTAssertTrue(legacy.emojiPastesDirectly)
        XCTAssertTrue(legacy.numberBaseConversion)
        XCTAssertTrue(legacy.percentExpressions)
        var changed = ToolSettings()
        changed.percentExpressions = false
        let roundTrip = try JSONDecoder().decode(ToolSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertFalse(roundTrip.percentExpressions)
    }

    func testPercentExpressionsLiveInTheirOwnModule() async throws {
        let percent = try await PercentModule().search(ModuleSearchRequest(query: "300 的 20%"))
        XCTAssertEqual(percent.first?.title, "60")
        let plain = try await PercentModule().search(ModuleSearchRequest(query: "1+2"))
        XCTAssertTrue(plain.isEmpty)
        let calculator = try await CalculatorModule().search(ModuleSearchRequest(query: "300 的 20%"))
        XCTAssertTrue(calculator.isEmpty)
    }

    func testEmojiActionFollowsThePasteSetting() async throws {
        let pasting = try await EmojiModule(skinTone: 0, pastesDirectly: true).search(ModuleSearchRequest(query: "emoji 火"))
        let copying = try await EmojiModule(skinTone: 0, pastesDirectly: false).search(ModuleSearchRequest(query: "emoji 火"))
        guard case .paste = try XCTUnwrap(pasting.first).action else { return XCTFail("expected paste") }
        guard case .copy = try XCTUnwrap(copying.first).action else { return XCTFail("expected copy") }
    }
}
