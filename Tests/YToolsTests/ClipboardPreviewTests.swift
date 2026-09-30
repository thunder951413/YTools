import Foundation
import XCTest
@testable import YTools

@MainActor
final class ClipboardPreviewTests: XCTestCase {
    func testSwitchAndHideInvalidateDelayedImage() async {
        let gate = PreviewDataGate()
        let controller = ClipboardPreviewController { _ in await gate.load() }
        let image = item(.image, ["image"])
        controller.show(image)
        await gate.waitUntilRequested()
        let text = item(.text, [String(repeating: "完整文本\n", count: 300)])
        controller.select(text)
        await gate.finish(nil)
        await Task.yield()
        XCTAssertEqual(controller.item, text)
        XCTAssertNil(controller.image)
        XCTAssertNil(controller.error)
        XCTAssertFalse(controller.isLoading)
        controller.hide()
        XCTAssertNil(controller.item)
        XCTAssertFalse(controller.isVisible)
    }

    func testMissingOriginalNeverUsesStoredThumbnail() async {
        let controller = ClipboardPreviewController { _ in nil }
        controller.show(item(.image, ["image"], binary: Data([1, 2, 3])))
        await controller.waitUntilLoaded()
        XCTAssertNil(controller.image)
        XCTAssertNotNil(controller.error)
        XCTAssertFalse(controller.isLoading)
    }

    func testOriginalImageDecoderReportsDimensionsAndRejectsOversizeData() async throws {
        let decoder = ClipboardPreviewDecoder()
        let data = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGP4DwQACfsD/fteaysAAAAASUVORK5CYII="))
        let image = await decoder.decode(data)
        XCTAssertEqual(image?.width, 1)
        XCTAssertEqual(image?.height, 1)
        let rejected = await decoder.decode(Data(repeating: 0, count: 5_000_001))
        XCTAssertNil(rejected)
    }

    private func item(_ kind: ClipboardHistoryItem.Kind, _ payload: [String], binary: Data? = nil) -> ClipboardHistoryItem {
        ClipboardHistoryItem(id: UUID(), kind: kind, payload: payload, createdAt: Date(), sourceApplication: nil, binaryData: binary)
    }
}

private actor PreviewDataGate {
    private var continuation: CheckedContinuation<Data?, Never>?
    func load() async -> Data? { await withCheckedContinuation { continuation = $0 } }
    func waitUntilRequested() async { while continuation == nil { await Task.yield() } }
    func finish(_ data: Data?) { continuation?.resume(returning: data); continuation = nil }
}
