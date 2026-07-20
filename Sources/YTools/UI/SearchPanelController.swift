import AppKit
import Combine
import SwiftUI
import YToolsCore

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class SearchPanelController: NSWindowController, NSWindowDelegate {
    private let state = PanelState()
    private let launcher: LauncherModel
    private let preferences: AppPreferences
    private let clipboard: ClipboardHistoryManager
    private let snippets: SnippetManager
    private let onOpenSettings: () -> Void
    private let largeTypeController: LargeTypeWindowController
    private let commandRouter = PanelCommandRouter()
    private let positionSaveDebouncer = DebouncedAction()
    private var keyMonitor: Any?
    private var shiftPreviewTimer: Timer?
    private var isApplyingPanelPosition = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        preferences: AppPreferences,
        clipboard: ClipboardHistoryManager,
        snippets: SnippetManager,
        recentDocuments: RecentDocumentsManager,
        onOpenSettings: @escaping () -> Void
    ) {
        let largeTypeController = LargeTypeWindowController()
        self.largeTypeController = largeTypeController
        self.preferences = preferences
        self.clipboard = clipboard
        self.snippets = snippets
        self.onOpenSettings = onOpenSettings
        self.launcher = LauncherModel(
            preferences: preferences,
            snippets: snippets,
            recentDocuments: recentDocuments,
            onShowLargeType: { [weak largeTypeController] text in largeTypeController?.show(text: text) },
            onOpenSettings: onOpenSettings
        )
        let panel = LauncherPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: preferences.panelWidth,
                height: DesignTokens.panelMaximumHeight
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        super.init(window: panel)
        panel.delegate = self
        panel.contentViewController = NSHostingController(
            rootView: PanelRootView(
                state: state,
                launcher: launcher,
                clipboard: clipboard,
                preferences: preferences,
                onHide: { [weak self] in self?.hide() }
            )
            .ignoresSafeArea()
        )

        observePanelContent()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            guard self.window?.isKeyWindow == true else { return event }
            if event.type == .flagsChanged {
                self.handleModifierChange(event)
                return event
            }
            if self.handleTextEditingShortcut(event) { return nil }
            if [36, 123, 124, 125, 126].contains(Int(event.keyCode)),
               let textView = self.window?.firstResponder as? NSTextView,
               textView.hasMarkedText() {
                return event
            }
            self.shiftPreviewTimer?.invalidate()
            guard let command = self.commandRouter.command(
                for: PanelKeyEvent(
                    keyCode: event.keyCode,
                    modifiers: self.panelModifiers(from: event.modifierFlags)
                ),
                mode: self.state.mode == .launcher ? .launcher : .clipboard
            ) else { return event }
            return self.execute(command) ? nil : event
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        shiftPreviewTimer?.invalidate()
        positionSaveDebouncer.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    func toggleLauncher() {
        toggle(mode: .launcher)
    }

    func toggleClipboard() {
        toggle(mode: .clipboard)
    }

    func showLauncher() {
        state.mode = .launcher
        show()
    }

    func showClipboard() {
        state.mode = .clipboard
        clipboard.prepareForPresentation()
        show()
    }

    private func toggle(mode: PanelMode) {
        if window?.isVisible == true, state.mode == mode {
            hide()
            return
        }
        state.mode = mode
        if mode == .clipboard { clipboard.prepareForPresentation() }
        show()
    }

    private func show() {
        guard let window else { return }
        adjustPanelSize(animated: false)
        position(window)
        NSApp.activate(ignoringOtherApps: true)
        if KeyboardInputSourceManager.select(preferences.forcedKeyboardInputSourceID) {
            preferences.keyboardInputSourceError = nil
        } else {
            preferences.keyboardInputSourceError = "所选输入源当前不可用，已保留系统当前输入源。"
        }
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        shiftPreviewTimer?.invalidate()
        launcher.endPreviewSession()
        window?.orderOut(nil)
    }

    func clearUsageLearning() {
        launcher.clearUsageLearning()
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    func windowDidMove(_ notification: Notification) {
        guard !isApplyingPanelPosition, let window, window.isVisible else { return }
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        guard let screen = window.screen ?? screen(containing: topLeft) else { return }
        let visibleFrame = screen.visibleFrame
        let screenIdentifier = identifier(for: screen)
        positionSaveDebouncer.schedule(after: .milliseconds(250)) { [weak self] in
            self?.preferences.savePanelPosition(
                topLeft: topLeft,
                visibleFrame: visibleFrame,
                screenIdentifier: screenIdentifier
            )
        }
    }

    private func moveSelection(by offset: Int) {
        switch state.mode {
        case .launcher:
            launcher.moveSelection(by: offset)
        case .clipboard:
            clipboard.moveSelection(by: offset)
        }
    }

    private func observePanelContent() {
        let layoutPreferences = Publishers.CombineLatest3(
            preferences.$compactResults,
            preferences.$panelWidth,
            preferences.$launcherAppearanceStyle
        )
        .removeDuplicates { left, right in
            left.0 == right.0 && left.1 == right.1 && left.2 == right.2
        }
        .map { _ in () }
        .eraseToAnyPublisher()

        Publishers.MergeMany([
            launcher.layoutInvalidations,
            clipboard.layoutInvalidations,
            state.$mode.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            layoutPreferences
        ])
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.adjustPanelSize(animated: true) }
        .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, let window = self.window, window.isVisible else { return }
                self.position(window)
            }
            .store(in: &cancellables)
    }

    private func adjustPanelSize(animated: Bool) {
        guard let window else { return }
        let style = preferences.launcherAppearanceStyle
        let count: Int
        switch state.mode {
        case .launcher:
            // A pending debounced query keeps only the input row visible. The
            // panel expands once, when the final query publishes its results.
            if launcher.isSearchPending {
                setPanelContentHeight(style.headerHeight, window: window, animated: animated)
                return
            }
            count = launcher.visibleItemCount
        case .clipboard:
            count = clipboard.filteredItems.count
        }
        let rowHeight = preferences.compactResults
            ? DesignTokens.compactRowHeight
            : DesignTokens.comfortableRowHeight
        if state.mode == .launcher,
           style.collapsesWhenIdle,
           launcher.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !launcher.isShowingActions {
            setPanelContentHeight(style.headerHeight, window: window, animated: animated)
            return
        }
        let bodyHeight = count == 0
            ? (state.mode == .launcher ? style.emptyBodyHeight : DesignTokens.emptyBodyHeight)
            : min(CGFloat(count), 6) * rowHeight
        let headerHeight = state.mode == .launcher ? style.headerHeight : DesignTokens.headerHeight
        let footerHeight = state.mode == .launcher && !style.showsFooter
            ? 0
            : DesignTokens.footerHeight
        let contentHeight = min(
            DesignTokens.panelMaximumHeight,
            max(
                headerHeight + bodyHeight + footerHeight,
                headerHeight
            )
        )
        setPanelContentHeight(contentHeight, window: window, animated: animated)
    }

    private func setPanelContentHeight(_ contentHeight: CGFloat, window: NSWindow, animated: Bool) {
        // This is a borderless, key-capable panel, so the visible frame and
        // SwiftUI surface share the same dimensions without title-bar minima.
        var newFrame = window.frame
        newFrame.size = NSSize(width: preferences.panelWidth, height: contentHeight)
        newFrame.origin.y = window.frame.maxY - contentHeight
        // Selection, preview and pending-state publications do not necessarily
        // change panel geometry. Avoid asking AppKit to animate an identical
        // frame for every high-frequency state update.
        guard abs(newFrame.width - window.frame.width) >= 0.5
                || abs(newFrame.height - window.frame.height) >= 0.5 else { return }
        let duration = preferences.resultExpansionDuration
        let shouldAnimate = animated
            && window.isVisible
            && duration > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard shouldAnimate else {
            window.setFrame(newFrame, display: true, animate: false)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.allowsImplicitAnimation = true
            window.animator().setFrame(newFrame, display: true)
        }
    }

    private func handleModifierChange(_ event: NSEvent) {
        guard state.mode == .launcher else { return }
        if event.modifierFlags.contains(.shift) {
            shiftPreviewTimer?.invalidate()
            shiftPreviewTimer = Timer.scheduledTimer(
                timeInterval: 0.25,
                target: self,
                selector: #selector(showMomentaryPreview),
                userInfo: nil,
                repeats: false
            )
        } else {
            shiftPreviewTimer?.invalidate()
            launcher.endMomentaryPreview()
        }
    }

    @objc private func showMomentaryPreview() {
        launcher.beginMomentaryPreview()
    }

    private func panelModifiers(from flags: NSEvent.ModifierFlags) -> PanelKeyModifiers {
        var result: PanelKeyModifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }

    /// Borderless accessory panels do not always inherit the application's
    /// standard Edit menu key equivalents. Forward Select All directly to the
    /// active SwiftUI field editor while leaving every other shortcut on the
    /// normal responder chain or panel command router.
    private func handleTextEditingShortcut(_ event: NSEvent) -> Bool {
        guard event.keyCode == 0,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
              let textView = window?.firstResponder as? NSTextView else { return false }
        textView.selectAll(nil)
        return true
    }

    private func execute(_ command: PanelCommand) -> Bool {
        switch command {
        case .activateSelected:
            switch state.mode {
            case .launcher:
                guard launcher.activateSelected() else { return false }
            case .clipboard:
                guard clipboard.copySelected() else { return false }
            }
            hide()
        case let .activateResult(index):
            guard launcher.activateResult(at: index) else { return false }
            hide()
        case let .addSelectedToBuffer(moveToNext):
            return launcher.addSelectedToBuffer(moveToNext: moveToNext)
        case .removeLastBufferedItem:
            return launcher.removeLastBufferedItem()
        case .showFileBufferActions:
            return launcher.showFileBufferActions()
        case .clearFileBuffer:
            launcher.clearFileBuffer()
        case .escape:
            if state.mode == .launcher, launcher.dismissSecondaryView() { return true }
            if state.mode == .launcher, launcher.clearQuery() { return true }
            if state.mode == .clipboard, clipboard.clearQuery() { return true }
            hide()
        case let .moveSelection(offset):
            moveSelection(by: offset)
        case .showActions:
            return launcher.showActionsForSelected()
        case .navigateBack:
            return launcher.dismissSecondaryView() || launcher.navigateToParent()
        case .deleteClipboardItem:
            clipboard.deleteSelected()
        case .saveClipboardAsSnippet:
            guard let text = clipboard.selectedText, snippets.save(text: text) else { return false }
            NSSound(named: "Glass")?.play()
        case .togglePreview:
            launcher.togglePreview()
        case .showLargeType:
            guard let text = launcher.selectedLargeTypeText else { return false }
            hide()
            largeTypeController.show(text: text)
        case .revealSelected:
            guard launcher.revealSelected() else { return false }
            hide()
        case .openSettings:
            hide()
            onOpenSettings()
        }
        return true
    }

    private func position(_ window: NSWindow) {
        positionSaveDebouncer.cancel()
        let preferredScreen: NSScreen?
        switch preferences.screenPreference {
        case .main:
            preferredScreen = NSScreen.main ?? NSScreen.screens.first
        case .mouse:
            let point = NSEvent.mouseLocation
            preferredScreen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
        }
        let savedTopLeft = preferences.savedPanelTopLeft
        let savedPlacement = preferences.savedPanelPlacement
        let savedScreen = savedPlacement?.screenIdentifier.flatMap { identifier in
            NSScreen.screens.first { self.identifier(for: $0) == identifier }
        }
        let legacyScreen: NSScreen?
        if savedPlacement == nil, let savedTopLeft {
            legacyScreen = screen(containing: savedTopLeft)
        } else {
            legacyScreen = nil
        }
        let screen = savedScreen ?? legacyScreen ?? preferredScreen
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let origin: NSPoint
        if let savedPlacement {
            let relativeTopLeft = CGPoint(
                x: savedPlacement.relativePosition.resolvedLeft(
                    visibleOriginX: visibleFrame.origin.x,
                    visibleWidth: visibleFrame.size.width
                ),
                y: savedPlacement.relativePosition.resolvedTop(
                    visibleOriginY: visibleFrame.origin.y,
                    visibleHeight: visibleFrame.size.height
                )
            )
            origin = clampedOrigin(
                for: relativeTopLeft,
                visibleFrame: visibleFrame,
                windowSize: window.frame.size
            )
        } else if let savedTopLeft {
            origin = clampedOrigin(
                for: savedTopLeft,
                visibleFrame: visibleFrame,
                windowSize: window.frame.size
            )
            let screenIdentifier = screen.flatMap { identifier(for: $0) }
            preferences.savePanelPosition(
                topLeft: savedTopLeft,
                visibleFrame: visibleFrame,
                screenIdentifier: screenIdentifier
            )
        } else {
            let x = visibleFrame.midX - window.frame.width / 2
            let y: CGFloat
            switch preferences.panelPosition {
            case .upper:
                y = visibleFrame.maxY - window.frame.height - 110
            case .center:
                y = visibleFrame.midY - window.frame.height / 2
            }
            origin = NSPoint(x: x, y: y)
        }
        isApplyingPanelPosition = true
        window.setFrameOrigin(origin)
        isApplyingPanelPosition = false
    }

    private func clampedOrigin(
        for topLeft: CGPoint,
        visibleFrame: CGRect,
        windowSize: CGSize
    ) -> CGPoint {
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let minimumTop = min(visibleFrame.maxY, visibleFrame.minY + windowSize.height)
        let x = min(max(topLeft.x, visibleFrame.minX), maximumX)
        let top = min(max(topLeft.y, minimumTop), visibleFrame.maxY)
        return CGPoint(x: x, y: top - windowSize.height)
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func identifier(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber,
              let unmanagedUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value) else { return nil }
        return CFUUIDCreateString(nil, unmanagedUUID.takeRetainedValue()) as String
    }
}
