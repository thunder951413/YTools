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
