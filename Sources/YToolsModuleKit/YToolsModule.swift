import Foundation

public enum ModuleCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case localFileRead
    case clipboardRead
    case contactsRead
    case calendarRead
}

public struct ModuleDescriptor: Equatable, Sendable {
    public let id: String
    public let name: String
    public let capabilities: Set<ModuleCapability>

    public init(
        id: String,
        name: String,
        capabilities: Set<ModuleCapability> = []
    ) {
        self.id = id
        self.name = name
        self.capabilities = capabilities
    }
}

public struct ModuleSearchRequest: Equatable, Sendable {
    public let query: String
    public let maximumResults: Int

    public init(query: String, maximumResults: Int = 20) {
        self.query = query
        self.maximumResults = min(max(maximumResults, 1), 100)
    }
}

/// Source-compiled personal modules implement this protocol. The host owns UI,
/// permissions and side effects; a module only computes structured results.
public protocol YToolsModule: Sendable {
    var descriptor: ModuleDescriptor { get }
    func search(_ request: ModuleSearchRequest) async throws -> [LauncherResult]
}
