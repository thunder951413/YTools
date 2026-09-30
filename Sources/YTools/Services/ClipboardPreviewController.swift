import Combine
import Foundation
import ImageIO

struct ClipboardPreviewImage: Sendable {
    let image: CGImage
    let width: Int
    let height: Int
}

actor ClipboardPreviewDecoder {
    func decode(_ data: Data) -> ClipboardPreviewImage? {
        guard data.count <= 5_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024
              ] as CFDictionary) else { return nil }
        return ClipboardPreviewImage(image: image, width: width.intValue, height: height.intValue)
    }
}

/// Owns preview cancellation separately from history capture and persistence.
@MainActor
final class ClipboardPreviewController: ObservableObject {
    @Published private(set) var isVisible = false
    @Published private(set) var item: ClipboardHistoryItem?
    @Published private(set) var image: ClipboardPreviewImage?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let loadImage: @Sendable (UUID) async -> Data?
    private let decoder = ClipboardPreviewDecoder()
    private var task: Task<Void, Never>?
    private var generation = 0

    init(loadImage: @escaping @Sendable (UUID) async -> Data?) { self.loadImage = loadImage }

    func show(_ selected: ClipboardHistoryItem?) { isVisible = true; select(selected) }
    func hide() { isVisible = false; clearContent() }
    func clearContent() {
        generation += 1
        task?.cancel()
        task = nil
        item = nil
        image = nil
        error = nil
        isLoading = false
    }
    func select(_ selected: ClipboardHistoryItem?) {
        guard isVisible else { return }
        if item == selected { return }
        clearContent()
        item = selected
        guard let selected, selected.kind == .image else { return }
        isLoading = true
        let requestedGeneration = generation
        task = Task { [weak self, loadImage, decoder] in
            let data = await loadImage(selected.id)
            guard !Task.isCancelled else { return }
            let decoded = if let data { await decoder.decode(data) } else { nil as ClipboardPreviewImage? }
            guard !Task.isCancelled, let self, self.isVisible, self.generation == requestedGeneration,
                  self.item?.id == selected.id else { return }
            self.image = decoded
            self.isLoading = false
            self.error = decoded == nil ? "无法读取或解码图片原件；未使用缩略图替代。" : nil
        }
    }
    func waitUntilLoaded() async { await task?.value }
}
