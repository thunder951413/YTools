import CryptoKit
import Foundation
import ImageIO

enum ClipboardCapture: Sendable {
    case files(paths: [String], sourceApplication: String?, createdAt: Date)
    case image(data: Data, isPNG: Bool, sourceApplication: String?, createdAt: Date)
    case text(value: String, sourceApplication: String?, createdAt: Date)
}

struct ProcessedClipboardCapture: Sendable {
    let item: ClipboardHistoryItem
    let originalImage: Data?
}

/// Performs hashing, image conversion and thumbnail generation off MainActor.
actor ClipboardCaptureProcessor {
    private let maximumTextBytes = 1_000_000
    private let maximumImageBytes = 5_000_000

    func process(_ capture: ClipboardCapture) -> ProcessedClipboardCapture? {
        switch capture {
        case let .files(paths, sourceApplication, createdAt):
            let limited = Array(paths.prefix(20))
            guard !limited.isEmpty else { return nil }
            let item = ClipboardHistoryItem(
                id: UUID(),
                kind: .files,
                payload: limited,
                createdAt: createdAt,
                sourceApplication: sourceApplication,
                contentHash: contentHash(kind: .files, payload: limited)
            )
            return ProcessedClipboardCapture(item: item, originalImage: nil)

        case let .text(value, sourceApplication, createdAt):
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.lengthOfBytes(using: .utf8) <= maximumTextBytes else { return nil }
            let item = ClipboardHistoryItem(
                id: UUID(),
                kind: .text,
                payload: [value],
                createdAt: createdAt,
                sourceApplication: sourceApplication,
                contentHash: contentHash(kind: .text, payload: [value])
            )
            return ProcessedClipboardCapture(item: item, originalImage: nil)

        case let .image(data, isPNG, sourceApplication, createdAt):
            guard let normalized = isPNG ? data : normalizedPNGData(from: data),
                  normalized.count <= maximumImageBytes,
                  let dimensions = imageDimensions(normalized) else { return nil }
            let thumbnail = makeThumbnail(from: normalized)
            let item = ClipboardHistoryItem(
                id: UUID(),
                kind: .image,
                payload: ["图片 · \(dimensions.width) × \(dimensions.height)"],
                createdAt: createdAt,
                sourceApplication: sourceApplication,
                binaryData: thumbnail,
                contentHash: hash(normalized)
            )
            return ProcessedClipboardCapture(item: item, originalImage: normalized)
        }
    }

    private func normalizedPNGData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func imageDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { return nil }
        return (width.intValue, height.intValue)
    }

    private func makeThumbnail(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 192
              ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.png" as CFString,
            1,
            nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func contentHash(kind: ClipboardHistoryItem.Kind, payload: [String]) -> String {
        hash(Data("\(kind.rawValue)\0\(payload.joined(separator: "\0"))".utf8))
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
