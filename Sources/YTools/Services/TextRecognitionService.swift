import AppKit
import ScreenCaptureKit
import Vision

/// A captured screen image that can cross actors; it is never mutated.
struct CapturedImage: @unchecked Sendable {
    let image: CGImage
}

/// Global shortcut → freeze the screen under the pointer → select a region →
/// recognise its text on-device with Vision → copy it. Needs the Screen
/// Recording permission; nothing leaves the Mac.
@MainActor
final class TextRecognitionService {
    static let shared = TextRecognitionService()
    private var selectionWindow: RegionSelectionWindow?

    var hasScreenRecordingPermission: Bool { CGPreflightScreenCaptureAccess() }

    func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    func start() {
        guard selectionWindow == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            ToastPresenter.show("截图识别文字需要“屏幕与系统录音”权限", systemImage: "exclamationmark.triangle.fill", duration: .seconds(3))
            return
        }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let width = Int(screen.frame.width * screen.backingScaleFactor)
        let height = Int(screen.frame.height * screen.backingScaleFactor)
        let processID = ProcessInfo.processInfo.processIdentifier
        Task { @MainActor in
            do {
                let captured = try await Self.captureDisplay(displayID, width: width, height: height, excludingProcess: processID)
                self.presentSelection(captured, on: screen)
            } catch {
                ToastPresenter.show("无法截取屏幕：\(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill", duration: .seconds(3))
            }
        }
    }

    private func presentSelection(_ captured: CapturedImage, on screen: NSScreen) {
        let window = RegionSelectionWindow(screen: screen, image: captured.image) { [weak self] cropped in
            guard let self else { return }
            self.selectionWindow?.orderOut(nil)
            self.selectionWindow = nil
            guard let cropped else { return }
            Task { @MainActor in await self.recognizeAndCopy(CapturedImage(image: cropped)) }
        }
        selectionWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func recognizeAndCopy(_ captured: CapturedImage) async {
        do {
            let text = try await Self.recognizeText(in: captured)
            guard !text.isEmpty else {
                ToastPresenter.show("所选区域没有识别到文字", systemImage: "text.magnifyingglass")
                return
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            let lines = text.split(separator: "\n").count
            ToastPresenter.show("已识别 \(lines) 行文字并复制")
        } catch {
            ToastPresenter.show("文字识别失败：\(error.localizedDescription)", systemImage: "exclamationmark.triangle.fill", duration: .seconds(3))
        }
    }

    nonisolated static func captureDisplay(
        _ displayID: CGDirectDisplayID, width: Int, height: Int, excludingProcess processID: pid_t
    ) async throws -> CapturedImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CocoaError(.featureUnsupported)
        }
        let ownWindows = content.windows.filter { $0.owningApplication?.processID == processID }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        return CapturedImage(image: image)
    }

    /// On-device recognition for Simplified/Traditional Chinese and English.
    nonisolated static func recognizeText(in captured: CapturedImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            try VNImageRequestHandler(cgImage: captured.image, options: [:]).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.joined(separator: "\n")
        }.value
    }
}
