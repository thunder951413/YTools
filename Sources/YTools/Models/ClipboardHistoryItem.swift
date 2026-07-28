import Foundation

struct ClipboardHistoryItem: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case text
        case files
        case image
    }

    let id: UUID
    let kind: Kind
    let payload: [String]
    let createdAt: Date
    let sourceApplication: String?
    let binaryData: Data?
    let contentHash: String?
    var isPinned: Bool?
    var useCount: Int?

    init(
        id: UUID,
        kind: Kind,
        payload: [String],
        createdAt: Date,
        sourceApplication: String?,
        binaryData: Data? = nil,
        contentHash: String? = nil,
        isPinned: Bool = false,
        useCount: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.sourceApplication = sourceApplication
        self.binaryData = binaryData
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.useCount = useCount
    }

    var displayText: String {
        switch kind {
        case .text:
            return payload.first ?? ""
        case .files:
            return payload
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                .joined(separator: ", ")
        case .image:
            return payload.first ?? "图片"
        }
    }

    func hasSameContent(as other: ClipboardHistoryItem) -> Bool {
        if let contentHash, let otherHash = other.contentHash { return contentHash == otherHash }
        return kind == other.kind && payload == other.payload && binaryData == other.binaryData
    }

    var pinned: Bool { isPinned == true }
    var usageCount: Int { max(0, useCount ?? 0) }
}
