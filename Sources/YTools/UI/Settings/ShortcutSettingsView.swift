import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var snippets: SnippetManager
    @State private var draftKind: CustomHotKeyDraft.Kind?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsGroup(title: "全局快捷键",
                          footer: "组合键须包含 ⌘、⌥ 或 ⌃；被系统或其他应用占用时会在这里提示。") {
                SettingsRow(title: "显示启动器", target: "LauncherHotKey") {
                    HotKeyRecorderView(hotKey: $preferences.launcherHotKey, label: "启动器快捷键")
                }
                SettingsDivider()
                SettingsRow(title: "剪贴板历史", target: "ClipboardHotKey") {
                    HotKeyRecorderView(hotKey: $preferences.clipboardHotKey, label: "剪贴板快捷键")
                }
                if let error = preferences.hotKeyError {
                    SettingsNoteRow("⚠︎ " + error)
                }
                SettingsDivider()
                optionalHotKeyRow(
                    title: "截图识别文字", detail: "框选屏幕区域，识别出的文字放入剪贴板",
                    target: "RecognizeTextHotKey", unavailableID: "recognizeText",
                    hotKey: $preferences.toolHotKeys.recognizeText
                )
                SettingsDivider()
                optionalHotKeyRow(
                    title: "连续粘贴", detail: preferences.clipboardBehavior.sequentialPaste
                        ? "按复制顺序依次粘贴暂存的多条内容"
                        : "需先在“剪贴板 › 粘贴”中开启连续粘贴",
                    target: "SequentialPasteHotKey", unavailableID: "sequentialPaste",
                    hotKey: $preferences.toolHotKeys.sequentialPaste
                )
            }

            SettingsGroup(title: "自定义快捷键", isNew: true) {
                if preferences.customHotKeys.isEmpty {
                    SettingsEmptyRow(text: "还没有自定义快捷键。可以为常用应用、文件夹或文本片段各绑定一个组合键。")
                } else {
                    ForEach(Array(preferences.customHotKeys.enumerated()), id: \.element.id) { index, shortcut in
                        if index > 0 { SettingsDivider() }
                        customRow(shortcut)
                    }
                }
                SettingsDivider()
                SettingsNoteRow("快捷键在任何应用中都可用。") {
                    HStack(spacing: 6) {
                        Button("添加应用…") { draftKind = .application }
                        Button("添加文件夹…") { draftKind = .folder }
                        Button("添加片段…") { draftKind = .snippet }
                            .disabled(snippets.items.isEmpty)
                    }
                }
            }
            .settingsTarget("CustomHotKeys")
        }
        .sheet(item: $draftKind) { kind in
            AddCustomHotKeySheet(kind: kind, preferences: preferences, snippets: snippets)
        }
    }

    private func optionalHotKeyRow(title: String, detail: String, target: String, unavailableID: String,
                                   hotKey: Binding<HotKeyDefinition?>) -> some View {
        SettingsRow(title: title,
                    detail: preferences.unavailableHotKeyIDs.contains(unavailableID) && hotKey.wrappedValue != nil
                        ? "⚠︎ 该组合键已被占用，请换一个" : detail,
                    isNew: true, target: target) {
            HStack(spacing: 6) {
                OptionalHotKeyRecorderView(hotKey: hotKey, label: title + "快捷键")
                    .frame(width: 170, height: 30)
                Button {
                    hotKey.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .opacity(hotKey.wrappedValue == nil ? 0 : 1)
                .disabled(hotKey.wrappedValue == nil)
                .help("清除快捷键")
                .accessibilityLabel("清除" + title + "快捷键")
            }
        }
    }

    private func customRow(_ shortcut: CustomHotKey) -> some View {
        SettingsListItem(
            title: shortcut.title,
            subtitle: preferences.unavailableHotKeyIDs.contains(shortcut.id.uuidString)
                ? "⚠︎ 组合键已被占用" : shortcut.actionTitle
        ) {
            CustomHotKeyIcon(target: shortcut.target)
        } trailing: {
            HotKeyRecorderView(hotKey: customBinding(shortcut.id, fallback: shortcut.hotKey),
                               label: shortcut.title + "快捷键")
                .frame(width: 150, height: 28)
            RemoveButton(label: "移除" + shortcut.title + "快捷键") {
                preferences.customHotKeys.removeAll { $0.id == shortcut.id }
            }
        }
    }

    private func customBinding(_ id: UUID, fallback: HotKeyDefinition) -> Binding<HotKeyDefinition> {
        Binding(
            get: { preferences.customHotKeys.first { $0.id == id }?.hotKey ?? fallback },
            set: { value in
                guard let index = preferences.customHotKeys.firstIndex(where: { $0.id == id }) else { return }
                preferences.customHotKeys[index].hotKey = value
            }
        )
    }
}

struct CustomHotKeyIcon: View {
    let target: CustomHotKey.Target

    var body: some View {
        switch target {
        case let .application(path):
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().scaledToFit().frame(width: 24, height: 24)
        case .folder:
            SettingsTile(symbol: "folder.fill", color: SettingsSection.files.tint, size: 24)
        case .snippet:
            SettingsTile(symbol: "text.alignleft", color: SettingsSection.snippets.tint, size: 24)
        }
    }
}

enum CustomHotKeyDraft {
    enum Kind: String, Identifiable {
        case application
        case folder
        case snippet
        var id: String { rawValue }
        var title: String {
            switch self {
            case .application: "为应用添加快捷键"
            case .folder: "为文件夹添加快捷键"
            case .snippet: "为文本片段添加快捷键"
            }
        }
    }
}

private struct AddCustomHotKeySheet: View {
    let kind: CustomHotKeyDraft.Kind
    @ObservedObject var preferences: AppPreferences
    @ObservedObject var snippets: SnippetManager
    @Environment(\.dismiss) private var dismiss
    @State private var path: String?
    @State private var snippetID: UUID?
    @State private var hotKey: HotKeyDefinition?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(kind.title).font(.headline)
            SettingsGroup(title: "") {
                SettingsRow(title: kind == .snippet ? "文本片段" : kind == .application ? "应用" : "文件夹",
                            detail: targetDetail) {
                    if kind == .snippet {
                        Picker("文本片段", selection: $snippetID) {
                            Text("请选择").tag(UUID?.none)
                            ForEach(snippets.items.filter { !$0.content.isEmpty }) { item in
                                Text(item.title.isEmpty ? "未命名片段" : item.title).tag(UUID?.some(item.id))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200)
                    } else {
                        Button(path == nil ? "选择…" : "重新选择…", action: choosePath)
                    }
                }
                SettingsDivider()
                SettingsRow(title: "快捷键", detail: conflict ?? "点击后按下组合键") {
                    OptionalHotKeyRecorderView(hotKey: $hotKey, label: "新快捷键")
                        .frame(width: 170, height: 30)
                }
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("添加") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(target == nil || hotKey == nil || conflict != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if kind != .snippet, path == nil { choosePath() }
        }
    }

    private var targetDetail: String {
        switch kind {
        case .snippet: "选择后，按快捷键会把展开的片段粘贴到当前应用"
        case .application, .folder: path.map(abbreviatedHomePath) ?? "尚未选择"
        }
    }

    private var target: CustomHotKey.Target? {
        switch kind {
        case .application: path.map { .application(path: $0) }
        case .folder: path.map { .folder(path: $0) }
        case .snippet: snippetID.map { .snippet(id: $0) }
        }
    }

    private var title: String {
        switch kind {
        case .application:
            return path.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? ""
        case .folder:
            return path.map(abbreviatedHomePath) ?? ""
        case .snippet:
            let item = snippets.items.first { $0.id == snippetID }
            return "片段 · " + ((item?.title.isEmpty ?? true) ? "未命名片段" : item?.title ?? "")
        }
    }

    private var conflict: String? {
        guard let hotKey else { return nil }
        if hotKey == preferences.launcherHotKey { return "⚠︎ 与“显示启动器”冲突" }
        if hotKey == preferences.clipboardHotKey { return "⚠︎ 与“剪贴板历史”冲突" }
        if hotKey == preferences.toolHotKeys.recognizeText { return "⚠︎ 与“截图识别文字”冲突" }
        if hotKey == preferences.toolHotKeys.sequentialPaste { return "⚠︎ 与“连续粘贴”冲突" }
        if let existing = preferences.customHotKeys.first(where: { $0.hotKey == hotKey }) {
            return "⚠︎ 与“\(existing.title)”冲突"
        }
        return nil
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = kind == .application
        panel.canChooseDirectories = kind == .folder
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        if kind == .application {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        }
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.standardizedFileURL.path
    }

    private func add() {
        guard let target, let hotKey, conflict == nil else { return }
        preferences.customHotKeys.append(CustomHotKey(hotKey: hotKey, target: target, title: title))
        dismiss()
    }
}
