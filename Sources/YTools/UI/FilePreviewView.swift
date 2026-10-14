import QuickLookUI
import SwiftUI

struct FilePreviewView: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var displayedURL: URL?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        view.setAccessibilityLabel("文件预览：\(url.lastPathComponent)")
        context.coordinator.displayedURL = url
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard context.coordinator.displayedURL != url else { return }
        context.coordinator.displayedURL = url
        view.previewItem = url as NSURL
        view.setAccessibilityLabel("文件预览：\(url.lastPathComponent)")
        view.refreshPreviewItem()
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.previewItem = nil
        coordinator.displayedURL = nil
    }
}

/// PDF and Office documents can be slow to render; users may turn their
/// Quick Look preview off in settings.
enum FilePreviewPolicy {
    static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "odt", "ods", "odp"
    ]

    static func isDocument(_ url: URL) -> Bool {
        documentExtensions.contains(url.pathExtension.lowercased())
    }
}
