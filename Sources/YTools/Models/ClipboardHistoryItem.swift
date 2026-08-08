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
    var updatedAt: Date?
    var copyCount: Int

    init(
        id: UUID,
        kind: Kind,
        payload: [String],
        createdAt: Date,
        sourceApplication: String?,
        binaryData: Data? = nil,
        contentHash: String? = nil,
        isPinned: Bool = false,
        updatedAt: Date? = nil,
        copyCount: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.sourceApplication = sourceApplication
        self.binaryData = binaryData
        self.contentHash = contentHash
        self.isPinned = isPinned
        self.updatedAt = updatedAt
        self.copyCount = max(1, copyCount)
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
    var effectiveUpdatedAt: Date { updatedAt ?? createdAt }

    enum CodingKeys: String, CodingKey {
        case id, kind, payload, createdAt, sourceApplication, binaryData, contentHash, isPinned, updatedAt, copyCount
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        payload = try values.decode([String].self, forKey: .payload)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        sourceApplication = try values.decodeIfPresent(String.self, forKey: .sourceApplication)
        binaryData = try values.decodeIfPresent(Data.self, forKey: .binaryData)
        contentHash = try values.decodeIfPresent(String.self, forKey: .contentHash)
        isPinned = try values.decodeIfPresent(Bool.self, forKey: .isPinned)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt)
        copyCount = max(1, try values.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1)
    }
}
