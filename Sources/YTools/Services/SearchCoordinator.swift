import Foundation
import YToolsModuleKit

struct RegisteredSearchModule: Sendable {
    let module: any YToolsModule
    let policy: ModuleResultPolicy
    let contentType: SearchContentType

    init(
        _ module: any YToolsModule,
        contentType: SearchContentType,
        allowedCapabilities: Set<ModuleCapability> = [],
        allowsPrivilegedActions: Bool = false
    ) {
        self.module = module
        self.contentType = contentType
        self.policy = ModuleResultPolicy(
            allowedCapabilities: allowedCapabilities,
            allowsPrivilegedActions: allowsPrivilegedActions
        )
    }
}

struct BackgroundSearchRequest: Sendable {
    let query: String
    let fileNavigationActive: Bool
    let showsHiddenFiles: Bool
    let fileNavigationSort: FileNavigationSort
    let fileNavigationSortAscending: Bool
    let fileNavigationFoldersFirst: Bool
    let enabledContentTypes: Set<SearchContentType>
    let applicationAliases: [String: String]
    let customApplicationPaths: [String]
    let maximumResults: Int
    let requestModules: [RegisteredSearchModule]
}

/// Owns every non-Spotlight query provider. All results—including trusted
/// built-ins—cross the same descriptor, capability, field and action policy.
actor SearchCoordinator {
    private let applications = ApplicationModule()
    private let fileNavigation = FileNavigationModule()
    private let standardModules: [RegisteredSearchModule]

    init(personalModules: [any YToolsModule] = [TextStatisticsModule()]) {
        standardModules = [
            RegisteredSearchModule(CalculatorModule(), contentType: .calculations),
            RegisteredSearchModule(UnitConversionModule(), contentType: .calculations),
            RegisteredSearchModule(SpellingModule(), contentType: .dictionary),
            RegisteredSearchModule(SettingsModule(), contentType: .systemTools)
        ] + personalModules.map { RegisteredSearchModule($0, contentType: .textTools) }
    }

    func prepare() async {
        await applications.prepare()
    }

    func search(_ request: BackgroundSearchRequest,
                onUpdate: (@Sendable ([LauncherResult]) async -> Void)? = nil) async -> [LauncherResult] {
        guard !Task.isCancelled else { return [] }
        if request.fileNavigationActive {
            guard request.enabledContentTypes.contains(.files) else { return [] }
            let descriptor = ModuleDescriptor(
                id: "file-navigation",
                name: "文件导航",
                capabilities: [.localFileRead]
            )
            let results = fileNavigation.results(
                for: request.query,
                showsHiddenFiles: request.showsHiddenFiles,
                sort: request.fileNavigationSort,
                ascending: request.fileNavigationSortAscending,
                foldersFirst: request.fileNavigationFoldersFirst
            )
            let sanitized = sanitize(
                results,
                descriptor: descriptor,
                policy: ModuleResultPolicy(allowedCapabilities: [.localFileRead])
            )
            if !Task.isCancelled { await onUpdate?(sanitized) }
            return sanitized
        }

        return await withTaskGroup(of: [LauncherResult].self) { group in
            if request.enabledContentTypes.contains(.applications) {
                group.addTask {
                    await self.searchApplications(query: request.query, aliases: request.applicationAliases,
                        customApplicationPaths: request.customApplicationPaths)
                }
            }
            for registration in standardModules + request.requestModules {
                guard request.enabledContentTypes.contains(registration.contentType),
                      registration.policy.permits(registration.module.descriptor) else { continue }
                group.addTask {
                    await Self.search(registration.module, query: request.query,
                        maximumResults: request.maximumResults, policy: registration.policy)
                }
            }
            var combined: [LauncherResult] = []
            for await results in group {
                guard !Task.isCancelled else { group.cancelAll(); return [] }
                combined.append(contentsOf: results)
                if !results.isEmpty { await onUpdate?(combined) }
            }
            return Task.isCancelled ? [] : combined
        }
    }

    private func searchApplications(
        query: String,
        aliases: [String: String],
        customApplicationPaths: [String]
    ) async -> [LauncherResult] {
        let descriptor = ModuleDescriptor(
            id: "applications",
            name: "应用程序",
            capabilities: [.localFileRead]
        )
        let results = await applications.results(
            for: query,
            aliases: aliases,
            customApplicationPaths: customApplicationPaths
        )
        return sanitize(
            results,
            descriptor: descriptor,
            policy: ModuleResultPolicy(allowedCapabilities: [.localFileRead])
        )
    }

    private static func search(
        _ module: any YToolsModule,
        query: String,
        maximumResults: Int,
        policy: ModuleResultPolicy
    ) async -> [LauncherResult] {
        do {
            let request = ModuleSearchRequest(
                query: query,
                maximumResults: min(max(maximumResults, 3), 40)
            )
            let results = try await module.search(request)
            guard !Task.isCancelled else { return [] }
            return results.prefix(request.maximumResults).compactMap {
                policy.sanitize($0, from: module.descriptor)
            }
        } catch {
            return []
        }
    }

    private func sanitize(
        _ results: [LauncherResult],
        descriptor: ModuleDescriptor,
        policy: ModuleResultPolicy
    ) -> [LauncherResult] {
        results.prefix(40).compactMap { policy.sanitize($0, from: descriptor) }
    }
}
