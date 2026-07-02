import Foundation

final class LocalMemoryStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let fileManager: FileManager
    private let directoryURL: URL
    private let entriesURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = baseURL.appendingPathComponent("LocalMemoryVault", isDirectory: true)
        self.entriesURL = directoryURL.appendingPathComponent("entries.json")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadEntries() throws -> [LocalMemoryEntry] {
        try ensureDirectory()
        guard fileManager.fileExists(atPath: entriesURL.path) else {
            return []
        }

        let data = try Data(contentsOf: entriesURL)
        guard !data.isEmpty else {
            return []
        }

        return try decoder.decode([LocalMemoryEntry].self, from: data)
            .sorted(by: sortEntries)
    }

    @discardableResult
    func saveEntry(
        projectName: String,
        title: String,
        content: String,
        source: String,
        tags: [String],
        importance: Int
    ) throws -> LocalMemorySaveResult {
        var entries = try loadEntries()
        let now = Date()
        let entry = LocalMemoryEntry(
            projectName: clean(projectName, fallback: "Local Project"),
            title: clean(title, fallback: "Untitled memory"),
            content: clean(content, fallback: ""),
            source: clean(source, fallback: "manual"),
            tags: normalizedTags(tags),
            importance: importance,
            createdAt: now,
            updatedAt: now
        )
        entries.append(entry)
        try writeEntries(entries.sorted(by: sortEntries))
        return LocalMemorySaveResult(
            entry: entry,
            totalCount: entries.count,
            message: "Saved to local device memory."
        )
    }

    func search(_ query: String, limit: Int = 25) throws -> [LocalMemoryEntry] {
        let entries = try loadEntries()
        let terms = query
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !terms.isEmpty else {
            return Array(entries.prefix(limit))
        }

        return entries
            .map { entry in (entry, score(entry, terms: terms)) }
            .filter { $0.1 > 0 }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return sortEntries(lhs.0, rhs.0)
                }
                return lhs.1 > rhs.1
            }
            .prefix(limit)
            .map(\.0)
    }

    func renderProjectContext(projectName: String, limit: Int = 20) throws -> String {
        let entries = try loadEntries()
        let normalizedProject = projectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let projectEntries = entries
            .filter { entry in
                normalizedProject.isEmpty || entry.projectName.lowercased() == normalizedProject
            }
            .prefix(limit)

        var lines: [String] = []
        lines.append("# Local Device Memory Context")
        lines.append("")
        lines.append("Project: \(projectName.isEmpty ? "Local Project" : projectName)")
        lines.append("Generated: \(Self.isoFormatter.string(from: Date()))")
        lines.append("Source: on-device local memory vault")
        lines.append("")
        lines.append("Use this as user-owned context for the next AI session. Treat newer, higher-importance entries as stronger signals, but current user instructions still override this context.")
        lines.append("")

        if projectEntries.isEmpty {
            lines.append("No local memory entries found for this project.")
            return lines.joined(separator: "\n")
        }

        for (index, entry) in projectEntries.enumerated() {
            lines.append("---")
            lines.append("")
            lines.append("## \(index + 1). \(entry.title)")
            lines.append("")
            lines.append("- Source: \(entry.source)")
            lines.append("- Importance: \(entry.importance)/5")
            lines.append("- Created: \(Self.isoFormatter.string(from: entry.createdAt))")
            if !entry.tags.isEmpty {
                lines.append("- Tags: \(entry.tags.joined(separator: ", "))")
            }
            lines.append("")
            lines.append(entry.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func writeEntries(_ entries: [LocalMemoryEntry]) throws {
        try ensureDirectory()
        let data = try encoder.encode(entries)
        try data.write(to: entriesURL, options: [.atomic])
    }

    private func sortEntries(_ lhs: LocalMemoryEntry, _ rhs: LocalMemoryEntry) -> Bool {
        if lhs.importance == rhs.importance {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.importance > rhs.importance
    }

    private func score(_ entry: LocalMemoryEntry, terms: [String]) -> Int {
        let title = entry.title.lowercased()
        let content = entry.content.lowercased()
        let tags = entry.tags.joined(separator: " ").lowercased()
        let source = entry.source.lowercased()
        var score = 0

        for term in terms {
            if title.contains(term) { score += 10 }
            if tags.contains(term) { score += 7 }
            if source.contains(term) { score += 3 }
            if content.contains(term) { score += 2 }
        }

        return score + entry.importance
    }

    private func clean(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func normalizedTags(_ values: [String]) -> [String] {
        var tags = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        if !tags.contains("local") {
            tags.append("local")
        }

        return Array(Set(tags)).sorted()
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
