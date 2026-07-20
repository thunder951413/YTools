import SwiftUI

struct SnippetSettingsView: View {
    @ObservedObject var snippets: SnippetManager

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "文本片段", icon: "text.quote") {
                if let error = snippets.storageError {
                    Label(error, systemImage: "exclamationmark.shield")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Divider()
                }
                Text("在启动器中输入 snip 或“片段”搜索。剪贴板历史中按 Command + S 可快速保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if snippets.items.isEmpty {
                    Divider()
                    Text("暂无片段").foregroundStyle(.secondary)
                }
            }
            ForEach(snippets.items) { item in
                SettingsCard(title: item.title.isEmpty ? "未命名片段" : item.title, icon: "quote.opening") {
                    SettingsRow(title: "标题", detail: "搜索结果中显示的名称") {
                        TextField("标题", text: titleBinding(item)).frame(width: 230)
                    }
                    Divider()
                    SettingsRow(title: "关键词", detail: "可选，例如 addr 或 sig") {
                        TextField("关键词", text: keywordBinding(item)).frame(width: 230)
                    }
                    Divider()
                    SettingsRow(title: "分类", detail: "用于分组和搜索，例如 工作、个人") {
                        TextField("分类", text: collectionBinding(item)).frame(width: 230)
                    }
                    Divider()
                    TextField("片段内容", text: contentBinding(item), axis: .vertical)
                        .lineLimit(3...8)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Text("支持 {date}、{time}、{clipboard}、{cursor}")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("删除", role: .destructive) { snippets.delete(item) }
                    }
                }
            }
        }
        .onDisappear { snippets.flushPendingChanges() }
    }

    private func titleBinding(_ item: SnippetItem) -> Binding<String> {
        Binding(
            get: { snippets.items.first(where: { $0.id == item.id })?.title ?? "" },
            set: { snippets.update(id: item.id, title: $0) }
        )
    }

    private func keywordBinding(_ item: SnippetItem) -> Binding<String> {
        Binding(
            get: { snippets.items.first(where: { $0.id == item.id })?.keyword ?? "" },
            set: { snippets.update(id: item.id, keyword: $0) }
        )
    }

    private func contentBinding(_ item: SnippetItem) -> Binding<String> {
        Binding(
            get: { snippets.items.first(where: { $0.id == item.id })?.content ?? "" },
            set: { snippets.update(id: item.id, content: $0) }
        )
    }

    private func collectionBinding(_ item: SnippetItem) -> Binding<String> {
        Binding(
            get: { snippets.items.first(where: { $0.id == item.id })?.collection ?? "默认" },
            set: { snippets.update(id: item.id, collection: $0) }
        )
    }
}
