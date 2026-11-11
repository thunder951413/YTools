import AppKit
import SwiftUI
import YToolsCore

/// Small floating window: type on top, the translation appears below once
/// typing pauses. The direction follows the configured language pair and can
/// be flipped for the current text.
@MainActor
final class TranslatorWindowController: NSWindowController, NSWindowDelegate {
    private let model: TranslatorModel

    init(preferences: AppPreferences, onOpenSettings: @escaping () -> Void) {
        let model = TranslatorModel(preferences: preferences)
        self.model = model
        let panel = TranslatorPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI 翻译"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 420, height: 320)
        panel.isMovableByWindowBackground = true
        super.init(window: panel)
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: TranslatorView(
            model: model,
            preferences: preferences,
            onOpenSettings: { [weak panel] in
                panel?.orderOut(nil)
                onOpenSettings()
            },
            onClose: { [weak panel] in panel?.orderOut(nil) }
        ))
        panel.setContentSize(NSSize(width: 560, height: 440))
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isVisible: Bool { window?.isVisible == true }

    /// Opens the window; non-empty `text` replaces the input and translates it.
    func show(text: String = "") {
        guard let window else { return }
        if !window.isVisible { PasteService.shared.rememberFrontmostApplication() }
        if !text.isEmpty { model.replaceInput(with: text) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    func toggle() {
        if isVisible, window?.isKeyWindow == true { window?.orderOut(nil) } else { show() }
    }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
    }

    func shutdown() { model.cancel() }
}

private final class TranslatorPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var input = "" { didSet { if input != oldValue { scheduleTranslation() } } }
    @Published private(set) var output = ""
    @Published private(set) var target: TranslationLanguage = .english
    @Published private(set) var isTranslating = false
    @Published private(set) var errorMessage: String?
    /// The user flipped the direction for the current text.
    @Published private(set) var targetOverride: TranslationLanguage?
    @Published var focusRequest = 0

    private let preferences: AppPreferences
    private let service: AITranslationService
    private let debouncer = DebouncedAction()
    private var task: Task<Void, Never>?

    init(preferences: AppPreferences, service: AITranslationService = .shared) {
        self.preferences = preferences
        self.service = service
        self.target = preferences.aiTranslation.secondaryLanguage
    }

    var settings: AITranslationSettings { preferences.aiTranslation }

    var directionTitle: String {
        let destination = targetOverride ?? (input.isEmpty ? settings.secondaryLanguage : settings.target(for: input))
        let source = destination == settings.primaryLanguage ? settings.secondaryLanguage : settings.primaryLanguage
        return "\(source.title) → \(destination.title)"
    }

    func replaceInput(with text: String) {
        targetOverride = nil
        input = String(text.prefix(TranslationQuery.maximumCharacters))
        translateNow()
    }

    func swapDirection() {
        let current = targetOverride ?? settings.target(for: input)
        targetOverride = current == settings.primaryLanguage ? settings.secondaryLanguage : settings.primaryLanguage
        translateNow()
    }

    func clear() {
        cancel()
        input = ""
        output = ""
        errorMessage = nil
        targetOverride = nil
    }

    func cancel() {
        debouncer.cancel()
        task?.cancel()
        task = nil
        isTranslating = false
    }

    private func scheduleTranslation() {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cancel()
            output = ""
            errorMessage = nil
            targetOverride = nil
            return
        }
        debouncer.schedule(after: .milliseconds(settings.liveDelayMilliseconds)) { [weak self] in
            self?.translateNow()
        }
    }

    func translateNow() {
        debouncer.cancel()
        task?.cancel()
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let settings = self.settings
        let requestedTarget = targetOverride
        isTranslating = true
        errorMessage = nil
        task = Task { [weak self, service] in
            do {
                let result = try await service.translate(text, settings: settings, target: requestedTarget)
                guard let self, !Task.isCancelled, self.input == text else { return }
                self.output = result.text
                self.target = result.target
                self.isTranslating = false
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled, self.input == text else { return }
                self.errorMessage = error.localizedDescription
                self.isTranslating = false
            }
        }
    }
}

private struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    @ObservedObject var preferences: AppPreferences
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "character.bubble").foregroundStyle(Color.accentColor)
                Text(model.directionTitle).font(.headline)
                Button { model.swapDirection() } label: { Image(systemName: "arrow.left.arrow.right") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r", modifiers: .command)
                    .help("切换翻译方向（⌘R）")
                    .disabled(model.input.isEmpty)
                Spacer()
                if model.isTranslating { ProgressView().controlSize(.small) }
                Button { onOpenSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("AI 翻译设置")
            }
            .padding(.horizontal, 16)
            .padding(.top, 30)
            .padding(.bottom, 10)

            if !preferences.aiTranslation.enabled {
                notice("AI 翻译尚未启用。在设置中选择服务商、填写 API Key 并打开开关后即可使用。",
                       button: "打开设置", action: onOpenSettings)
            }

            TextEditor(text: $model.input)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .focused($inputFocused)
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        Text("输入或粘贴要翻译的内容…")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 110)

            Divider().padding(.vertical, 10)

            ScrollView {
                Group {
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else if model.output.isEmpty {
                        Text(model.isTranslating ? "正在翻译…" : "译文会显示在这里").foregroundStyle(.tertiary)
                    } else {
                        Text(model.output).textSelection(.enabled)
                    }
                }
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22)
            }
            .frame(minHeight: 110)

            Divider()
            HStack(spacing: 12) {
                Button("清空") { model.clear(); inputFocused = true }
                    .keyboardShortcut("k", modifiers: .command)
                Spacer()
                Text("停顿 \(preferences.aiTranslation.liveDelayMilliseconds) ms 后自动翻译 · Esc 关闭")
                    .font(.caption).foregroundStyle(.secondary)
                Button("复制译文") { copyOutput() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.output.isEmpty)
                Button("粘贴到应用") { pasteOutput() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(model.output.isEmpty)
                    .help("关闭窗口并把译文粘贴到之前的应用（⇧⌘↩）")
            }
            .controlSize(.small)
            .padding(.horizontal, 16)
            .frame(height: 44)
        }
        .frame(minWidth: 420, minHeight: 320)
        .background(.regularMaterial)
        .onAppear { inputFocused = true }
        .onChange(of: model.focusRequest) { _, _ in inputFocused = true }
    }

    private func notice(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label(text, systemImage: "info.circle").font(.caption)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func copyOutput() {
        guard !model.output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.output, forType: .string)
        ToastPresenter.show("已复制译文")
    }

    private func pasteOutput() {
        guard !model.output.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.output, forType: .string)
        onClose()
        if !PasteService.shared.pasteIntoPreviousApplication() {
            PasteService.shared.reportPasteUnavailable()
        }
    }
}
