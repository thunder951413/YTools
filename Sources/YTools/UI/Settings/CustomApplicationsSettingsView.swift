import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CustomApplicationsSettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @StateObject private var fileImporter = FileImporterPresentation()

    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "自定义应用", icon: "app.badge.plus") {
                Text("添加不在标准应用目录中的本机应用。它们会加入应用搜索；别名可用逗号分隔。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if sortedPaths.isEmpty {
                    ContentUnavailableView(
                        "尚未添加自定义应用",
                        systemImage: "app.badge.plus",
                        description: Text("选择 .app 应用后，它会出现在这里和启动器搜索结果中。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    ForEach(sortedPaths, id: \.self) { path in
                        Divider()
                        applicationRow(path: path)
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
            for url in urls {
                guard let path = preferences.addCustomApplication(url) else { continue }
                preferences.addApplicationAliasTarget(URL(fileURLWithPath: path))
            }
        }
        .fileDialogDefaultDirectory(URL(fileURLWithPath: "/Applications", isDirectory: true))
        .fileDialogConfirmationLabel("添加应用")
    }

    private var sortedPaths: [String] {
        preferences.customApplicationPaths.sorted {
            applicationName(for: $0).localizedStandardCompare(applicationName(for: $1)) == .orderedAscending
        }
    }

    private func applicationRow(path: String) -> some View {
        let isMissing = !FileManager.default.fileExists(atPath: path)
        return HStack(alignment: .center, spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
                .opacity(isMissing ? 0.45 : 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(applicationName(for: path)).font(.headline)
                    if isMissing {
                        Text("找不到")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.red)
                    }
                }
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TextField("别名", text: aliasBinding(path))
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
            Button {
                preferences.removeCustomApplication(path)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .help("移除自定义应用")
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
