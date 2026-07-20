import AppKit
import SwiftUI

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    @ObservedObject var preferences: AppPreferences
    let onActivate: () -> Void
    @FocusState private var searchFocused: Bool

    private var style: LauncherAppearanceStyle { preferences.launcherAppearanceStyle }
    private var isIdle: Bool {
        !model.isShowingActions
            && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isShowingActions {
                HStack(spacing: 12) {
                    Button {
                        model.dismissSecondaryView()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    Text(model.actionSubjectTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    Text("可用动作")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 22)
                .frame(height: style.headerHeight)
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: style.searchFontSize + 1))
                        .foregroundStyle(.secondary)
                    TextField("搜索应用和文件，或输入 /、~ 浏览目录", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: style.searchFontSize, weight: .medium))
                        .focused($searchFocused)
                        .onSubmit {
                            if model.activateSelected() { onActivate() }
                        }
                }
                .padding(.horizontal, 22)
                .frame(height: style.headerHeight)
            }

            if !model.isSearchPending, !isIdle || !style.collapsesWhenIdle {
                Divider()

                resultContent
            }

            if style.showsFooter, !isIdle, !model.isSearchPending {
                Divider()
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(style.backgroundStyle)
        .clipShape(RoundedRectangle(cornerRadius: preferences.panelCornerRadius, style: .continuous))
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private var resultContent: some View {
        if model.isShowingActions {
                ScrollViewReader { proxy in
                    List(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                        ActionRow(action: action, selected: index == model.selectedActionIndex)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                model.selectedActionIndex = index
                                if model.activateSelected() { onActivate() }
                            }
                            .id(action.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .onChange(of: model.selectedActionIndex) { _, index in
                        guard model.actions.indices.contains(index) else { return }
                        proxy.scrollTo(model.actions[index].id, anchor: .center)
                    }
                }
            } else if model.results.isEmpty {
                emptyResultsView
            } else {
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        List(Array(model.results.enumerated()), id: \.element.id) { index, result in
                            ResultRow(
                                result: result,
                                selected: index == model.selectedIndex,
                                compact: preferences.compactResults,
                                showSubtitle: preferences.showSubtitles,
                                buffered: model.isBuffered(result),
                                shortcutNumber: preferences.showNumberShortcuts && index < 9 ? index + 1 : nil,
                                selectionOpacity: style.selectionOpacity
                            )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.selectedIndex = index
                                    if model.activate(result) { onActivate() }
                                }
                                .contextMenu {
                                    if let url = result.fileURL {
                                        Button("打开") {
                                            if model.activate(result) { onActivate() }
                                        }
                                        Button("在访达中显示") {
                                            model.reveal(url)
                                            onActivate()
                                        }
                                        Button("复制路径") { model.copyPath(url) }
                                    }
                                }
                                .id(result.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                        .listStyle(.plain)
                        .onChange(of: model.selectedIndex) { _, index in
                            guard model.results.indices.contains(index) else { return }
                            proxy.scrollTo(model.results[index].id, anchor: .center)
                        }
                    }

                    if model.showsPreview, let url = model.displayedPreviewURL {
                        Divider()
                        FilePreviewView(url: url)
                            .frame(width: 330)
                    }
                }
        }
    }

    @ViewBuilder
    private var emptyResultsView: some View {
        if style == .modern {
            ContentUnavailableView(
                model.query.isEmpty ? "输入要查找的内容" : "没有本地结果",
                systemImage: "command",
                description: Text(model.query.isEmpty
                    ? "应用启动、计算和系统词典均在本机完成"
                    : "可尝试应用名称、open/find/in、tag、spell、recent 或 / 和 ~；不会跳转网页")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                Text("没有本地结果")
                    .font(.headline)
                Text("可尝试应用名称、open/find/in、tag、spell、recent，或使用 / 和 ~ 浏览目录")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var footer: some View {
        HStack {
                Text("↑↓ 选择")
                if model.isShowingActions {
                    Text("↩ 执行动作")
                    Text("← / Esc 返回")
                } else {
                    Text("↩ 执行")
                    Text("→ 动作")
                    Text("⌘↩ 访达")
                    Text("⇧ 预览")
                    Text("Esc 清空/关闭")
                    Text("⌘, 设置")
                }
                Spacer()
                if !model.fileBuffer.isEmpty {
                    Text("缓冲 \(model.fileBuffer.count) 项 · ⌥→ 动作")
                        .foregroundStyle(Color.accentColor)
                }
                Text("\(preferences.launcherHotKey.displayString) 启动器 · \(preferences.clipboardHotKey.displayString) 剪贴板")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.horizontalPadding)
            .frame(height: DesignTokens.footerHeight)
    }
}

private struct ResultRow: View {
    let result: LauncherResult
    let selected: Bool
    let compact: Bool
    let showSubtitle: Bool
    let buffered: Bool
    let shortcutNumber: Int?
    let selectionOpacity: Double

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.headline)
                    .lineLimit(1)
                if showSubtitle {
                    Text(result.subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            if buffered {
                Image(systemName: "tray.and.arrow.down.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("已加入文件缓冲")
            }
            if let shortcutNumber {
                Text("⌘\(shortcutNumber)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 5 : 9)
        .background(selected ? Color.accentColor.opacity(selectionOpacity) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.resultCornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(result.title)，\(result.subtitle)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var icon: some View {
        switch result.icon {
        case let .system(name):
            Image(systemName: name)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        case let .application(url):
            Image(nsImage: WorkspaceIconCache.shared.icon(for: url))
                .resizable()
                .scaledToFit()
        case let .file(url):
            Image(nsImage: WorkspaceIconCache.shared.icon(for: url))
                .resizable()
                .scaledToFit()
        }
    }
}

@MainActor
private final class WorkspaceIconCache {
    static let shared = WorkspaceIconCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 256
    }

    func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }
}

private struct ActionRow: View {
    let action: LauncherAction
    let selected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.systemIcon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: DesignTokens.resultIconSize, height: DesignTokens.resultIconSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title).font(.headline)
                Text(action.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if selected { Text("↩").foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.resultCornerRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("动作：\(action.title)，\(action.subtitle)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
