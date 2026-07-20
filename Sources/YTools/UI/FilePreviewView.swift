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
        context.coordinator.displayedURL = url
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard context.coordinator.displayedURL != url else { return }
        context.coordinator.displayedURL = url
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.previewItem = nil
        coordinator.displayedURL = nil
    }
}
