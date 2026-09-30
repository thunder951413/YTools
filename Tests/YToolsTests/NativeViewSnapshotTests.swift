import AppKit
import SwiftUI
import XCTest
@testable import YTools
import YToolsModuleKit

@MainActor
final class NativeViewSnapshotTests: XCTestCase {
    func testClipboardPanelRendersCopyFailureWithSyntheticHistory() async throws {
        guard let outputValue = ProcessInfo.processInfo.environment["YTOOLS_UI_SNAPSHOT_DIR"], !outputValue.isEmpty else {
            throw XCTSkip("Set YTOOLS_UI_SNAPSHOT_DIR to render clipboard panel review PNGs.")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ytools-panel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = Data(repeating: 1, count: 32)
        _ = try ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }).persist([
            ClipboardHistoryItem(id: UUID(), kind: .text,
                payload: ["用于验证完整剪贴板面板的长文本：复制失败时应显示原因并保留列表，工具栏、固定按钮和底部快捷键都应保持可见。"],
                createdAt: Date(), sourceApplication: "Synthetic Fixture", isPinned: true)
        ] + (0..<250).map { index in
            ClipboardHistoryItem(id: UUID(), kind: .text, payload: ["合成记录 \(index + 1)：用于分页与选中态检查"],
                createdAt: Date().addingTimeInterval(-Double(index + 1)), sourceApplication: "Synthetic Fixture")
        })
        let suite = "ytools-panel-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferences(defaults: defaults, launchAtLoginService: SnapshotLoginService())
        let board = NSPasteboard(name: .init("ytools-test-\(UUID())"))
        defer { board.releaseGlobally() }
        let manager = ClipboardHistoryManager(preferences: preferences,
            persistence: ClipboardPersistenceService { ClipboardHistoryStore(rootURL: directory, keyProvider: { _ in key }) },
            cloudSync: ClipboardCloudSyncService(
                credentialStore: SecureCodableStore(fileURL: directory.appendingPathComponent("credentials.enc")) { _ in key },
                stateStore: SecureCodableStore(fileURL: directory.appendingPathComponent("state.enc")) { _ in key },
                transport: SnapshotCloudTransport()),
            pasteboard: board, monitorsClipboard: false)
        await manager.waitUntilLoaded()
        let copied = await manager.copy(ClipboardHistoryItem(id: UUID(), kind: .image, payload: ["missing"], createdAt: Date(), sourceApplication: nil))
        XCTAssertFalse(copied)
        XCTAssertNotNil(manager.copyError)
        let output = URL(fileURLWithPath: outputValue, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for filter in [ClipboardHistoryManager.Filter.all, .pinned] {
            manager.filter = filter
            for scheme in [ColorScheme.light, .dark] {
                // ImageRenderer cannot draw AppKit-backed TextField/Picker/List.
                // Host the real panel in an offscreen native window instead.
                _ = NSApplication.shared
                let frame = NSRect(x: 0, y: 0, width: 720, height: 420)
                let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                defer { window.close() }
                let view = NSHostingView(rootView: ClipboardHistoryView(manager: manager, preferences: preferences, onActivate: {})
                    .frame(width: 720, height: 420).colorScheme(scheme))
                window.contentView = view
                view.frame = frame
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let image = NSImage(size: frame.size)
                image.addRepresentation(bitmap)
                XCTAssertEqual(image.size.width, 720)
                XCTAssertEqual(image.size.height, 420)
                try writePng(image, to: output.appendingPathComponent("clipboard-\(filter == .all ? "panel" : "pinned")-\(name(for: scheme)).png"))
            }
        }
        await manager.flushPendingChanges()
    }

    func testNativeRowsAndSettingsGroupRenderInLightAndDarkThemes() throws {
        guard let outputValue = ProcessInfo.processInfo.environment["YTOOLS_UI_SNAPSHOT_DIR"],
              !outputValue.isEmpty else {
            throw XCTSkip("Set YTOOLS_UI_SNAPSHOT_DIR to render component-level UI review PNGs.")
        }

        let outputDirectory = URL(fileURLWithPath: outputValue, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: fixture.colorScheme(scheme))
            renderer.scale = 2
            renderer.proposedSize = ProposedViewSize(width: 720, height: nil)
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertGreaterThanOrEqual(image.size.width, 700)
            XCTAssertGreaterThan(image.size.height, 180)
            try writePng(image, to: outputDirectory.appendingPathComponent("native-components-\(name(for: scheme)).png"))
        }
    }

    private var fixture: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("组件级视觉审查：长文本、选中状态与右侧控件")
                .font(.caption)
                .foregroundStyle(.secondary)

            ResultRow(
                result: LauncherResult(
                    id: "snapshot-result",
                    moduleID: "snapshot",
                    title: "一条用于验证单行截断、选中色和键盘快捷键不会覆盖右侧内容的非常长的本地文件搜索结果标题",
                    subtitle: "/Users/example/Documents/一个很长的目录名称/用于视觉验收的文件路径/quarterly-review-final-version.md",
                    icon: .system("doc.text"),
                    score: 100,
                    action: .none
                ),
                selected: true,
                compact: false,
                showSubtitle: true,
                buffered: true,
                shortcutNumber: 9,
                selectionOpacity: 0.16
            )

            ClipboardHistoryRow(
                item: ClipboardHistoryItem(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    kind: .files,
                    payload: ["/tmp/这是一个很长很长的文件名，用来验证剪贴板历史行在固定按钮存在时仍会截断而不重叠.txt"],
                    createdAt: Date(timeIntervalSince1970: 1_725_000_000),
                    sourceApplication: "YTools Snapshot Fixture",
                    isPinned: true,
                    copyCount: 12
                ),
                selected: true,
                compact: false,
                onTogglePin: {}
            )

            SettingsCard(title: "剪贴板与同步", icon: "lock.shield") {
                SettingsRow(
                    title: "同步状态",
                    detail: "仅在用户保存凭据并显式启用后连接固定 WebDAV 地址；长说明应保留在左列。"
                ) {
                    Text("已启用")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.16))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(24)
        .frame(width: 720, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func name(for scheme: ColorScheme) -> String {
        scheme == .dark ? "dark" : "light"
    }

    private func writePng(_ image: NSImage, to url: URL) throws {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let representation = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw SnapshotError.unavailableImage
        }
        let bitmap = NSBitmapImageRep(cgImage: representation)
        guard let data = bitmap.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
            throw SnapshotError.unavailablePng
        }
        try data.write(to: url, options: Data.WritingOptions.atomic)
    }

    private enum SnapshotError: Error {
        case unavailableImage
        case unavailablePng
    }
}

@MainActor
private struct SnapshotLoginService: LaunchAtLoginManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

private struct SnapshotCloudTransport: ClipboardCloudTransport {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> (status: Int, data: Data) {
        throw URLError(.unsupportedURL)
    }
}
