import AppKit
import Carbon
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = AppPreferences()
    private var panelController: SearchPanelController?
    private var settingsController: SettingsWindowController?
    private var snippets: SnippetManager?
    private var hotKeyManager: HotKeyManager?
    private var statusItem: NSStatusItem?
    private var pauseClipboardMenuItem: NSMenuItem?
    private var launcherMenuItem: NSMenuItem?
    private var clipboardMenuItem: NSMenuItem?
    private var lastWorkingLauncherHotKey: HotKeyDefinition?
    private var lastWorkingClipboardHotKey: HotKeyDefinition?
    private var themeCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyAppearance(preferences.theme)
        themeCancellable = preferences.$theme
            .removeDuplicates()
            .sink { [weak self] in self?.applyAppearance($0) }

        let clipboard = ClipboardHistoryManager(preferences: preferences)
        let snippets = SnippetManager()
        let recentDocuments = RecentDocumentsManager()
        let settingsController = SettingsWindowController(
            preferences: preferences,
            clipboard: clipboard,
            snippets: snippets,
            recentDocuments: recentDocuments
        )
        let panelController = SearchPanelController(
            preferences: preferences,
            clipboard: clipboard,
            snippets: snippets,
            recentDocuments: recentDocuments,
            onOpenSettings: { [weak settingsController] in settingsController?.show() }
        )
        let hotKeyManager = HotKeyManager()
        self.panelController = panelController
        self.settingsController = settingsController
        self.snippets = snippets
        self.hotKeyManager = hotKeyManager
        preferences.hotKeysDidChange = { [weak self] in self?.configureHotKeys() }
        preferences.menuBarVisibilityDidChange = { [weak self] in self?.updateStatusItemVisibility() }
        preferences.clearUsageLearningHandler = { [weak panelController] in
            panelController?.clearUsageLearning()
        }
        configureHotKeys()
        configureStatusItem()
        updateStatusItemVisibility()

        panelController.showLauncher()
    }

    private func configureHotKeys() {
        guard let hotKeyManager else { return }
        hotKeyManager.removeAll()
        preferences.hotKeyError = nil

        if !registerHotKeys(
            launcher: preferences.launcherHotKey,
            clipboard: preferences.clipboardHotKey
        ) {
            hotKeyManager.removeAll()
            let hadPreviousHotKeys = lastWorkingLauncherHotKey != nil
            let launcher = lastWorkingLauncherHotKey ?? HotKeyDefinition(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey) | UInt32(optionKey)
            )
            let clipboard = lastWorkingClipboardHotKey ?? HotKeyDefinition(
                keyCode: UInt32(kVK_ANSI_C),
                modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
            )
            if registerHotKeys(launcher: launcher, clipboard: clipboard) {
                preferences.restoreHotKeysWithoutNotifying(
                    launcher: launcher,
                    clipboard: clipboard
                )
                lastWorkingLauncherHotKey = launcher
                lastWorkingClipboardHotKey = clipboard
                preferences.hotKeyError = hadPreviousHotKeys
                    ? "新快捷键已被占用，已恢复上一个可用组合。"
                    : "默认快捷键被占用，已启用备用组合。"
            } else {
                hotKeyManager.removeAll()
                preferences.hotKeyError = "快捷键已被 macOS 或其他应用占用，请在启动器中按 Command+, 打开设置后更换。"
            }
        } else {
            lastWorkingLauncherHotKey = preferences.launcherHotKey
            lastWorkingClipboardHotKey = preferences.clipboardHotKey
        }
        launcherMenuItem?.title = "显示启动器（\(preferences.launcherHotKey.displayString)）"
        clipboardMenuItem?.title = "剪贴板历史（\(preferences.clipboardHotKey.displayString)）"
    }

    private func registerHotKeys(
        launcher: HotKeyDefinition,
        clipboard: HotKeyDefinition
    ) -> Bool {
        guard let hotKeyManager else { return false }
        let launcherRegistered = hotKeyManager.register(
            id: 1,
            keyCode: launcher.keyCode,
            modifiers: launcher.modifiers
        ) { [weak panelController] in
            panelController?.toggleLauncher()
        }
        let clipboardRegistered = !preferences.clipboardEnabled || hotKeyManager.register(
            id: 2,
            keyCode: clipboard.keyCode,
            modifiers: clipboard.modifiers
        ) { [weak panelController] in
            panelController?.toggleClipboard()
        }
        return launcherRegistered && clipboardRegistered
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "command.circle", accessibilityDescription: "YTools")
        let menu = NSMenu()
        launcherMenuItem = menu.addItem(
            withTitle: "显示启动器（\(preferences.launcherHotKey.displayString)）",
            action: #selector(showLauncher),
            keyEquivalent: ""
        )
        clipboardMenuItem = menu.addItem(
            withTitle: "剪贴板历史（\(preferences.clipboardHotKey.displayString)）",
            action: #selector(showClipboard),
            keyEquivalent: ""
        )
        let pauseItem = menu.addItem(
            withTitle: "暂停剪贴板记录",
            action: #selector(toggleClipboardPause),
            keyEquivalent: ""
        )
        pauseClipboardMenuItem = pauseItem
        menu.addItem(.separator())
        let privacyItem = menu.addItem(withTitle: "本机模式 · 无网络模块", action: nil, keyEquivalent: "")
        privacyItem.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 YTools", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item
    }

    private func updateStatusItemVisibility() {
        statusItem?.isVisible = preferences.showMenuBarIcon
    }

    @objc private func showLauncher() { panelController?.showLauncher() }
    @objc private func showClipboard() { panelController?.showClipboard() }
    @objc private func showSettings() { settingsController?.show() }
    @objc private func toggleClipboardPause() {
        preferences.clipboardPaused.toggle()
        pauseClipboardMenuItem?.state = preferences.clipboardPaused ? .on : .off
        pauseClipboardMenuItem?.title = preferences.clipboardPaused
            ? "继续剪贴板记录"
            : "暂停剪贴板记录"
    }
    @objc private func quit() { NSApp.terminate(nil) }

    func applicationWillTerminate(_ notification: Notification) {
        snippets?.flushPendingChanges()
    }

    private func applyAppearance(_ theme: AppTheme) {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.windows.forEach {
            $0.contentView?.needsDisplay = true
            $0.invalidateShadow()
        }
    }
}
