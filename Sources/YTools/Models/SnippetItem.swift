import Foundation

struct SnippetItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var keyword: String
    var content: String
    var collection: String
    let createdAt: Date
    var updatedAt: Date
}
