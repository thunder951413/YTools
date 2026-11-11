import Carbon
import Foundation
import XCTest
@testable import YTools

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testCustomApplicationPersistsAndReloadsCanonicalPath() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let application = try makeApplicationBundle(in: fixture.directory, name: "External Tool")
        let preferences = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())

        let canonicalPath = try XCTUnwrap(preferences.addCustomApplication(application))
        let reloaded = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())

        XCTAssertEqual(reloaded.customApplicationPaths, [canonicalPath])
    }

    func testRemovingCustomApplicationAlsoRemovesItsAlias() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let application = try makeApplicationBundle(in: fixture.directory, name: "Writing Tool")
        let preferences = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())
        let canonicalPath = try XCTUnwrap(preferences.addCustomApplication(application))
        preferences.addApplicationAliasTarget(application)
        preferences.setApplicationAliases("draft", forPath: canonicalPath)

        preferences.removeCustomApplication(canonicalPath)

        XCTAssertTrue(preferences.customApplicationPaths.isEmpty)
        XCTAssertNil(preferences.applicationAliases[canonicalPath])
    }

    func testRestoreDefaultsClearsCustomApplicationsAndAliases() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let application = try makeApplicationBundle(in: fixture.directory, name: "Reset Tool")
        let preferences = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())
        _ = preferences.addCustomApplication(application)
        preferences.addApplicationAliasTarget(application)

        preferences.restoreDefaults()

        XCTAssertTrue(preferences.customApplicationPaths.isEmpty)
        XCTAssertTrue(preferences.applicationAliases.isEmpty)
    }

    func testRejectsDirectoryThatOnlyUsesAppExtension() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let invalid = fixture.directory.appendingPathComponent("Invalid.app", isDirectory: true)
        try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: false)
        let preferences = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())

        XCTAssertNil(preferences.addCustomApplication(invalid))
        XCTAssertTrue(preferences.customApplicationPaths.isEmpty)
    }

    func testLastLauncherQueryPersistsAcrossReload() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let preferences = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())

        preferences.lastLauncherQuery = "微信"
        let reloaded = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())

        XCTAssertEqual(reloaded.lastLauncherQuery, "微信")
    }

    func testRestoreDefaultsResetsSwappedHotKeysCustomHotKeysAndLastQuery() throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let preferences = AppPreferences(defaults: fixture.defaults, launchAtLoginService: StubLaunchAtLoginService())
        let originalLauncher = preferences.launcherHotKey
        let originalClipboard = preferences.clipboardHotKey
        let spare = HotKeyDefinition(keyCode: 11, modifiers: UInt32(cmdKey | optionKey)) // ⌥⌘B
        preferences.launcherHotKey = spare
        preferences.clipboardHotKey = originalLauncher
        preferences.launcherHotKey = originalClipboard
        preferences.lastLauncherQuery = "draft query"
        preferences.customHotKeys = [
            CustomHotKey(
                hotKey: HotKeyDefinition(keyCode: 14, modifiers: UInt32(cmdKey | optionKey)),
                target: .snippet(id: UUID()),
                title: "Sig"
            )
        ]

        preferences.restoreDefaults()

        XCTAssertEqual(preferences.launcherHotKey, originalLauncher)
        XCTAssertEqual(preferences.clipboardHotKey, originalClipboard)
        XCTAssertTrue(preferences.customHotKeys.isEmpty)
        XCTAssertEqual(preferences.lastLauncherQuery, "")
    }

    func testOversizedPNGDimensionsAreRejectedBeforeDecode() async {
        // Minimal PNG signature + IHDR declaring 10000 x 10000 (100M pixels > 50M cap).
        var png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        png.append(contentsOf: [0x00, 0x00, 0x00, 0x0D]) // IHDR length 13
        png.append(contentsOf: Array("IHDR".utf8))
        png.append(contentsOf: [0x00, 0x00, 0x27, 0x10]) // width = 10_000
        png.append(contentsOf: [0x00, 0x00, 0x27, 0x10]) // height = 10_000
        png.append(contentsOf: [0x08, 0x06, 0x00, 0x00, 0x00]) // 8-bit RGBA
        png.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // dummy CRC

        let processor = ClipboardCaptureProcessor()
        let captured = await processor.process(
            .image(data: png, isPNG: true, sourceApplication: "Test", createdAt: Date())
        )
        XCTAssertNil(captured)
    }

    private func makeFixture() throws -> Fixture {
        let suiteName = "com.ytools.tests.preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return Fixture(suiteName: suiteName, defaults: defaults, directory: directory)
    }

    private func makeApplicationBundle(in directory: URL, name: String) throws -> URL {
        let application = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = application.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "com.ytools.tests.\(UUID().uuidString)"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        return application
    }
}

@MainActor
private struct Fixture {
    let suiteName: String
    let defaults: UserDefaults
    let directory: URL

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private struct StubLaunchAtLoginService: LaunchAtLoginManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}
