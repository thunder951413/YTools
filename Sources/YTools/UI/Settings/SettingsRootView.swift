import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var clipboardManager: ClipboardHistoryManager
    @ObservedObject var snippets: SnippetManager
    @ObservedObject var recentDocuments: RecentDocumentsManager
    @StateObject private var navigation = SettingsNavigationModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 22) {
                        settingsHeader
                        if navigation.searchText.isEmpty {
                            selectedSection
                        } else {
                            settingsSearchResults
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(30)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
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
            Text("本机模式 · 无联网")
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
            PrivacySettingsView(recentDocuments: recentDocuments)
        }
    }

    private var settingsSearchResults: some View {
        VStack(spacing: 10) {
            let matches = SettingsSection.allCases.filter(navigation.matches)
            if matches.isEmpty {
                ContentUnavailableView.search(text: navigation.searchText)
            } else {
                ForEach(matches) { section in
                    Button {
                        navigation.selection = section
                        navigation.searchText = ""
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title).font(.headline)
                                Text("打开相关设置").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

}
