import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var manager: ClipboardHistoryManager
    @ObservedObject var preferences: AppPreferences
    let onActivate: () -> Void

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
                        if manager.copySelected() { onActivate() }
                    }
                Picker("类型", selection: $manager.filter) {
                    ForEach(ClipboardHistoryManager.Filter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)
                Button {
                    manager.showsClearConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清空全部历史")
                .disabled(manager.items.isEmpty)
            }
            .padding(.horizontal, 22)
            .frame(height: 72)

            Divider()

            if manager.filteredItems.isEmpty {
                ContentUnavailableView(
                    manager.query.isEmpty ? "暂无剪贴板历史" : "没有匹配内容",
                    systemImage: "clipboard",
                    description: Text("历史仅在本机加密保存；图片记录默认关闭")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(Array(manager.filteredItems.enumerated()), id: \.element.id) { index, item in
                        ClipboardHistoryRow(
                            item: item,
                            selected: index == manager.selectedIndex,
                            compact: preferences.compactResults
                        )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                manager.selectedIndex = index
                                manager.copy(item)
                                onActivate()
                            }
                            .contextMenu {
                                Button("复制") {
                                    manager.copy(item)
                                    onActivate()
                                }
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

            Divider()
            HStack(spacing: 14) {
                Text("↑↓ 选择")
                Text("↩ 复制")
                Text("⌘D 删除")
                Text("⌘S 存为片段")
                Text("Esc 清空/关闭")
                Spacer()
                if manager.query.isEmpty, manager.filteredItems.count < manager.items.count {
                    Text("显示最近 \(manager.filteredItems.count) / 共 \(manager.items.count) 条")
                } else {
                    Text("\(manager.items.count) 条")
                }
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
            Text("所选范围内的本机加密记录将被永久删除。")
        }
    }
}

private struct ClipboardHistoryRow: View {
    let item: ClipboardHistoryItem
    let selected: Bool
    let compact: Bool

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
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if item.pinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("固定项目不会因保留期限过期")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 5 : 9)
        .background(selected ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
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
