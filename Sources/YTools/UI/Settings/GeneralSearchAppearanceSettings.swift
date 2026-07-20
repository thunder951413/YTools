import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var recentDocuments: RecentDocumentsManager

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "启动器", icon: "magnifyingglass") {
                Toggle("登录时启动 YTools", isOn: $preferences.launchAtLogin)
                if let error = preferences.launchAtLoginError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Divider()
                SettingsRow(title: "显示菜单栏图标", detail: "隐藏后应用继续在后台运行，可通过全局快捷键或 Command+, 打开设置") {
                    Toggle("", isOn: $preferences.showMenuBarIcon)
                        .labelsHidden()
                }
                Divider()
                SettingsRow(title: "主快捷键", detail: "显示应用、文件和工具搜索") {
                    HotKeyRecorderView(hotKey: $preferences.launcherHotKey)
                }
                Divider()
                SettingsRow(title: "窗口位置", detail: "首次按预设显示；拖动后按当前显示器分辨率记住相对位置") {
                    Picker("", selection: $preferences.panelPosition) {
                        ForEach(PanelPosition.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Divider()
                SettingsRow(title: "显示器", detail: "多屏环境下选择启动器所在屏幕") {
                    Picker("", selection: $preferences.screenPreference) {
                        ForEach(ScreenPreference.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                if preferences.savedPanelTopLeft != nil {
                    Divider()
                    SettingsRow(title: "已记住拖动位置", detail: "切换显示器或分辨率后保持相对位置，并自动限制在可见区域") {
                        Button("恢复预设位置") { preferences.clearSavedPanelPosition() }
                    }
                }
                Divider()
                SettingsRow(title: "默认输入语言", detail: "每次显示启动器或剪贴板时切换；也可跟随系统当前输入源") {
                    Picker("", selection: $preferences.forcedKeyboardInputSourceID) {
                        Text("跟随当前输入源").tag("")
                        ForEach(KeyboardInputSourceManager.availableInputSources()) { source in
                            Text(source.name).tag(source.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }
                if let error = preferences.keyboardInputSourceError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }

            SettingsCard(title: "维护", icon: "arrow.counterclockwise") {
                SettingsRow(title: "清除使用学习", detail: "清除本机哈希排序和查询词绑定") {
                    Button("清除学习") { preferences.clearUsageLearning() }
                }
                Divider()
                SettingsRow(title: "清除最近文档", detail: "删除 YTools 本机加密保存的最近打开记录") {
                    Button("清除记录") { recentDocuments.clear() }
                        .disabled(recentDocuments.items.isEmpty)
                }
                Divider()
                SettingsRow(title: "恢复默认设置", detail: "恢复外观、快捷键和剪贴板选项") {
                    Button("恢复默认") { preferences.restoreDefaults() }
                }
            }
        }
    }
}

struct SearchSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @StateObject private var fileImporter = FileImporterPresentation()

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "显示的内容类型", icon: "square.grid.2x2") {
                ForEach(Array(SearchContentType.allCases.enumerated()), id: \.element.id) { index, type in
                    if index > 0 { Divider() }
                    Toggle(isOn: contentTypeBinding(type)) {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(type.title)
                                Text(type.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: type.icon)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 22)
                        }
                    }
                }
            }

            SettingsCard(title: "默认结果", icon: "list.bullet") {
                SettingsRow(title: "输入停止后搜索", detail: searchDelayDescription) {
                    Slider(value: $preferences.searchInputDelay, in: 0.05...0.4, step: 0.025)
                        .frame(width: 180)
                }
                Divider()
                Toggle("在默认结果中显示本地文件", isOn: $preferences.includeFilesInDefaultResults)
                    .disabled(!preferences.isSearchContentEnabled(.files))
                Divider()
                Toggle("自动显示单词释义", isOn: $preferences.includeAutomaticDictionary)
                    .disabled(!preferences.isSearchContentEnabled(.dictionary))
                Divider()
                SettingsRow(title: "最多文件结果", detail: "显式 open/find 搜索仍可显示更多") {
                    Stepper(
                        "\(preferences.maximumSearchResults) 条",
                        value: $preferences.maximumSearchResults,
                        in: 3...20
                    )
                    .frame(width: 120)
                }
            }

            SettingsCard(title: "Spotlight 搜索范围", icon: "folder.badge.gearshape") {
                Text(preferences.searchScopePaths.isEmpty
                     ? "当前搜索用户主目录。添加目录后将只搜索下面列出的范围。"
                     : "仅搜索以下目录：")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(preferences.searchScopePaths, id: \.self) { path in
                    Divider()
                    HStack {
                        Image(systemName: "folder")
                        Text(abbreviatedPath(path)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            preferences.removeSearchScope(path)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .help("移除搜索范围")
                    }
                }
                Divider()
                HStack {
                    Button("添加目录…") { fileImporter.isPresented = true }
                    if !preferences.searchScopePaths.isEmpty {
                        Button("恢复主目录") { preferences.searchScopePaths = [] }
                    }
                }
            }

            SettingsCard(title: "文件导航", icon: "folder") {
                Toggle("显示隐藏文件", isOn: $preferences.fileNavigationShowsHiddenFiles)
                Divider()
                SettingsRow(title: "排序依据", detail: "名称、创建时间或修改时间") {
                    Picker("", selection: $preferences.fileNavigationSort) {
                        ForEach(FileNavigationSort.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                Divider()
                Toggle("升序排列", isOn: $preferences.fileNavigationSortAscending)
                Divider()
                Toggle("文件夹优先", isOn: $preferences.fileNavigationFoldersFirst)
                Divider()
                Text("输入 / 或 ~ 浏览；文件名可使用 * 通配符。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .fileImporter(
            isPresented: $fileImporter.isPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            urls.forEach(preferences.addSearchScope)
        }
        .fileDialogConfirmationLabel("添加搜索范围")
    }

    private func contentTypeBinding(_ type: SearchContentType) -> Binding<Bool> {
        Binding(
            get: { preferences.isSearchContentEnabled(type) },
            set: { preferences.setSearchContent(type, enabled: $0) }
        )
    }

    private var searchDelayDescription: String {
        let milliseconds = Int((preferences.searchInputDelay * 1_000).rounded())
        return "应用与计算等待 \(milliseconds) 毫秒；Spotlight 至少等待 300 毫秒"
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}

struct AppearanceSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        VStack(spacing: 14) {
            LauncherAppearancePreview(preferences: preferences)
            SettingsCard(title: "启动器风格", icon: "rectangle.3.group") {
                Picker("风格", selection: $preferences.launcherAppearanceStyle) {
                    ForEach(LauncherAppearanceStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Text(preferences.launcherAppearanceStyle.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard(title: "窗口与结果", icon: "paintbrush") {
                SettingsRow(title: "颜色模式", detail: "应用于启动器、剪贴板和设置") {
                    Picker("", selection: $preferences.theme) {
                        ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Divider()
                SettingsRow(title: "强调色", detail: "用于选中态、图标和操作提示") {
                    Picker("", selection: $preferences.accentColor) {
                        ForEach(AppAccentColor.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Divider()
                Toggle("使用紧凑结果间距", isOn: $preferences.compactResults)
                Divider()
                Toggle("显示结果副标题和路径", isOn: $preferences.showSubtitles)
                Divider()
                Toggle("显示 Command + 1…9 快速执行提示", isOn: $preferences.showNumberShortcuts)
                Divider()
                SettingsRow(
                    title: "预览切换停留时间",
                    detail: previewDelayDescription
                ) {
                    Slider(value: $preferences.previewSelectionDelay, in: 0...0.8, step: 0.05)
                        .frame(width: 180)
                }
                Divider()
                SettingsRow(
                    title: "结果展开速度",
                    detail: resultExpansionDurationDescription
                ) {
                    Slider(value: $preferences.resultExpansionDuration, in: 0...0.4, step: 0.025)
                        .frame(width: 180)
                }
                Divider()
                SettingsRow(title: "面板宽度", detail: "当前 \(Int(preferences.panelWidth)) pt") {
                    Slider(value: $preferences.panelWidth, in: 640...960, step: 20)
                        .frame(width: 180)
                }
                Divider()
                SettingsRow(title: "外层圆角", detail: "当前 \(Int(preferences.panelCornerRadius)) pt") {
                    Slider(value: $preferences.panelCornerRadius, in: 10...20, step: 1)
                        .frame(width: 180)
                }
            }
        }
    }

    private var previewDelayDescription: String {
        let milliseconds = Int((preferences.previewSelectionDelay * 1_000).rounded())
        return milliseconds == 0
            ? "立即切换；适合轻量文件"
            : "选中项停留 \(milliseconds) 毫秒后才加载 Quick Look"
    }

    private var resultExpansionDurationDescription: String {
        let milliseconds = Int((preferences.resultExpansionDuration * 1_000).rounded())
        return milliseconds == 0
            ? "立即展开和收起，不播放尺寸动画"
            : "结果区域用 \(milliseconds) 毫秒展开或收起"
    }
}
