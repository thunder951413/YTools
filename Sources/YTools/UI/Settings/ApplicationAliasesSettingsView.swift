import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ApplicationAliasesSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @StateObject private var fileImporter = FileImporterPresentation()

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "应用别名", icon: "app.badge") {
                Text("为本机应用添加更顺手的中文名、简称或拼音。多个别名请使用逗号分隔，匹配完全在本机完成。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if sortedPaths.isEmpty {
                    Divider()
                    ContentUnavailableView(
                        "尚未设置应用别名",
                        systemImage: "app.badge",
                        description: Text("例如为 WeChat 添加“微信，weixin，wx”")
                    )
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    ForEach(sortedPaths, id: \.self) { path in
                        Divider()
                        aliasRow(path: path)
                    }
                }

                Divider()
                Button("添加应用…") { fileImporter.isPresented = true }
            }
        }
        .fileImporter(
            isPresented: $fileImporter.isPresented,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            urls.forEach(preferences.addApplicationAliasTarget)
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications", isDirectory: true))
        .fileDialogConfirmationLabel("添加应用")
    }

    private var sortedPaths: [String] {
        preferences.applicationAliases.keys.sorted {
            applicationName(for: $0).localizedStandardCompare(applicationName(for: $1)) == .orderedAscending
        }
    }

    private func aliasRow(path: String) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(applicationName(for: path)).font(.headline)
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("例如 微信，weixin，wx", text: aliasBinding(path))
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
            Button {
                preferences.removeApplicationAliasTarget(path)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("移除应用别名")
        }
    }

    private func aliasBinding(_ path: String) -> Binding<String> {
        Binding(
            get: { preferences.applicationAliases[path, default: ""] },
            set: { preferences.setApplicationAliases($0, forPath: path) }
        )
    }

    private func applicationName(for path: String) -> String {
        URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}
