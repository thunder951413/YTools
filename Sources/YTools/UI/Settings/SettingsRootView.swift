import SwiftUI
import YToolsCore

struct SettingsRootView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var clipboardManager: ClipboardHistoryManager
    @ObservedObject var snippets: SnippetManager
    @ObservedObject var recentDocuments: RecentDocumentsManager
    @StateObject private var navigation: SettingsNavigationModel
    @FocusState private var searchFocused: Bool
    private var appVersion: String {
        guard Bundle.main.bundleIdentifier == "com.ztools.native" else { return "开发版" }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    init(preferences: AppPreferences, clipboardManager: ClipboardHistoryManager, snippets: SnippetManager,
         recentDocuments: RecentDocumentsManager, navigation: SettingsNavigationModel = SettingsNavigationModel()) {
        self.preferences = preferences
        self.clipboardManager = clipboardManager
        self.snippets = snippets
        self.recentDocuments = recentDocuments
        _navigation = StateObject(wrappedValue: navigation)
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 22) {
                            settingsHeader
                            if navigation.searchText.isEmpty {
                                selectedSection
                                    .id("section:" + navigation.selection.rawValue)
                                    .environment(\.highlightedSetting, navigation.targetID)
                            } else {
                                settingsSearchResults
                            }
                        }
                        .frame(maxWidth: 760, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 32).padding(.top, 26).padding(.bottom, 32)
                    .id("settings-content-top")
                }
                .onChange(of: navigation.selection) { _, _ in
                    guard navigation.targetID == nil else { return }
                    proxy.scrollTo("settings-content-top", anchor: .top)
                }
                .onChange(of: navigation.searchText) { _, text in
                    if !text.isEmpty { proxy.scrollTo("settings-content-top", anchor: .top) }
                }
                .task(id: navigation.targetRevision) {
                    guard let target = navigation.targetID else { return }
                    try? await Task.sleep(for: .milliseconds(120))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 520)
        .autocorrectionDisabled(true)
        .tint(preferences.accentColor.color)
        .onReceive(NotificationCenter.default.publisher(for: .focusYToolsSettingsSearch)) { _ in
            searchFocused = true
        }
    }

    // MARK: Sidebar

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("搜索设置", text: $navigation.searchText)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .accessibilityLabel("搜索设置")
                if !navigation.searchText.isEmpty {
                    Button {
                        navigation.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SettingsSectionGroup.allCases) { group in
                        Text(group.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, group == .basics ? 4 : 12)
                            .padding(.bottom, 3)
                        ForEach(group.sections) { section in
                            sidebarButton(section)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            Divider()
            HStack(spacing: 6) {
                Circle()
                    .fill(preferences.clipboardCloudSyncEnabled ? Color.green : Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(preferences.clipboardCloudSyncEnabled ? "坚果云同步已启用" : "本机模式 · 同步已关闭")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(appVersion == "开发版" ? appVersion : "YTools " + appVersion)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 34)
        }
        .frame(width: 236)
        .background(.ultraThinMaterial)
    }

    private func sidebarButton(_ section: SettingsSection) -> some View {
        let selected = navigation.searchText.isEmpty && navigation.selection == section
        let dimmed = !navigation.searchText.isEmpty && !navigation.matches(section)
            && !SettingsSearchCatalog.searchTargets(navigation.searchText).contains { $0.sectionID == section.rawValue }
        return Button {
            navigation.select(section)
        } label: {
            HStack(spacing: 9) {
                SettingsTile(symbol: section.icon, color: section.tint)
                Text(section.title)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: 30)
            .background(selected ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .opacity(dimmed ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Content

    private var settingsHeader: some View {
        HStack(spacing: 14) {
            if navigation.searchText.isEmpty {
                SettingsTile(symbol: navigation.selection.icon, color: navigation.selection.tint, size: 38)
            } else {
                SettingsTile(symbol: "magnifyingglass", color: .accentColor, size: 38)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(navigation.searchText.isEmpty ? navigation.selection.title : "搜索设置")
                    .font(.system(size: 22, weight: .semibold))
                Text(navigation.searchText.isEmpty
                     ? navigation.selection.summary
                     : "“\(navigation.searchText)” 的匹配结果")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch navigation.selection {
        case .general:
            GeneralSettingsView(preferences: preferences)
        case .appearance:
            AppearanceSettingsView(preferences: preferences)
        case .shortcuts:
            ShortcutSettingsView(preferences: preferences, snippets: snippets)
        case .search:
            SearchSettingsView(preferences: preferences)
        case .apps:
            ApplicationsSettingsView(preferences: preferences)
        case .files:
            FilesSettingsView(preferences: preferences)
        case .tools:
            ToolsSettingsView(preferences: preferences)
        case .system:
            SystemCommandsSettingsView(preferences: preferences)
        case .clipboard:
            ClipboardSettingsView(preferences: preferences, clipboardManager: clipboardManager)
        case .sync:
            CloudSyncSettingsView(preferences: preferences, clipboardManager: clipboardManager)
        case .snippets:
            SnippetSettingsView(snippets: snippets)
        case .permissions:
            PermissionsSettingsView()
        case .privacy:
            PrivacySettingsView(preferences: preferences, recentDocuments: recentDocuments) {
                LocalDiagnosticReport.text(version: appVersion,
                    platform: .macOS, backend: .spotlight, historyCount: clipboardManager.items.count,
                    pinnedCount: clipboardManager.items.filter(\.pinned).count, snippetCount: snippets.items.count,
                    preferencesHealthy: true, clipboardHealthy: clipboardManager.storageError == nil,
                    snippetsHealthy: snippets.storageError == nil, recentDocumentsHealthy: recentDocuments.storageError == nil,
                    cloudEnabled: preferences.clipboardCloudSyncEnabled)
            }
        }
    }

    private var settingsSearchResults: some View {
        let targets = SettingsSearchCatalog.searchTargets(navigation.searchText)
        let sections = SettingsSection.allCases.filter { section in
            navigation.matches(section) && !targets.contains(where: { $0.sectionID == section.rawValue })
        }
        return VStack(alignment: .leading, spacing: 18) {
            if targets.isEmpty && sections.isEmpty {
                ContentUnavailableView.search(text: navigation.searchText)
                    .frame(maxWidth: .infinity, minHeight: 260)
            }
            if !targets.isEmpty {
                SettingsGroup(title: "设置项") {
                    ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                        if index > 0 { SettingsDivider() }
                        let section = SettingsSection(rawValue: target.sectionID)
                        Button { navigation.open(target) } label: {
                            HStack(spacing: 10) {
                                SettingsTile(symbol: section?.icon ?? "gearshape.fill",
                                             color: section?.tint ?? .gray)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(target.title)
                                    Text(section?.title ?? "设置").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("定位设置：" + target.title)
                    }
                }
            }
            if !sections.isEmpty {
                SettingsGroup(title: "分类") {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        if index > 0 { SettingsDivider() }
                        Button {
                            navigation.selection = section
                            navigation.searchText = ""
                            navigation.targetID = "section:" + section.rawValue
                            navigation.targetRevision += 1
                        } label: {
                            HStack(spacing: 10) {
                                SettingsTile(symbol: section.icon, color: section.tint)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(section.title)
                                    Text(section.summary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开" + section.title)
                    }
                }
            }
        }
    }
}
