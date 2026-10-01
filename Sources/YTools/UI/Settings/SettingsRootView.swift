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
            VStack(spacing: 0) {
                settingsHeader
                    .frame(maxWidth: 860)
                    .padding(.horizontal, 30).padding(.top, 24).padding(.bottom, 22)
                ScrollViewReader { proxy in
                ScrollView {
                    HStack(alignment: .top, spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 22) {
                            if navigation.searchText.isEmpty {
                                selectedSection
                                    .id("section:" + navigation.selection.rawValue)
                                    .environment(\.highlightedSetting, navigation.targetID)
                            } else {
                                settingsSearchResults
                            }
                        }
                        .frame(maxWidth: 860, alignment: .leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 30).padding(.bottom, 30)
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
                    proxy.scrollTo(target, anchor: .center)
                }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 500)
        .autocorrectionDisabled(true)
        .tint(preferences.accentColor.color)
        .onReceive(NotificationCenter.default.publisher(for: .focusYToolsSettingsSearch)) { _ in
            searchFocused = true
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "command.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("YTools").font(.headline)
                    Text("原生效率工具").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 18)

            ForEach(SettingsSection.allCases) { section in
                Button {
                    navigation.selection = section
                    navigation.targetID = nil
                    navigation.searchText = ""
                } label: {
                    Label(section.title, systemImage: section.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            navigation.selection == section
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(appVersion) · \(preferences.clipboardCloudSyncEnabled ? "坚果云加密同步已启用" : "本机模式 · 同步已关闭")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        .padding(14)
        .frame(width: 190)
        .background(.ultraThinMaterial)
    }

    private var settingsHeader: some View {
        HStack {
            Text(navigation.searchText.isEmpty ? navigation.selection.title : "搜索设置")
                .font(.system(size: 26, weight: .semibold))
            Spacer()
            TextField("搜索设置", text: $navigation.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
                .focused($searchFocused)
        }
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch navigation.selection {
        case .general:
            GeneralSettingsView(preferences: preferences, recentDocuments: recentDocuments)
        case .search:
            SearchSettingsView(preferences: preferences)
        case .customApplications:
            CustomApplicationsSettingsView(preferences: preferences)
        case .applicationAliases:
            ApplicationAliasesSettingsView(preferences: preferences)
        case .systemCommands:
            SystemCommandsSettingsView(preferences: preferences)
        case .appearance:
            AppearanceSettingsView(preferences: preferences)
        case .shortcuts:
            ShortcutSettingsView(preferences: preferences)
        case .clipboard:
            ClipboardSettingsView(preferences: preferences, clipboardManager: clipboardManager)
        case .snippets:
            SnippetSettingsView(snippets: snippets)
        case .privacy:
            PrivacySettingsView(recentDocuments: recentDocuments) {
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
        VStack(spacing: 10) {
            let targets = SettingsSearchCatalog.searchTargets(navigation.searchText)
            let sections = SettingsSection.allCases.filter { section in navigation.matches(section) && !targets.contains(where: { $0.sectionID == section.rawValue }) }
            if targets.isEmpty && sections.isEmpty {
                ContentUnavailableView.search(text: navigation.searchText)
            } else {
                ForEach(targets) { target in
                    Button { navigation.open(target) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(target.title).font(.headline)
                                Text(SettingsSection(rawValue: target.sectionID)?.title ?? "设置")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }.buttonStyle(.plain).accessibilityLabel("定位设置：" + target.title)
                }
                ForEach(sections) { section in
                    Button("打开" + section.title) {
                        navigation.selection = section
                        navigation.searchText = ""
                        navigation.targetID = "section:" + section.rawValue
                        navigation.targetRevision += 1
                    }
                }
            }
        }
    }

}
