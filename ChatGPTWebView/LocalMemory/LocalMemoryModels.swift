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

    init(
        id: UUID = UUID(),
        projectName: String,
        title: String,
        content: String,
        source: String,
        tags: [String],
        importance: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
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
    }
}

struct LocalMemorySaveResult: Sendable, Hashable {
    let entry: LocalMemoryEntry
    let totalCount: Int
    let message: String
}
