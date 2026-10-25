import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 搜索与结果

struct SearchSettingsView: View {
    @ObservedObject var preferences: AppPreferences

    private let newTypes: Set<SearchContentType> = [.textTransforms, .dateTime, .generators, .emoji, .runningApplications]
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("结果中显示")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(SearchContentType.allCases) { type in
                        contentTypeChip(type)
                    }
                }
            }
            .settingsTarget("EnabledSearchContentTypes")

            SettingsGroup(title: "搜索行为") {
                SettingsRow(title: "输入停止后搜索", detail: "应用与计算每次按键即时搜索；文件（Spotlight）和剪贴板历史按此等待，文件至少 300 毫秒") {
                    SettingsSlider(value: $preferences.searchInputDelay, range: 0.05...0.4, step: 0.025,
                                   label: "\(Int((preferences.searchInputDelay * 1_000).rounded())) ms")
                }
                SettingsDivider()
                SettingsToggleRow("默认结果包含本地文件", detail: "关闭后仅 open / find / in / tag 前缀搜索文件",
                                  target: "IncludeFilesInDefaultResults",
                                  isOn: $preferences.includeFilesInDefaultResults)
                    .disabled(!preferences.isSearchContentEnabled(.files))
                SettingsDivider()
                SettingsToggleRow("自动显示单词释义", target: "IncludeAutomaticDictionary",
                                  isOn: $preferences.includeAutomaticDictionary)
                    .disabled(!preferences.isSearchContentEnabled(.dictionary))
                SettingsDivider()
                SettingsRow(title: "最多文件结果", detail: "显式 open / find 搜索仍可显示更多") {
                    SettingsStepper(value: $preferences.maximumSearchResults, range: 3...20) { "\($0) 条" }
                }
            }
        }
    }

    private func contentTypeChip(_ type: SearchContentType) -> some View {
        let enabled = preferences.isSearchContentEnabled(type)
        return Button {
            preferences.setSearchContent(type, enabled: !enabled)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(type.title).foregroundStyle(.primary)
                        if newTypes.contains(type) { NewBadge() }
                    }
                    Text(type.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 4)
                Image(systemName: enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(enabled ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.78),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(enabled ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(type.detail)
        .accessibilityLabel(type.title)
        .accessibilityValue(enabled ? "已开启" : "已关闭")
    }
}

// MARK: - 应用

struct ApplicationsSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var importer: Importer?

    private enum Importer: String, Identifiable {
        case customApplication
        case aliasTarget
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "自定义应用") {
                if customPaths.isEmpty {
                    SettingsEmptyRow(text: "尚未添加自定义应用")
                } else {
                    ForEach(Array(customPaths.enumerated()), id: \.element) { index, path in
                        if index > 0 { SettingsDivider() }
                        SettingsListItem(title: applicationName(path), subtitle: abbreviatedHomePath(path)) {
                            applicationIcon(path)
                        } trailing: {
                            if !FileManager.default.fileExists(atPath: path) {
                                StatusPill(text: "找不到", tone: .warning)
                            }
                            RemoveButton(label: "移除自定义应用" + applicationName(path)) {
                                preferences.removeCustomApplication(path)
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsNoteRow("标准应用目录之外的 .app 也能被搜索和排序。") {
                    Button("添加应用…") { importer = .customApplication }
                }
            }
            .settingsTarget("CustomApplications")

            SettingsGroup(title: "应用别名") {
                if aliasPaths.isEmpty {
                    SettingsEmptyRow(text: "例如为 WeChat 添加“微信，weixin，wx”")
                } else {
                    ForEach(Array(aliasPaths.enumerated()), id: \.element) { index, path in
                        if index > 0 { SettingsDivider() }
                        SettingsListItem(title: applicationName(path)) {
                            applicationIcon(path)
                        } trailing: {
                            TextField("别名，用逗号分隔", text: aliasBinding(path))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 240)
                                .accessibilityLabel(applicationName(path) + "的别名")
                            RemoveButton(label: "移除" + applicationName(path) + "的别名") {
                                preferences.removeApplicationAliasTarget(path)
                            }
                        }
                    }
                }
                SettingsDivider()
                SettingsNoteRow("别名优先于模糊匹配；多个别名用逗号分隔，匹配完全在本机完成。") {
                    Button("添加别名…") { importer = .aliasTarget }
                }
            }
            .settingsTarget("ApplicationAliases")

            SettingsGroup(title: "运行中的应用", isNew: true) {
                SettingsToggleRow("在结果中标记正在运行",
                                  detail: "输入 running 或“运行中”列出；回车切换，→ 打开隐藏、退出等动作",
                                  target: "MarkRunningApplications",
                                  isOn: $preferences.behavior.markRunningApplications)
                SettingsDivider()
                SettingsToggleRow("退出前确认", detail: "避免误退出仍有未保存内容的应用",
                                  target: "ConfirmQuitApplication",
                                  isOn: $preferences.behavior.confirmQuitApplication)
            }
        }
        .fileImporter(
            isPresented: Binding(get: { importer != nil }, set: { if !$0 { importer = nil } }),
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true
        ) { result in
            let kind = importer
            importer = nil
            guard case let .success(urls) = result else { return }
            for url in urls {
                if kind == .customApplication {
                    guard let path = preferences.addCustomApplication(url) else { continue }
                    preferences.addApplicationAliasTarget(URL(fileURLWithPath: path))
                } else {
                    preferences.addApplicationAliasTarget(url)
                }
            }
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications", isDirectory: true))
        .fileDialogConfirmationLabel("添加应用")
    }

    private var customPaths: [String] {
        preferences.customApplicationPaths.sorted {
            applicationName($0).localizedStandardCompare(applicationName($1)) == .orderedAscending
        }
    }

    private var aliasPaths: [String] {
        preferences.applicationAliases.keys.sorted {
            applicationName($0).localizedStandardCompare(applicationName($1)) == .orderedAscending
        }
    }

    private func applicationIcon(_ path: String) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .scaledToFit()
            .frame(width: 26, height: 26)
            .opacity(FileManager.default.fileExists(atPath: path) ? 1 : 0.45)
    }

    private func aliasBinding(_ path: String) -> Binding<String> {
        Binding(
            get: { preferences.applicationAliases[path, default: ""] },
            set: { preferences.setApplicationAliases($0, forPath: path) }
        )
    }

    private func applicationName(_ path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

// MARK: - 文件

struct FilesSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var importer: Importer?
    @State private var extensionText = ""

    private enum Importer: String, Identifiable {
        case searchScope
        case favoriteFolder
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "搜索范围") {
                if preferences.searchScopePaths.isEmpty {
                    SettingsEmptyRow(text: "当前搜索整个主目录")
                } else {
                    ForEach(Array(preferences.searchScopePaths.enumerated()), id: \.element) { index, path in
                        if index > 0 { SettingsDivider() }
                        folderItem(path) { preferences.removeSearchScope(path) }
                    }
                }
                SettingsDivider()
                SettingsNoteRow("未添加目录时搜索整个主目录；添加后只搜索列出的目录。") {
                    HStack(spacing: 6) {
                        if !preferences.searchScopePaths.isEmpty {
                            Button("恢复主目录") { preferences.searchScopePaths = [] }
                        }
                        Button("添加目录…") { importer = .searchScope }
                    }
                }
            }
            .settingsTarget("SearchScopePaths")

            SettingsGroup(title: "常用文件夹", isNew: true) {
                if preferences.fileActions.favoriteFolders.isEmpty {
                    SettingsEmptyRow(text: "尚未添加常用文件夹")
                } else {
                    ForEach(Array(preferences.fileActions.favoriteFolders.enumerated()), id: \.element) { index, path in
                        if index > 0 { SettingsDivider() }
                        folderItem(path) {
                            preferences.fileActions.favoriteFolders.removeAll { $0 == path }
                        }
                    }
                }
                SettingsDivider()
                SettingsNoteRow("出现在文件动作“移到…”中，一步完成移动。") {
                    Button("添加文件夹…") { importer = .favoriteFolder }
                }
            }
            .settingsTarget("FavoriteFolders")

            SettingsGroup(title: "文件动作", isNew: true) {
                SettingsRow(title: "“在终端中打开”使用", target: "TerminalApplication") {
                    Picker("终端应用", selection: $preferences.fileActions.terminal) {
                        ForEach(TerminalApplication.allCases) { terminal in
                            Text(terminal.title + (isInstalled(terminal) ? "" : "（未安装）")).tag(terminal)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }
                SettingsDivider()
                SettingsToggleRow("压缩后显示在访达", detail: "压缩为 .zip，与原项目放在同一目录",
                                  target: "RevealArchiveAfterCompression",
                                  isOn: $preferences.fileActions.revealArchiveAfterCompression)
                SettingsDivider()
                SettingsRow(title: "新建文件默认扩展名", detail: "仅限字母和数字，最长 12 个字符",
                            target: "NewFileExtension") {
                    HStack(spacing: 2) {
                        Text(".").foregroundStyle(.secondary)
                        TextField("txt", text: $extensionText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .onSubmit(commitExtension)
                            .accessibilityLabel("新建文件默认扩展名")
                    }
                }
            }

            SettingsGroup(title: "导航与预览", footer: "输入 / 或 ~ 浏览目录；文件名可使用 * 通配符。") {
                SettingsToggleRow("显示隐藏文件", target: "FileNavigationShowsHiddenFiles",
                                  isOn: $preferences.fileNavigationShowsHiddenFiles)
                SettingsDivider()
                SettingsRow(title: "排序", target: "FileNavigationSort") {
                    Picker("排序", selection: $preferences.fileNavigationSort) {
                        ForEach(FileNavigationSort.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 230)
                }
                SettingsDivider()
                SettingsToggleRow("升序排列", target: "FileNavigationSortAscending",
                                  isOn: $preferences.fileNavigationSortAscending)
                SettingsDivider()
                SettingsToggleRow("文件夹优先", target: "FileNavigationFoldersFirst",
                                  isOn: $preferences.fileNavigationFoldersFirst)
                SettingsDivider()
                SettingsToggleRow("预览 PDF 与 Office 文档", detail: "使用系统快速查看，内容不离开本机",
                                  isNew: true, target: "PreviewDocuments",
                                  isOn: $preferences.fileActions.previewDocuments)
            }
        }
        .onAppear { extensionText = preferences.fileActions.newFileExtension }
        .onDisappear(perform: commitExtension)
        .onChange(of: extensionText) { _, _ in
            let sanitized = FileActionSettings.sanitizedExtension(extensionText)
            if sanitized == extensionText.lowercased(), sanitized != preferences.fileActions.newFileExtension {
                preferences.fileActions.newFileExtension = sanitized
            }
        }
        .fileImporter(
            isPresented: Binding(get: { importer != nil }, set: { if !$0 { importer = nil } }),
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            let kind = importer
            importer = nil
            guard case let .success(urls) = result else { return }
            for url in urls {
                if kind == .searchScope {
                    preferences.addSearchScope(url)
                } else {
                    let path = url.standardizedFileURL.path
                    if !preferences.fileActions.favoriteFolders.contains(path) {
                        preferences.fileActions.favoriteFolders.append(path)
                    }
                }
            }
        }
        .fileDialogConfirmationLabel("添加")
    }

    private func folderItem(_ path: String, remove: @escaping () -> Void) -> some View {
        SettingsListItem(title: abbreviatedHomePath(path), monospaced: true) {
            Image(systemName: FileManager.default.fileExists(atPath: path) ? "folder.fill" : "questionmark.folder")
                .foregroundStyle(SettingsSection.files.tint)
                .frame(width: 22)
        } trailing: {
            RemoveButton(label: "移除" + abbreviatedHomePath(path), action: remove)
        }
    }

    private func commitExtension() {
        let sanitized = FileActionSettings.sanitizedExtension(extensionText)
        preferences.fileActions.newFileExtension = sanitized
        extensionText = sanitized
    }

    private func isInstalled(_ terminal: TerminalApplication) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleIdentifier) != nil
    }
}
