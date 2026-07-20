import XCTest
import YToolsModuleKit

final class ModuleResultPolicyTests: XCTestCase {
    func testRejectsExternalURLFromSourceModule() {
        let descriptor = ModuleDescriptor(id: "test", name: "Test")
        let result = LauncherResult(
            id: "external",
            moduleID: descriptor.id,
            title: "External",
            subtitle: "",
            icon: .system("link"),
            score: 1,
            action: .open(URL(string: "ztools-test://blocked")!)
        )
        XCTAssertNil(ModuleResultPolicy().sanitize(result, from: descriptor))
    }

    func testRequiresBothDeclarationAndHostGrantForFiles() {
        let descriptor = ModuleDescriptor(
            id: "files",
            name: "Files",
            capabilities: [.localFileRead]
        )
        let url = URL(fileURLWithPath: "/tmp/example.txt")
        let result = LauncherResult(
            id: "file",
            moduleID: descriptor.id,
            title: "File",
            subtitle: url.path,
            icon: .file(url),
            score: 1,
            action: .open(url)
        )
        XCTAssertNil(ModuleResultPolicy().sanitize(result, from: descriptor))
        XCTAssertNotNil(
            ModuleResultPolicy(allowedCapabilities: [.localFileRead])
                .sanitize(result, from: descriptor)
        )
    }

    func testPrivilegedActionsRequireTrustedHostPolicy() {
        let descriptor = ModuleDescriptor(id: "system", name: "System")
        let result = LauncherResult(
            id: "sleep",
            moduleID: descriptor.id,
            title: "Sleep displays",
            subtitle: "",
            icon: .system("display"),
            score: 1,
            action: .sleepDisplays
        )
        XCTAssertNil(ModuleResultPolicy().sanitize(result, from: descriptor))
        XCTAssertNotNil(
            ModuleResultPolicy(allowsPrivilegedActions: true)
                .sanitize(result, from: descriptor)
        )
    }

    func testEmptyTrashRequiresTrustedHostPolicy() {
        let descriptor = ModuleDescriptor(id: "system", name: "System")
        let result = LauncherResult(
            id: "empty-trash",
            moduleID: descriptor.id,
            title: "Empty Trash",
            subtitle: "",
            icon: .system("trash.slash"),
            score: 1,
            action: .emptyTrash
        )
        XCTAssertNil(ModuleResultPolicy().sanitize(result, from: descriptor))
        XCTAssertNotNil(
            ModuleResultPolicy(allowsPrivilegedActions: true)
                .sanitize(result, from: descriptor)
        )
    }

    func testRejectsOversizedCopyPayload() {
        let descriptor = ModuleDescriptor(id: "copy", name: "Copy")
        let result = LauncherResult(
            id: "oversized",
            moduleID: descriptor.id,
            title: "Oversized",
            subtitle: "",
            icon: .system("doc.on.doc"),
            score: 1,
            action: .copy(String(repeating: "x", count: 1_000_001))
        )
        XCTAssertNil(ModuleResultPolicy().sanitize(result, from: descriptor))
    }
}
