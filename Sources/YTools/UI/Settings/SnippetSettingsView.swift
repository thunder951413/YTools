import SwiftUI

struct SnippetSettingsView: View {
    @ObservedObject var snippets: SnippetManager
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var deleting: SnippetItem?
    private var matchingItems: [SnippetItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return snippets.items.filter { item in term.isEmpty || [item.title, item.keyword, item.collection, item.content]
            .contains { $0.localizedCaseInsensitiveContains(term) } }
    }
    private var filtered: [SnippetItem] {
        let matches = matchingItems
        if let selected, !matches.contains(where: { $0.id == selected.id }) { return [selected] + matches }
        return matches
    }
    private var selected: SnippetItem? { snippets.items.first { $0.id == selectedID } }
    var body: some View {
        SettingsCard(title: "文本片段", icon: "text.quote") {
            HStack {
                Label(snippets.storageStatus, systemImage: snippets.isSaving ? "arrow.triangle.2.circlepath" : "lock.fill")
                    .font(.caption).foregroundStyle(snippets.storageError == nil ? Color.secondary : .orange)
                Spacer()
                if snippets.storageError != nil {
                    Button("重试保存") { Task { await snippets.flushPendingChanges() } }
                }
                Button("新建") { query = ""; selectedID = snippets.createDraft() }
                    .disabled(!snippets.isLoaded).accessibilityLabel("新建文本片段")
            }
            Text("修改自动加密保存；输入 snip 或“片段”可搜索并复制。空白草稿不会出现在启动器结果中。")
                .font(.caption).foregroundStyle(.secondary)
            TextField("搜索标题、关键词、分类或内容", text: $query).textFieldStyle(.roundedBorder)
                .accessibilityLabel("筛选文本片段")
            HStack(alignment: .top, spacing: 14) {
                List(filtered, selection: $selectedID) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title.isEmpty ? "未命名片段" : item.title).lineLimit(1)
                        Text([item.collection, item.keyword].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.padding(.vertical, 4).tag(item.id)
                }
                .listStyle(.bordered).frame(width: 170, height: 360).accessibilityLabel("文本片段列表")
                Divider()
                if let item = selected {
                    VStack(alignment: .leading, spacing: 10) {
                        field("标题", value: binding(item.id, \.title))
                        field("关键词", value: binding(item.id, \.keyword))
                        field("分类", value: binding(item.id, \.collection))
                        Text("内容").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: binding(item.id, \.content)).autocorrectionDisabled(true).font(.system(size: 13))
                            .frame(height: 160).border(Color.secondary.opacity(0.2))
                            .accessibilityLabel("片段内容").id(item.id)
                        Text("支持 {date}、{time}、{clipboard}、{cursor}").font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Text("\(item.content.count) 字符").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("删除", role: .destructive) { deleting = item }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(snippets.items.isEmpty ? "点击“新建”开始保存片段" : "选择左侧片段开始编辑")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            Text("\(filtered.count) / \(snippets.items.count) 条片段").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { selectFirstIfNeeded() }
        .onChange(of: query) { _, _ in selectFirstIfNeeded(filteredOnly: true) }
        .onChange(of: snippets.items.map(\.id)) { _, _ in selectFirstIfNeeded() }
        .onChange(of: selectedID) { _, _ in Task { await snippets.flushPendingChanges() } }
        .onDisappear { Task { await snippets.flushPendingChanges() } }
        .confirmationDialog("删除此片段？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除片段", role: .destructive) { if let deleting { snippets.delete(deleting) }; deleting = nil }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("仅删除本机保存的这条片段，无法撤销。") }
    }
    private func selectFirstIfNeeded(filteredOnly: Bool = false) {
        let source = filteredOnly ? matchingItems : snippets.items
        if !source.contains(where: { $0.id == selectedID }) { selectedID = source.first?.id }
    }
    private func field(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: value).textFieldStyle(.roundedBorder).accessibilityLabel("片段\(title)")
        }
    }
    private func binding(_ id: UUID, _ key: WritableKeyPath<SnippetItem, String>) -> Binding<String> {
        Binding(get: { snippets.items.first { $0.id == id }?[keyPath: key] ?? "" }, set: { text in
            if key == \.title { snippets.update(id: id, title: text) }
            else if key == \.keyword { snippets.update(id: id, keyword: text) }
            else if key == \.collection { snippets.update(id: id, collection: text) }
            else { snippets.update(id: id, content: text) }
        })
    }
}
