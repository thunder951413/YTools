import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var manager: ClipboardHistoryManager
    @ObservedObject var preferences: AppPreferences
    @ObservedObject private var preview: ClipboardPreviewController
    let onActivate: () -> Void

    init(manager: ClipboardHistoryManager, preferences: AppPreferences, onActivate: @escaping () -> Void) {
        self.manager = manager
        self.preferences = preferences
        self.onActivate = onActivate
        self.preview = manager.preview
    }

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clipboard")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                TextField("搜索剪贴板历史", text: $manager.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .medium))
                    .focused($searchFocused)
                    .onSubmit {
                        Task { if await manager.copySelected() { onActivate() } }
                    }
                Picker("类型", selection: $manager.filter) {
                    ForEach(ClipboardHistoryManager.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 260)
                Button { manager.togglePreview() } label: {
                    Image(systemName: preview.isVisible ? "sidebar.right" : "doc.text.magnifyingglass")
                }
                .buttonStyle(.plain).help("内容预览（⌘P）")
                .accessibilityLabel(preview.isVisible ? "关闭内容预览" : "显示内容预览")
                Button {
                    Task { await manager.syncCloudNow() }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("立即同步坚果云剪贴板")
                .disabled(!preferences.clipboardCloudSyncEnabled || manager.isLoading)
                .accessibilityLabel("立即加密同步剪贴板历史")
                Button {
                    manager.showsClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清空全部历史")
                .disabled(manager.items.isEmpty || manager.isClearing)
            }
            .padding(.horizontal, 22)
            .frame(height: 72)

            Divider()

            if let error = manager.copyError {
                statusMessage(error, symbol: "exclamationmark.triangle.fill", tint: .orange)
            } else if manager.isCopying {
                statusMessage("正在复制…", symbol: "doc.on.clipboard", tint: .secondary)
            } else if manager.isClearing {
                statusMessage("正在清理加密历史…", symbol: "trash", tint: .secondary)
            } else if let error = manager.storageError {
                statusMessage(error, symbol: "exclamationmark.triangle.fill", tint: .orange)
            } else if manager.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取本机加密历史…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
            } else if !manager.cloudSyncStatus.isEmpty {
                statusMessage(manager.cloudSyncStatus, symbol: "arrow.triangle.2.circlepath", tint: .secondary)
            }

            HStack(spacing: 0) {
            Group {
            if manager.filteredItems.isEmpty {
                ContentUnavailableView(
                    manager.items.isEmpty ? "暂无剪贴板历史" : "没有匹配内容",
                    systemImage: manager.query.isEmpty ? "clipboard" : "line.3.horizontal.decrease.circle",
                    description: Text(manager.items.isEmpty
                        ? (preferences.clipboardCloudSyncEnabled
                            ? "复制文本、文件或图片后会在这里出现；已启用坚果云加密同步"
                            : "复制文本、文件或图片后会在这里出现；历史在本机加密保存")
                        : "可清除关键词或切换“全部”查看其他记录")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ClipboardHistoryRow(
                            item: item,
                            selected: index == manager.selectedIndex,
                            compact: preferences.compactResults,
                            onTogglePin: { manager.togglePinned(item) }
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                manager.selectedIndex = index
                                Task { if await manager.copy(item) { onActivate() } }
                            }
                            .contextMenu {
                                Button("复制") {
                                    Task { if await manager.copy(item) { onActivate() } }
                                }
                                Button("预览") { manager.selectedIndex = index; preview.show(item) }
                                Button("删除", role: .destructive) {
                                    manager.delete(item)
                                }
                                Button(item.pinned ? "取消固定" : "固定") {
                                    manager.togglePinned(item)
                                }
                            }
                            .id(item.id)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .onChange(of: manager.selectedIndex) { _, index in
                        let visible = manager.filteredItems
                        guard visible.indices.contains(index) else { return }
                        proxy.scrollTo(visible[index].id, anchor: .center)
                    }
                }
            }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if preview.isVisible {
                Divider()
                ClipboardPreviewView(preview: preview).frame(width: 280)
            }
            }
            Divider()
            HStack(spacing: 12) {
                Text("已显示 \(manager.filteredItems.count) / 匹配 \(manager.totalMatches) 条")
                Spacer()
                if manager.hasMore {
                    Button("加载更多（100 条）") { manager.loadMore() }
                        .accessibilityLabel("加载更多匹配的剪贴板记录")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 32)
            HStack(spacing: 14) {
                Text("↑↓ 选择")
                Text("↩ 复制")
                Text("⌘D 删除")
                Text("Esc 清空/关闭")
                Spacer()
                Text(preferences.clipboardHotKey.displayString)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
            .frame(height: 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: preferences.panelCornerRadius, style: .continuous))
        .onAppear { searchFocused = true }
        .confirmationDialog(
            "清理剪贴板历史",
            isPresented: $manager.showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除最近 5 分钟", role: .destructive) { manager.clearRecent(minutes: 5) }
            Button("清除最近 15 分钟", role: .destructive) { manager.clearRecent(minutes: 15) }
            Button("清空全部", role: .destructive) { manager.clear() }
            Button("取消", role: .cancel) {}
        } message: {
            Text(preferences.clipboardCloudSyncEnabled
                ? "所选范围内的记录将被永久删除。删除会加密同步到同一账号和目录下的其他设备，离线设备会在恢复同步后删除；无法撤销。"
                : "所选范围内的本机加密记录将被永久删除，无法撤销。")
        }
    }

    private func statusMessage(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 32)
            .accessibilityLabel("剪贴板状态：\(text)")
    }
}

struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let selected: Bool
    let compact: Bool
    let onTogglePin: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            itemIcon
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayText)
                    .font(.body)
                    .lineLimit(2)
                    .textSelection(.disabled)
                HStack(spacing: 6) {
                    if let source = item.sourceApplication {
                        Text(source)
                    }
                    Text(item.createdAt, style: .relative)
                    if item.copyCount > 1 {
                        Text("×\(item.copyCount)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                onTogglePin()
            } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(item.pinned ? Color.accentColor : .secondary)
            .help(item.pinned ? "取消固定" : "固定项目")
            .accessibilityLabel(item.pinned ? "取消固定此剪贴板项目" : "固定此剪贴板项目")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 5 : 9)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind == .image ? "图片" : item.kind == .files ? "文件" : "文本")，\(item.displayText)，\(item.sourceApplication ?? "未知来源")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var itemIcon: some View {
        if item.kind == .image, let data = item.binaryData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: item.kind == .text ? "text.alignleft" : "doc.on.doc")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
        }
    }
}
