import Foundation
import XCTest
@testable import YToolsCore

final class MacApplicationPathPolicyTests: XCTestCase {
    func testStrictNormalizationAcceptsValidApplicationBundle() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let application = try makeApplicationBundle(in: directory, name: "Example")

        XCTAssertEqual(
            MacApplicationPathPolicy.normalize(url: application, requireExistingBundle: true),
            canonicalPath(for: application)
        )
    }

    func testStrictNormalizationRejectsMissingApplicationBundle() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missingApplication = directory.appendingPathComponent("Missing.app")

        XCTAssertNil(MacApplicationPathPolicy.normalize(url: missingApplication, requireExistingBundle: true))
        XCTAssertEqual(
            MacApplicationPathPolicy.normalize(url: missingApplication, requireExistingBundle: false),
            canonicalPath(for: missingApplication)
        )
    }

    func testNormalizationRejectsNonApplicationsOrdinaryDirectoriesAndRelativePaths() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textFile = directory.appendingPathComponent("Example.txt")
        let ordinaryDirectory = directory.appendingPathComponent("Ordinary.app")
        FileManager.default.createFile(atPath: textFile.path, contents: Data())
        try FileManager.default.createDirectory(at: ordinaryDirectory, withIntermediateDirectories: false)

        XCTAssertNil(MacApplicationPathPolicy.normalize(url: textFile, requireExistingBundle: false))
        XCTAssertNil(MacApplicationPathPolicy.normalize(url: ordinaryDirectory, requireExistingBundle: true))
        XCTAssertNil(MacApplicationPathPolicy.normalize(path: "Example.app", requireExistingBundle: false))
    }

    func testNormalizationResolvesSymlinksAndDeduplicatesCaseInsensitively() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let application = try makeApplicationBundle(in: directory, name: "Example")
        let link = directory.appendingPathComponent("Linked.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: application)

        XCTAssertEqual(
            MacApplicationPathPolicy.normalize(url: link, requireExistingBundle: true),
            canonicalPath(for: application)
        )
        XCTAssertEqual(
            MacApplicationPathPolicy.normalize(
                paths: [application.path, link.path, application.path.uppercased()],
                requireExistingBundle: false
            ),
            [canonicalPath(for: application)]
        )
        XCTAssertEqual(
            MacApplicationPathPolicy.normalize(
                paths: ["/Applications/Zeta.app", "/Applications/alpha.app", "/Applications/ALPHA.app"],
                requireExistingBundle: false
            ),
            ["/Applications/alpha.app", "/Applications/Zeta.app"]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func makeApplicationBundle(in directory: URL, name: String) throws -> URL {
        let application = directory.appendingPathComponent("\(name).app", isDirectory: true)
        let contents = application.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": "com.ytools.tests.\(name.lowercased())"]
        let plistURL = contents.appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: plistURL)
        return application
    }

    private func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
