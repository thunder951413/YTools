import Foundation

struct RecentDocumentItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let path: String
    var lastOpenedAt: Date

    var url: URL { URL(fileURLWithPath: path) }
}
