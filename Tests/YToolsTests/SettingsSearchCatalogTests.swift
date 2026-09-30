import XCTest
import YToolsCore

final class SettingsSearchCatalogTests: XCTestCase {
    func testSyncSettingsAreDiscoverableByUserTerms() {
        for query in ["坚果云", "webdav", "SYNC", "应用密码", "同步口令", "  WEBDAV\n同步口令  "] {
            XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "clipboard", query: query), query)
            XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "appearance", query: query), query)
        }
    }

    func testEveryQueryTermMustMatchTheSameCategory() {
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "appearance", query: "主题 深色"))
        XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "appearance", query: "主题 坚果云"))
        XCTAssertFalse(SettingsSearchCatalog.matches(sectionID: "missing", query: "主题"))
        XCTAssertTrue(SettingsSearchCatalog.matches(sectionID: "general", query: " \n "))
    }
}
