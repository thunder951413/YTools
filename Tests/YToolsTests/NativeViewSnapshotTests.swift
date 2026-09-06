import AppKit
import SwiftUI
import XCTest
@testable import YTools
import YToolsModuleKit

@MainActor
final class NativeViewSnapshotTests: XCTestCase {
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
