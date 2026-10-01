import Foundation
import XCTest
@testable import YTools

final class ClipboardCloudSyncTests: XCTestCase {
    func testEncryptedEventEnvelopeRoundTrips() throws {
        let clear = Data("跨平台加密剪贴板".utf8)
        let encrypted = try CloudCryptography.seal(clear, passphrase: "shared-sync-secret")

        XCTAssertEqual(encrypted.prefix(5), Data("YTCE2".utf8))
        XCTAssertEqual(try CloudCryptography.open(encrypted, passphrase: "shared-sync-secret"), clear)
        XCTAssertThrowsError(try CloudCryptography.open(encrypted, passphrase: "wrong-sync-secret"))
    }
}
