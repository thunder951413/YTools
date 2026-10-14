import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

@MainActor
final class LargeTypeWindowController: NSWindowController {
    init() {
        let panel = LargeTypePanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(text: String) {
        guard let window, !text.isEmpty else { return }
        window.contentViewController = NSHostingController(rootView: LargeTypeView(text: text))
        window.setContentSize(NSSize(width: 900, height: 420))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows `text` as a QR code generated locally with Core Image.
    func show(qrCode text: String) {
        guard let window, let image = QRCodeRenderer.image(for: text) else { return }
        window.contentViewController = NSHostingController(rootView: QRCodeView(text: text, image: image))
        window.setContentSize(NSSize(width: 460, height: 560))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private final class LargeTypePanel: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}

private struct LargeTypeView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.25)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .padding(56)
                .frame(maxWidth: .infinity, minHeight: 380)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

enum QRCodeRenderer {
    /// Error correction "M", scaled with nearest-neighbour sampling so modules stay crisp.
    static func image(for text: String, side: CGFloat = 360) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }
        let scale = (side / output.extent.width).rounded(.down)
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}

private struct QRCodeView: View {
    let text: String
    let image: NSImage
    @State private var copied = false

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: 320, height: 320)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("二维码")
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            Button(copied ? "已复制图片" : "复制二维码图片") {
                let board = NSPasteboard.general
                board.clearContents()
                copied = board.writeObjects([image])
            }
            .keyboardShortcut("c", modifiers: .command)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

