import Foundation
import PDFKit

enum MemoryContextBundleError: LocalizedError {
    case emptySelection
    case couldNotBuildPDF

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select at least one saved Memory."
        case .couldNotBuildPDF:
            return "The selected memories could not be combined into a PDF context bundle."
        }
    }
}

struct MemoryContextBundle {
    let fileURLs: [URL]
    let selectedCount: Int
    let format: MemorySharingFormat

    func statusMessage(for providerName: String) -> String {
        let entryVerb = selectedCount == 1 ? "entry is" : "entries are"
        if format.injectsMarkdownText {
            return "\(selectedCount) Memory \(entryVerb) ready for \(providerName). Tap Paste Context to insert the combined context."
        }

        let names = fileURLs.map(\.lastPathComponent).joined(separator: ", ")
        return "\(selectedCount) Memory \(entryVerb) ready for \(providerName): \(names)."
    }
}

final class MemoryContextBundleBuilder {
    private let fileManager: FileManager
    private let store: LocalMemoryStore
    private let bundleRoot: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.store = LocalMemoryStore(fileManager: fileManager)
        self.bundleRoot = fileManager.temporaryDirectory
            .appendingPathComponent("ContextPortContextBundles", isDirectory: true)
    }

    func build(entries: [LocalMemoryEntry], format: MemorySharingFormat) throws -> MemoryContextBundle {
        guard !entries.isEmpty else {
            throw MemoryContextBundleError.emptySelection
        }

        try resetBundleRoot()
        let outputFolder = bundleRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let markdownText = Self.combinedMarkdown(for: entries, store: store)
        var fileURLs: [URL] = []

        if format.includesPDF {
            let pdfURL = outputFolder.appendingPathComponent("ContextPort Context.pdf")
            try buildCombinedPDF(entries: entries, combinedMarkdown: markdownText, to: pdfURL)
            fileURLs.append(pdfURL)
        }

        if format.includesMarkdownFile {
            let markdownURL = outputFolder.appendingPathComponent("ContextPort Context.md")
            try markdownText.write(to: markdownURL, atomically: true, encoding: .utf8)
            fileURLs.append(markdownURL)
        }

        return MemoryContextBundle(
            fileURLs: fileURLs,
            selectedCount: entries.count,
            format: format
        )
    }

    static func composerText(for entries: [LocalMemoryEntry]) -> String {
        let store = LocalMemoryStore()
        let markdown = combinedMarkdown(for: entries, store: store)
        return """
        Continue using the selected ContextPort memories below as project memory. Treat them as historical context. Current instructions override older context.

        \(markdown)
        """
    }

    private static func combinedMarkdown(for entries: [LocalMemoryEntry], store: LocalMemoryStore) -> String {
        let formatter = ISO8601DateFormatter()
        let sections = entries.enumerated().map { index, entry in
            let revisionSections = entry.orderedRevisions.map { revision in
                let markdown = store.markdownText(for: revision, in: entry)
                    ?? "_Revision content is unavailable on this device._"
                let messageLine = revision.messageCount.map { "Messages: \($0)" } ?? "Messages: unknown"
                return """
                ## Revision \(revision.number)

                Source: \(revision.source)
                Saved: \(formatter.string(from: revision.createdAt))
                \(messageLine)

                \(markdown)
                """
            }

            return """
            # Memory \(index + 1): \(entry.title)

            Project: \(entry.projectName)
            Created: \(formatter.string(from: entry.createdAt))
            Updated: \(formatter.string(from: entry.updatedAt))
            Revisions: \(entry.revisionCount)

            \(revisionSections.joined(separator: "\n\n---\n\n"))
            """
        }

        return """
        # ContextPort Context Bundle

        Selected Memories: \(entries.count)
        Generated: \(formatter.string(from: Date()))

        Current instructions override older context. Treat the selected memories and their ordered revisions as historical project context unless the user explicitly says otherwise.

        ---

        \(sections.joined(separator: "\n\n---\n\n"))
        """
    }

    private func buildCombinedPDF(
        entries: [LocalMemoryEntry],
        combinedMarkdown: String,
        to destination: URL
    ) throws {
        let output = PDFDocument()

        for entry in entries {
            for revision in entry.orderedRevisions {
                if let sourceURL = store.pdfURL(for: revision),
                   let sourceDocument = PDFDocument(url: sourceURL) {
                    appendPages(from: sourceDocument, to: output)
                    continue
                }

                guard let markdown = store.markdownText(for: revision, in: entry) else {
                    continue
                }

                let fallbackURL = bundleRoot.appendingPathComponent("fallback-\(revision.id.uuidString).pdf")
                let fallbackEntry = LocalMemoryEntry(
                    projectName: entry.projectName,
                    title: "\(entry.title) · Revision \(revision.number)",
                    content: markdown,
                    source: revision.source,
                    tags: entry.tags,
                    importance: entry.importance,
                    createdAt: revision.createdAt,
                    updatedAt: revision.createdAt,
                    messageCount: revision.messageCount,
                    exportedAt: revision.exportedAt
                )
                try LocalMemoryPDFRenderer.render(entry: fallbackEntry, to: fallbackURL)
                if let fallbackDocument = PDFDocument(url: fallbackURL) {
                    appendPages(from: fallbackDocument, to: output)
                }
                try? fileManager.removeItem(at: fallbackURL)
            }
        }

        if output.pageCount == 0 {
            let fallbackEntry = LocalMemoryEntry(
                projectName: "ContextPort",
                title: "ContextPort Context Bundle",
                content: combinedMarkdown,
                source: "contextport-memory-bundle",
                tags: ["context", "memory", "bundle"],
                importance: 5
            )
            try LocalMemoryPDFRenderer.render(entry: fallbackEntry, to: destination)
            return
        }

        guard output.write(to: destination) else {
            throw MemoryContextBundleError.couldNotBuildPDF
        }
    }

    private func appendPages(from source: PDFDocument, to output: PDFDocument) {
        for index in 0..<source.pageCount {
            guard let page = source.page(at: index),
                  let pageCopy = page.copy() as? PDFPage else {
                continue
            }
            output.insert(pageCopy, at: output.pageCount)
        }
    }

    private func resetBundleRoot() throws {
        if fileManager.fileExists(atPath: bundleRoot.path) {
            try fileManager.removeItem(at: bundleRoot)
        }
        try fileManager.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
    }
}
