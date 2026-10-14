import Foundation
import YToolsCore
import YToolsModuleKit

struct RunningApplicationInfo: Equatable, Sendable {
    let name: String
    let bundleIdentifier: String
    let path: String
}

/// `running` / `运行中` lists regular running apps (Return switches to one);
/// `quit <name>` / `退出 <name>` and `hide <name>` / `隐藏 <name>` act on them.
struct RunningApplicationsModule: YToolsModule {
    let descriptor = ModuleDescriptor(id: "running-applications", name: "运行中的应用", capabilities: [.localFileRead])
    let applications: [RunningApplicationInfo]

    enum Command: Equatable {
        case list(String)
        case quit(String)
        case hide(String)
    }

    static func command(for rawQuery: String) -> Command? {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        let lowered = query.lowercased()
        for keyword in ["running", "运行中", "switch", "切换"] {
            if lowered == keyword { return .list("") }
            if lowered.hasPrefix(keyword + " ") { return .list(String(query.dropFirst(keyword.count + 1))) }
        }
        for keyword in ["quit ", "退出 "] where lowered.hasPrefix(keyword) {
            return .quit(String(query.dropFirst(keyword.count)))
        }
        for keyword in ["hide ", "隐藏 "] where lowered.hasPrefix(keyword) {
            return .hide(String(query.dropFirst(keyword.count)))
        }
        return nil
    }

    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult] {
        guard let command = Self.command(for: request.query) else { return [] }
        let filter: String
        switch command {
        case let .list(text), let .quit(text), let .hide(text): filter = text.trimmingCharacters(in: .whitespaces)
        }
        let normalizer = SearchTextNormalizer()
        let matches = applications.filter { application in
            guard !filter.isEmpty else { return true }
            let forms = normalizer.forms(for: application.name)
            let needle = normalizer.normalized(filter)
            return forms.normalized.contains(needle) || forms.transliteration.contains(needle)
                || forms.abbreviation.hasPrefix(needle) || normalizer.fuzzyScore(query: filter, candidate: application.name) != nil
        }
        return matches.prefix(request.maximumResults).enumerated().map { index, application in
            let url = URL(fileURLWithPath: application.path)
            switch command {
            case .list:
                return LauncherResult(
                    id: "running:switch:\(application.bundleIdentifier)", moduleID: descriptor.id,
                    title: application.name, subtitle: "运行中 · 回车切换 · → 隐藏或退出",
                    icon: .application(url), score: 1_060 - index, action: .open(url)
                )
            case .quit:
                return LauncherResult(
                    id: "running:quit:\(application.bundleIdentifier)", moduleID: descriptor.id,
                    title: "退出 \(application.name)", subtitle: "请求应用正常退出",
                    icon: .application(url), score: 1_060 - index, action: .quitApplication(application.bundleIdentifier)
                )
            case .hide:
                return LauncherResult(
                    id: "running:hide:\(application.bundleIdentifier)", moduleID: descriptor.id,
                    title: "隐藏 \(application.name)", subtitle: "隐藏该应用的所有窗口",
                    icon: .application(url), score: 1_060 - index, action: .hideApplication(application.bundleIdentifier)
                )
            }
        }
    }
}
