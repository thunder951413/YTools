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

    func search(_ request: BackgroundSearchRequest) async -> [LauncherResult] {
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
            return sanitize(
                results,
                descriptor: descriptor,
                policy: ModuleResultPolicy(allowedCapabilities: [.localFileRead])
            )
        }

        async let applicationResults = request.enabledContentTypes.contains(.applications)
            ? searchApplications(query: request.query, aliases: request.applicationAliases)
            : []
        async let moduleResults = searchModules(
            query: request.query,
            registrations: standardModules + request.requestModules,
            enabledContentTypes: request.enabledContentTypes
        )
        let combined = await applicationResults + moduleResults
        return Task.isCancelled ? [] : combined
    }

    private func searchApplications(query: String, aliases: [String: String]) async -> [LauncherResult] {
        let descriptor = ModuleDescriptor(
            id: "applications",
            name: "应用程序",
            capabilities: [.localFileRead]
        )
        let results = await applications.results(for: query, aliases: aliases)
        return sanitize(
            results,
            descriptor: descriptor,
            policy: ModuleResultPolicy(allowedCapabilities: [.localFileRead])
        )
    }

    private func searchModules(
        query: String,
        registrations: [RegisteredSearchModule],
        enabledContentTypes: Set<SearchContentType>
    ) async -> [LauncherResult] {
        await withTaskGroup(of: [LauncherResult].self, returning: [LauncherResult].self) { group in
            for registration in registrations {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    break
                }
                guard enabledContentTypes.contains(registration.contentType) else { continue }
                let descriptor = registration.module.descriptor
                guard registration.policy.permits(descriptor) else { continue }
                let wasAdded = group.addTaskUnlessCancelled {
                    await Self.search(registration.module, query: query, policy: registration.policy)
                }
                if !wasAdded { break }
            }
            var combined: [LauncherResult] = []
            for await results in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return []
                }
                combined.append(contentsOf: results)
            }
            return combined
        }
    }

    private static func search(
        _ module: any YToolsModule,
        query: String,
        policy: ModuleResultPolicy
    ) async -> [LauncherResult] {
        do {
            let request = ModuleSearchRequest(query: query, maximumResults: 40)
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
