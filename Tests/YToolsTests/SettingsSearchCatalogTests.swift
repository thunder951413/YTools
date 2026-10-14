import XCTest
import YToolsCore

final class SettingsSearchCatalogTests: XCTestCase {
    func testSyncSettingsAreDiscoverableByUserTerms() {
        for query in ["坚果云", "webdav", "SYNC", "应用密码", "同步口令", "  WEBDAV\n同步口令  "] {
            XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "sync", query: query), query)
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

    func testEveryTargetBelongsToAKnownSectionWithKeywords() {
        let sections = Set(SettingsSearchCatalog.sectionIDs)
        XCTAssertEqual(sections.count, SettingsSearchCatalog.sectionIDs.count)
        for target in SettingsSearchCatalog.targets {
            XCTAssertTrue(sections.contains(target.sectionID), target.id)
        }
        for section in sections {
            XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: section, query: "不存在的词"), section)
        }
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "tools", query: "时间戳"))
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "permissions", query: "辅助功能"))
        XCTAssertEqual(SettingsSearchCatalog.searchTargets("截图 识别").first?.id, "RecognizeTextHotKey")
        XCTAssertEqual(SettingsSearchCatalog.targetID(forRowTitle: "进制转换"), "NumberBaseConversion")
    }

    func testEveryQueryTermMustMatchTheSameCategory() {
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "appearance", query: "主题 深色"))
        XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "appearance", query: "主题 坚果云"))
        XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "missing", query: "主题"))
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "general", query: " \n "))
    }
}
