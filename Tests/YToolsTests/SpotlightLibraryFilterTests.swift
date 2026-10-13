import Foundation
import XCTest
@testable import YTools

final class SpotlightLibraryFilterTests: XCTestCase {
    func testHidesSystemLibrariesButKeepsICloudDriveAndUserFolders() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(SpotlightSearchService.isLibraryNoise(home + "/Library/Caches/com.example/cache.db"))
        XCTAssertTrue(SpotlightSearchService.isLibraryNoise("/Library/Preferences/com.example.plist"))
        XCTAssertFalse(SpotlightSearchService.isLibraryNoise(home + "/Library/Mobile Documents/com~apple~CloudDocs/report.pdf"))
        XCTAssertFalse(SpotlightSearchService.isLibraryNoise(home + "/Projects/Library/notes.md"))
        XCTAssertFalse(SpotlightSearchService.isLibraryNoise(home + "/Documents/a.txt"))
    }
}
