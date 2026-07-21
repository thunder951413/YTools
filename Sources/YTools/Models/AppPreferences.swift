import Carbon
import Combine
import Foundation
import YToolsCore

struct HotKeyDefinition: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let launcherDefault = HotKeyDefinition(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey)
    )
    static let clipboardDefault = HotKeyDefinition(
        keyCode: UInt32(kVK_ANSI_V),
        modifiers: UInt32(shiftKey) | UInt32(cmdKey)
    )

    var displayString: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += keyName
        return value
    }

    private var keyName: String {
        let names: [UInt32: String] = [
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Return): "↩",
            UInt32(kVK_Tab): "⇥",
            UInt32(kVK_Escape): "⎋",
            UInt32(kVK_Delete): "⌫",
            UInt32(kVK_UpArrow): "↑",
            UInt32(kVK_DownArrow): "↓",
            UInt32(kVK_LeftArrow): "←",
            UInt32(kVK_RightArrow): "→"
        ]
        if let known = names[keyCode] { return known }

        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }
        let data = unsafeBitCast(dataPointer, to: CFData.self)
        guard let layout = CFDataGetBytePtr(data) else { return "Key \(keyCode)" }

        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            UnsafePointer<UCKeyboardLayout>(OpaquePointer(layout)),
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }
}

enum AppAccentColor: String, Codable, CaseIterable, Identifiable {
    case blue
    case purple
    case green
    case orange

    var id: String { rawValue }
    var title: String {
        switch self {
        case .blue: "蓝色"
        case .purple: "紫色"
        case .green: "绿色"
        case .orange: "橙色"
        }
    }
}

enum LauncherAppearanceStyle: String, Codable, CaseIterable, Identifiable {
    case minimal
    case classic
    case modern
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal: "极简"
        case .classic: "经典"
        case .modern: "现代"
        case .glass: "玻璃"
        }
    }

    var detail: String {
        switch self {
        case .minimal: "默认；空闲时只显示输入框"
        case .classic: "更实的背景与传统结果列表"
        case .modern: "完整状态提示和操作栏"
        case .glass: "更轻的半透明系统材质"
        }
    }
}

enum PanelPosition: String, Codable, CaseIterable, Identifiable {
    case upper
    case center

    var id: String { rawValue }
    var title: String { self == .upper ? "屏幕上方" : "屏幕中央" }
}

enum ScreenPreference: String, Codable, CaseIterable, Identifiable {
    case main
    case mouse

    var id: String { rawValue }
    var title: String { self == .main ? "主显示器" : "鼠标所在显示器" }
}

struct SavedPanelPlacement: Equatable, Sendable {
    let relativePosition: RelativePanelPlacement
    let screenIdentifier: String?
}

enum FileNavigationSort: String, Codable, CaseIterable, Identifiable, Sendable {
    case name
    case created
    case modified

    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: "名称"
        case .created: "创建时间"
        case .modified: "修改时间"
        }
    }
}

enum SearchContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case applications
    case files
    case calculations
    case dictionary
    case systemTools
    case snippets
    case recentDocuments
    case textTools

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "应用程序"
        case .files: "本地文件"
        case .calculations: "计算与单位换算"
        case .dictionary: "词典与拼写"
        case .systemTools: "系统工具与设置"
        case .snippets: "文本片段"
        case .recentDocuments: "最近文档"
        case .textTools: "文本统计工具"
        }
    }

    var detail: String {
        switch self {
        case .applications: "扫描本机应用目录并显示可启动应用"
        case .files: "Spotlight 文件、Finder 标签结果以及 /、~ 目录导航"
        case .calculations: "表达式计算、常量、函数和单位转换"
        case .dictionary: "系统词典释义、拼写检查和建议"
        case .systemTools: "可配置系统命令、废纸篓、屏保、显示器休眠和系统设置入口"
        case .snippets: "搜索保存在本机的文本片段"
        case .recentDocuments: "搜索由 YTools 记录的最近打开项目"
        case .textTools: "统计剪贴板文字的字数、行数等信息"
        }
    }

    var icon: String {
        switch self {
        case .applications: "app.dashed"
        case .files: "doc.text.magnifyingglass"
        case .calculations: "function"
        case .dictionary: "character.book.closed"
        case .systemTools: "gearshape.2"
        case .snippets: "text.quote"
        case .recentDocuments: "clock.arrow.circlepath"
        case .textTools: "textformat.123"
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet { configureLaunchAtLogin() }
    }
    @Published var launcherHotKey: HotKeyDefinition { didSet { saveHotKey(launcherHotKey, key: Keys.launcherHotKey); notifyHotKeyChange() } }
    @Published var clipboardHotKey: HotKeyDefinition { didSet { saveHotKey(clipboardHotKey, key: Keys.clipboardHotKey); notifyHotKeyChange() } }
    @Published var theme: AppTheme { didSet { defaults.set(theme.rawValue, forKey: Keys.theme) } }
    @Published var accentColor: AppAccentColor { didSet { defaults.set(accentColor.rawValue, forKey: Keys.accentColor) } }
    @Published var launcherAppearanceStyle: LauncherAppearanceStyle { didSet { defaults.set(launcherAppearanceStyle.rawValue, forKey: Keys.launcherAppearanceStyle) } }
    @Published var panelPosition: PanelPosition {
        didSet {
            defaults.set(panelPosition.rawValue, forKey: Keys.panelPosition)
            clearSavedPanelPosition()
        }
    }
    @Published var screenPreference: ScreenPreference {
        didSet {
            defaults.set(screenPreference.rawValue, forKey: Keys.screenPreference)
            clearSavedPanelPosition()
        }
    }
    @Published private(set) var savedPanelTopLeft: CGPoint?
    @Published private(set) var savedPanelPlacement: SavedPanelPlacement?
    @Published var forcedKeyboardInputSourceID: String { didSet { defaults.set(forcedKeyboardInputSourceID, forKey: Keys.forcedKeyboardInputSourceID) } }
    @Published var showMenuBarIcon: Bool {
        didSet {
            defaults.set(showMenuBarIcon, forKey: Keys.showMenuBarIcon)
            menuBarVisibilityDidChange?()
        }
    }
    @Published var compactResults: Bool { didSet { defaults.set(compactResults, forKey: Keys.compactResults) } }
    @Published var panelWidth: Double { didSet { defaults.set(panelWidth, forKey: Keys.panelWidth) } }
    @Published var panelCornerRadius: Double { didSet { defaults.set(panelCornerRadius, forKey: Keys.panelCornerRadius) } }
    @Published var showSubtitles: Bool { didSet { defaults.set(showSubtitles, forKey: Keys.showSubtitles) } }
    @Published var showNumberShortcuts: Bool { didSet { defaults.set(showNumberShortcuts, forKey: Keys.showNumberShortcuts) } }
    @Published var searchInputDelay: Double { didSet { defaults.set(searchInputDelay, forKey: Keys.searchInputDelay) } }
    @Published var previewSelectionDelay: Double { didSet { defaults.set(previewSelectionDelay, forKey: Keys.previewSelectionDelay) } }
    @Published var resultExpansionDuration: Double {
        didSet { defaults.set(resultExpansionDuration, forKey: Keys.resultExpansionDuration) }
    }
    @Published var enabledSearchContentTypes: Set<SearchContentType> {
        didSet {
            defaults.set(
                enabledSearchContentTypes.map(\.rawValue).sorted(),
                forKey: Keys.enabledSearchContentTypes
            )
        }
    }
    @Published var enabledSystemCommands: Set<SystemCommandID> {
        didSet {
            defaults.set(enabledSystemCommands.map(\.rawValue).sorted(), forKey: Keys.enabledSystemCommands)
        }
    }
    @Published var systemCommandKeywords: [SystemCommandID: String] {
        didSet {
            defaults.set(
                Dictionary(uniqueKeysWithValues: systemCommandKeywords.map { ($0.key.rawValue, $0.value) }),
                forKey: Keys.systemCommandKeywords
            )
        }
    }
    @Published var includeFilesInDefaultResults: Bool { didSet { defaults.set(includeFilesInDefaultResults, forKey: Keys.includeFilesInDefaultResults) } }
    @Published var includeAutomaticDictionary: Bool { didSet { defaults.set(includeAutomaticDictionary, forKey: Keys.includeAutomaticDictionary) } }
    @Published var maximumSearchResults: Int { didSet { defaults.set(maximumSearchResults, forKey: Keys.maximumSearchResults) } }
    @Published var searchScopePaths: [String] { didSet { defaults.set(searchScopePaths, forKey: Keys.searchScopePaths) } }
    @Published var applicationAliases: [String: String] {
        didSet { defaults.set(applicationAliases, forKey: Keys.applicationAliases) }
    }
    @Published var fileNavigationShowsHiddenFiles: Bool { didSet { defaults.set(fileNavigationShowsHiddenFiles, forKey: Keys.fileNavigationShowsHiddenFiles) } }
    @Published var fileNavigationSort: FileNavigationSort { didSet { defaults.set(fileNavigationSort.rawValue, forKey: Keys.fileNavigationSort) } }
    @Published var fileNavigationSortAscending: Bool { didSet { defaults.set(fileNavigationSortAscending, forKey: Keys.fileNavigationSortAscending) } }
    @Published var fileNavigationFoldersFirst: Bool { didSet { defaults.set(fileNavigationFoldersFirst, forKey: Keys.fileNavigationFoldersFirst) } }
    @Published var clipboardEnabled: Bool { didSet { defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled); notifyHotKeyChange() } }
    @Published var clipboardPaused: Bool { didSet { defaults.set(clipboardPaused, forKey: Keys.clipboardPaused) } }
    @Published var clipboardRetentionDays: Int { didSet { defaults.set(clipboardRetentionDays, forKey: Keys.clipboardRetentionDays) } }
    @Published var clipboardMaximumItems: Int { didSet { defaults.set(clipboardMaximumItems, forKey: Keys.clipboardMaximumItems) } }
    @Published var clipboardMaximumTextCharacters: Int { didSet { defaults.set(clipboardMaximumTextCharacters, forKey: Keys.clipboardMaximumTextCharacters) } }
    @Published var clipboardStoreImages: Bool { didSet { defaults.set(clipboardStoreImages, forKey: Keys.clipboardStoreImages) } }
    @Published var clipboardIgnoredBundleIDs: [String] { didSet { defaults.set(clipboardIgnoredBundleIDs, forKey: Keys.clipboardIgnoredBundleIDs) } }
    @Published var hotKeyError: String?
    @Published var launchAtLoginError: String?
    @Published var keyboardInputSourceError: String?

    var hotKeysDidChange: (() -> Void)?
    var menuBarVisibilityDidChange: (() -> Void)?
    var clearUsageLearningHandler: (() -> Void)?
    private let defaults: UserDefaults
    private let launchAtLoginService: any LaunchAtLoginManaging
    private var suppressHotKeyNotification = false
    private var suppressLaunchAtLoginUpdate = false

    init(
        defaults: UserDefaults = .standard,
        launchAtLoginService: any LaunchAtLoginManaging = LaunchAtLoginService()
    ) {
        Self.migrateIfNeeded(defaults)
        self.defaults = defaults
        self.launchAtLoginService = launchAtLoginService
        self.launchAtLogin = launchAtLoginService.isEnabled
        self.launcherHotKey = Self.loadHotKey(defaults, key: Keys.launcherHotKey) ?? .launcherDefault
        self.clipboardHotKey = Self.loadHotKey(defaults, key: Keys.clipboardHotKey) ?? .clipboardDefault
        self.theme = AppTheme(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .system
        self.accentColor = AppAccentColor(rawValue: defaults.string(forKey: Keys.accentColor) ?? "") ?? .blue
        self.launcherAppearanceStyle = LauncherAppearanceStyle(
            rawValue: defaults.string(forKey: Keys.launcherAppearanceStyle) ?? ""
        ) ?? .minimal
        self.panelPosition = PanelPosition(rawValue: defaults.string(forKey: Keys.panelPosition) ?? "") ?? .upper
        self.screenPreference = ScreenPreference(rawValue: defaults.string(forKey: Keys.screenPreference) ?? "") ?? .main
        self.savedPanelTopLeft = Self.loadPanelTopLeft(defaults)
        self.savedPanelPlacement = Self.loadPanelPlacement(defaults)
        self.forcedKeyboardInputSourceID = defaults.string(forKey: Keys.forcedKeyboardInputSourceID) ?? ""
        self.showMenuBarIcon = defaults.object(forKey: Keys.showMenuBarIcon) as? Bool ?? true
        self.compactResults = defaults.object(forKey: Keys.compactResults) as? Bool ?? false
        self.panelWidth = min(max(defaults.object(forKey: Keys.panelWidth) as? Double ?? 720, 640), 960)
        self.panelCornerRadius = min(max(defaults.object(forKey: Keys.panelCornerRadius) as? Double ?? 14, 10), 20)
        self.showSubtitles = defaults.object(forKey: Keys.showSubtitles) as? Bool ?? true
        self.showNumberShortcuts = defaults.object(forKey: Keys.showNumberShortcuts) as? Bool ?? true
        self.searchInputDelay = min(
            max(defaults.object(forKey: Keys.searchInputDelay) as? Double ?? 0.15, 0.05),
            0.4
        )
        self.previewSelectionDelay = min(
            max(defaults.object(forKey: Keys.previewSelectionDelay) as? Double ?? 0.3, 0),
            0.8
        )
        self.resultExpansionDuration = min(
            max(defaults.object(forKey: Keys.resultExpansionDuration) as? Double ?? 0.15, 0),
            0.4
        )
        if defaults.object(forKey: Keys.enabledSearchContentTypes) == nil {
            self.enabledSearchContentTypes = Set(SearchContentType.allCases)
        } else {
            self.enabledSearchContentTypes = Set(
                (defaults.stringArray(forKey: Keys.enabledSearchContentTypes) ?? [])
                    .compactMap(SearchContentType.init(rawValue:))
            )
        }
        if defaults.object(forKey: Keys.enabledSystemCommands) == nil {
            self.enabledSystemCommands = Set(SystemCommandID.allCases)
        } else {
            self.enabledSystemCommands = Set(
                (defaults.stringArray(forKey: Keys.enabledSystemCommands) ?? [])
                    .compactMap(SystemCommandID.init(rawValue:))
            )
        }
        let storedSystemKeywords = defaults.dictionary(forKey: Keys.systemCommandKeywords) as? [String: String] ?? [:]
        self.systemCommandKeywords = Dictionary(uniqueKeysWithValues: SystemCommandID.allCases.map { command in
            (command, storedSystemKeywords[command.rawValue] ?? command.defaultKeyword)
        })
        self.includeFilesInDefaultResults = defaults.object(forKey: Keys.includeFilesInDefaultResults) as? Bool ?? true
        self.includeAutomaticDictionary = defaults.object(forKey: Keys.includeAutomaticDictionary) as? Bool ?? true
        self.maximumSearchResults = min(
            max(defaults.object(forKey: Keys.maximumSearchResults) as? Int ?? 8, 3),
            20
        )
        self.searchScopePaths = Self.validSearchScopes(defaults.stringArray(forKey: Keys.searchScopePaths) ?? [])
        self.applicationAliases = Self.validApplicationAliases(
            defaults.dictionary(forKey: Keys.applicationAliases) as? [String: String] ?? [:]
        )
        self.fileNavigationShowsHiddenFiles = defaults.object(forKey: Keys.fileNavigationShowsHiddenFiles) as? Bool ?? false
        self.fileNavigationSort = FileNavigationSort(rawValue: defaults.string(forKey: Keys.fileNavigationSort) ?? "") ?? .name
        self.fileNavigationSortAscending = defaults.object(forKey: Keys.fileNavigationSortAscending) as? Bool ?? true
        self.fileNavigationFoldersFirst = defaults.object(forKey: Keys.fileNavigationFoldersFirst) as? Bool ?? true
        self.clipboardEnabled = defaults.object(forKey: Keys.clipboardEnabled) as? Bool ?? true
        self.clipboardPaused = defaults.object(forKey: Keys.clipboardPaused) as? Bool ?? false
        let retention = defaults.object(forKey: Keys.clipboardRetentionDays) as? Int ?? 7
        self.clipboardRetentionDays = [1, 7, 30, 90].contains(retention) ? retention : 7
        let maximumItems = defaults.object(forKey: Keys.clipboardMaximumItems) as? Int ?? 300
        self.clipboardMaximumItems = maximumItems == 0 ? 0 : min(max(maximumItems, 50), 5_000)
        self.clipboardMaximumTextCharacters = min(
            max(defaults.object(forKey: Keys.clipboardMaximumTextCharacters) as? Int ?? 1_000, 100),
            10_000
        )
        self.clipboardStoreImages = defaults.object(forKey: Keys.clipboardStoreImages) as? Bool ?? false
        self.clipboardIgnoredBundleIDs = Array(Set(
            (defaults.stringArray(forKey: Keys.clipboardIgnoredBundleIDs) ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )).sorted()
    }

    func restoreDefaults() {
        launchAtLogin = false
        launcherHotKey = .launcherDefault
        clipboardHotKey = .clipboardDefault
        theme = .system
        accentColor = .blue
        launcherAppearanceStyle = .minimal
        panelPosition = .upper
        screenPreference = .main
        forcedKeyboardInputSourceID = ""
        showMenuBarIcon = true
        compactResults = false
        panelWidth = 720
        panelCornerRadius = 14
        showSubtitles = true
        showNumberShortcuts = true
        searchInputDelay = 0.15
        previewSelectionDelay = 0.3
        resultExpansionDuration = 0.15
        enabledSearchContentTypes = Set(SearchContentType.allCases)
        enabledSystemCommands = Set(SystemCommandID.allCases)
        systemCommandKeywords = Dictionary(uniqueKeysWithValues: SystemCommandID.allCases.map {
            ($0, $0.defaultKeyword)
        })
        includeFilesInDefaultResults = true
        includeAutomaticDictionary = true
        maximumSearchResults = 8
        searchScopePaths = []
        fileNavigationShowsHiddenFiles = false
        fileNavigationSort = .name
        fileNavigationSortAscending = true
        fileNavigationFoldersFirst = true
        clipboardEnabled = true
        clipboardPaused = false
        clipboardRetentionDays = 7
        clipboardMaximumItems = 300
        clipboardMaximumTextCharacters = 1_000
        clipboardStoreImages = false
        clipboardIgnoredBundleIDs = []
    }

    func savePanelPosition(
        topLeft point: CGPoint,
        visibleFrame: CGRect,
        screenIdentifier: String?
    ) {
        guard let relativePosition = RelativePanelPlacement(
            left: point.x,
            top: point.y,
            visibleOriginX: visibleFrame.origin.x,
            visibleOriginY: visibleFrame.origin.y,
            visibleWidth: visibleFrame.size.width,
            visibleHeight: visibleFrame.size.height
        ) else { return }
        let placement = SavedPanelPlacement(
            relativePosition: relativePosition,
            screenIdentifier: screenIdentifier
        )
        savedPanelTopLeft = point
        savedPanelPlacement = placement
        defaults.set([Double(point.x), Double(point.y)], forKey: Keys.savedPanelTopLeft)
        defaults.set(
            [
                relativePosition.horizontalFraction,
                relativePosition.topFraction,
                relativePosition.sourceVisibleWidth,
                relativePosition.sourceVisibleHeight
            ],
            forKey: Keys.savedPanelPlacement
        )
        if let screenIdentifier {
            defaults.set(screenIdentifier, forKey: Keys.savedPanelScreenIdentifier)
        } else {
            defaults.removeObject(forKey: Keys.savedPanelScreenIdentifier)
        }
    }

    func clearSavedPanelPosition() {
        savedPanelTopLeft = nil
        savedPanelPlacement = nil
        defaults.removeObject(forKey: Keys.savedPanelTopLeft)
        defaults.removeObject(forKey: Keys.savedPanelPlacement)
        defaults.removeObject(forKey: Keys.savedPanelScreenIdentifier)
    }

    func restoreHotKeysWithoutNotifying(
        launcher: HotKeyDefinition,
        clipboard: HotKeyDefinition
    ) {
        suppressHotKeyNotification = true
        launcherHotKey = launcher
        clipboardHotKey = clipboard
        suppressHotKeyNotification = false
    }

    func clearUsageLearning() {
        clearUsageLearningHandler?()
    }

    func isSearchContentEnabled(_ type: SearchContentType) -> Bool {
        enabledSearchContentTypes.contains(type)
    }

    func setSearchContent(_ type: SearchContentType, enabled: Bool) {
        if enabled {
            enabledSearchContentTypes.insert(type)
        } else {
            enabledSearchContentTypes.remove(type)
        }
    }

    var systemCommandConfiguration: SystemCommandConfiguration {
        SystemCommandConfiguration(enabled: enabledSystemCommands, keywords: systemCommandKeywords)
    }

    func isSystemCommandEnabled(_ command: SystemCommandID) -> Bool {
        enabledSystemCommands.contains(command)
    }

    func setSystemCommand(_ command: SystemCommandID, enabled: Bool) {
        if enabled {
            enabledSystemCommands.insert(command)
        } else {
            enabledSystemCommands.remove(command)
        }
    }

    func setSystemCommandKeyword(_ keyword: String, for command: SystemCommandID) {
        systemCommandKeywords[command] = keyword
    }

    func restoreSystemCommandDefaults() {
        enabledSystemCommands = Set(SystemCommandID.allCases)
        systemCommandKeywords = Dictionary(uniqueKeysWithValues: SystemCommandID.allCases.map {
            ($0, $0.defaultKeyword)
        })
    }

    func addSearchScope(_ url: URL) {
        guard !searchScopePaths.contains(url.path) else { return }
        searchScopePaths.append(url.path)
    }

    func removeSearchScope(_ path: String) {
        searchScopePaths.removeAll { $0 == path }
    }

    func addApplicationAliasTarget(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard url.pathExtension.lowercased() == "app", applicationAliases[path] == nil else { return }
        applicationAliases[path] = ""
    }

    func setApplicationAliases(_ aliases: String, forPath path: String) {
        guard applicationAliases[path] != nil else { return }
        applicationAliases[path] = aliases
    }

    func removeApplicationAliasTarget(_ path: String) {
        applicationAliases.removeValue(forKey: path)
    }

    func addClipboardIgnoredApplication(_ url: URL) {
        guard let bundleID = Bundle(url: url)?.bundleIdentifier?.lowercased(),
              !clipboardIgnoredBundleIDs.contains(bundleID) else { return }
        clipboardIgnoredBundleIDs.append(bundleID)
    }

    func removeClipboardIgnoredApplication(_ bundleID: String) {
        clipboardIgnoredBundleIDs.removeAll { $0 == bundleID }
    }

    private func notifyHotKeyChange() {
        if !suppressHotKeyNotification { hotKeysDidChange?() }
    }

    private func configureLaunchAtLogin() {
        guard !suppressLaunchAtLoginUpdate else { return }
        launchAtLoginError = nil
        do {
            try launchAtLoginService.setEnabled(launchAtLogin)
        } catch {
            suppressLaunchAtLoginUpdate = true
            launchAtLogin = launchAtLoginService.isEnabled
            suppressLaunchAtLoginUpdate = false
            launchAtLoginError = "无法修改登录启动：\(error.localizedDescription)"
        }
    }

    private func saveHotKey(_ hotKey: HotKeyDefinition, key: String) {
        if let data = try? JSONEncoder().encode(hotKey) { defaults.set(data, forKey: key) }
    }

    private static func loadHotKey(_ defaults: UserDefaults, key: String) -> HotKeyDefinition? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotKeyDefinition.self, from: data)
    }

    private static func validSearchScopes(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        return paths.compactMap { path in
            let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seen.insert(standardized).inserted else { return nil }
            return standardized
        }
    }

    private static func validApplicationAliases(_ aliases: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: aliases.compactMap { path, value in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard URL(fileURLWithPath: standardized).pathExtension.lowercased() == "app" else { return nil }
            return (standardized, value)
        })
    }

    private static func migrateIfNeeded(_ defaults: UserDefaults) {
        let storedVersion = defaults.integer(forKey: Keys.schemaVersion)
        guard storedVersion < currentSchemaVersion else { return }
        if storedVersion < 6,
           let width = defaults.object(forKey: Keys.panelWidth) as? Double,
           abs(width - 860) < 0.5 {
            // Narrow only the former default. Preserve widths the user chose.
            defaults.set(720.0, forKey: Keys.panelWidth)
        }
        if storedVersion < 9,
           let data = defaults.data(forKey: Keys.clipboardHotKey),
           let storedHotKey = try? JSONDecoder().decode(HotKeyDefinition.self, from: data),
           [
               HotKeyDefinition(
                   keyCode: UInt32(kVK_ANSI_C),
                   modifiers: UInt32(optionKey) | UInt32(cmdKey)
               ),
               HotKeyDefinition(
                   keyCode: UInt32(kVK_ANSI_C),
                   modifiers: UInt32(shiftKey) | UInt32(cmdKey)
               )
           ].contains(storedHotKey),
           let migratedData = try? JSONEncoder().encode(HotKeyDefinition.clipboardDefault) {
            // Move only known former defaults. Keep every other user-recorded shortcut.
            defaults.set(migratedData, forKey: Keys.clipboardHotKey)
        }
        defaults.set(currentSchemaVersion, forKey: Keys.schemaVersion)
    }

    private static func loadPanelTopLeft(_ defaults: UserDefaults) -> CGPoint? {
        guard let values = defaults.array(forKey: Keys.savedPanelTopLeft) as? [Double],
              values.count == 2,
              values[0].isFinite,
              values[1].isFinite else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    private static func loadPanelPlacement(_ defaults: UserDefaults) -> SavedPanelPlacement? {
        guard let values = defaults.array(forKey: Keys.savedPanelPlacement) as? [Double],
              values.count == 4,
              let relativePosition = RelativePanelPlacement(
                  horizontalFraction: values[0],
                  topFraction: values[1],
                  sourceVisibleWidth: values[2],
                  sourceVisibleHeight: values[3]
              ) else { return nil }
        return SavedPanelPlacement(
            relativePosition: relativePosition,
            screenIdentifier: defaults.string(forKey: Keys.savedPanelScreenIdentifier)
        )
    }

    private static let currentSchemaVersion = 9

    private enum Keys {
        static let schemaVersion = "preferences.schemaVersion"
        static let launcherHotKey = "preferences.hotkey.launcher"
        static let clipboardHotKey = "preferences.hotkey.clipboard"
        static let theme = "preferences.appearance.theme"
        static let accentColor = "preferences.appearance.accentColor"
        static let launcherAppearanceStyle = "preferences.appearance.launcherStyle"
        static let panelPosition = "preferences.appearance.position"
        static let screenPreference = "preferences.appearance.screen"
        static let savedPanelTopLeft = "preferences.appearance.savedPanelTopLeft"
        static let savedPanelPlacement = "preferences.appearance.savedPanelPlacement"
        static let savedPanelScreenIdentifier = "preferences.appearance.savedPanelScreenIdentifier"
        static let forcedKeyboardInputSourceID = "preferences.inputSource.forcedID"
        static let showMenuBarIcon = "preferences.general.showMenuBarIcon"
        static let compactResults = "preferences.appearance.compactResults"
        static let panelWidth = "preferences.appearance.panelWidth"
        static let panelCornerRadius = "preferences.appearance.panelCornerRadius"
        static let showSubtitles = "preferences.appearance.showSubtitles"
        static let showNumberShortcuts = "preferences.appearance.showNumberShortcuts"
        static let searchInputDelay = "preferences.search.inputDelay"
        static let previewSelectionDelay = "preferences.appearance.previewSelectionDelay"
        static let resultExpansionDuration = "preferences.appearance.resultExpansionDuration"
        static let enabledSearchContentTypes = "preferences.search.enabledContentTypes"
        static let enabledSystemCommands = "preferences.systemCommands.enabled"
        static let systemCommandKeywords = "preferences.systemCommands.keywords"
        static let includeFilesInDefaultResults = "preferences.search.includeFilesInDefaultResults"
        static let includeAutomaticDictionary = "preferences.search.includeAutomaticDictionary"
        static let maximumSearchResults = "preferences.search.maximumResults"
        static let searchScopePaths = "preferences.search.scopePaths"
        static let applicationAliases = "preferences.search.applicationAliases"
        static let fileNavigationShowsHiddenFiles = "preferences.files.showHidden"
        static let fileNavigationSort = "preferences.files.sort"
        static let fileNavigationSortAscending = "preferences.files.sortAscending"
        static let fileNavigationFoldersFirst = "preferences.files.foldersFirst"
        static let clipboardEnabled = "preferences.clipboard.enabled"
        static let clipboardPaused = "preferences.clipboard.paused"
        static let clipboardRetentionDays = "preferences.clipboard.retentionDays"
        static let clipboardMaximumItems = "preferences.clipboard.maximumItems"
        static let clipboardMaximumTextCharacters = "preferences.clipboard.maximumTextCharacters"
        static let clipboardStoreImages = "preferences.clipboard.storeImages"
        static let clipboardIgnoredBundleIDs = "preferences.clipboard.ignoredBundleIDs"
    }
}
