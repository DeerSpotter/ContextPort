import Foundation

struct LocalMemoryEntry: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    var projectName: String
    var title: String
    var content: String
    var source: String
    var tags: [String]
    var importance: Int
    var createdAt: Date
    var updatedAt: Date
    var pdfFilename: String?
    var markdownFilename: String?
    var messageCount: Int?
    var exportedAt: String?
    var attachmentFilenames: [String]

    init(
        id: UUID = UUID(),
        projectName: String,
        title: String,
        content: String,
        source: String,
        tags: [String],
        importance: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pdfFilename: String? = nil,
        markdownFilename: String? = nil,
        messageCount: Int? = nil,
        exportedAt: String? = nil,
        attachmentFilenames: [String] = []
    ) {
        self.id = id
        self.projectName = projectName
        self.title = title
        self.content = content
        self.source = source
        self.tags = tags
        self.importance = min(max(importance, 1), 5)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pdfFilename = pdfFilename
        self.markdownFilename = markdownFilename
        self.messageCount = messageCount
        self.exportedAt = exportedAt
        self.attachmentFilenames = attachmentFilenames
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.projectName = try container.decode(String.self, forKey: .projectName)
        self.title = try container.decode(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.source = try container.decode(String.self, forKey: .source)
        self.tags = try container.decode([String].self, forKey: .tags)
        self.importance = try container.decode(Int.self, forKey: .importance)
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        self.pdfFilename = try container.decodeIfPresent(String.self, forKey: .pdfFilename)
        self.markdownFilename = try container.decodeIfPresent(String.self, forKey: .markdownFilename)
        self.messageCount = try container.decodeIfPresent(Int.self, forKey: .messageCount)
        self.exportedAt = try container.decodeIfPresent(String.self, forKey: .exportedAt)
        self.attachmentFilenames = try container.decodeIfPresent([String].self, forKey: .attachmentFilenames) ?? []
    }
}

struct LocalMemorySaveResult: Sendable, Hashable {
    let entry: LocalMemoryEntry
    let totalCount: Int
    let message: String
}
