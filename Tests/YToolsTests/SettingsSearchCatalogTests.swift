import XCTest
import YToolsCore

final class SettingsSearchCatalogTests: XCTestCase {
    func testSyncSettingsAreDiscoverableByUserTerms() {
        for query in ["坚果云", "webdav", "SYNC", "应用密码", "同步口令", "  WEBDAV\n同步口令  "] {
            XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "clipboard", query: query), query)
            XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "appearance", query: query), query)
        }
    }

    func testSpecificTargetsHaveUniqueIDsAndMatchAllTerms() {
        XCTAssertEqual(Set(SettingsSearchCatalog.targets.map(\.id)).count, SettingsSearchCatalog.targets.count)
        XCTAssertEqual(SettingsSearchCatalog.searchTargets("  WEBDAV\n同步口令  ").map(\.id), ["CloudPassphrase"])
        XCTAssertEqual(SettingsSearchCatalog.searchTargets("保留 天数").map(\.id), ["ClipboardRetentionDays"])
        XCTAssertTrue(SettingsSearchCatalog.searchTargets("主题 坚果云").isEmpty)
        XCTAssertTrue(SettingsSearchCatalog.searchTargets(" ").isEmpty)
        XCTAssertEqual(SettingsSearchCatalog.targetID(forRowTitle: "输入停止后搜索"), "SearchInputDelay")
    }

    func testEveryQueryTermMustMatchTheSameCategory() {
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "appearance", query: "主题 深色"))
        XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "appearance", query: "主题 坚果云"))
        XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "missing", query: "主题"))
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "general", query: " \n "))
    }
}
