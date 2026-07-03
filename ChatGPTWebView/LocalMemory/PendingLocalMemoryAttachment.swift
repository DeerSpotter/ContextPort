import Foundation

struct PendingLocalMemoryPayload {
    let fileURLs: [URL]
    let composerText: String?
}

enum PendingLocalMemoryAttachment {
    private static let entryIDKey = "PendingLocalMemoryAttachmentEntryID"
    private static let selectedFilePathsKey = "PendingLocalMemoryAttachmentSelectedFilePaths"
    private static let injectMarkdownKey = "PendingLocalMemoryAttachmentInjectMarkdown"

    static func mark(_ entry: LocalMemoryEntry, fileURLs: [URL] = [], injectMarkdown: Bool = false) {
        UserDefaults.standard.set(entry.id.uuidString, forKey: entryIDKey)
        UserDefaults.standard.set(fileURLs.map(\.path), forKey: selectedFilePathsKey)
        UserDefaults.standard.set(injectMarkdown, forKey: injectMarkdownKey)
    }

    static func consumePayload() -> PendingLocalMemoryPayload? {
        guard let idText = UserDefaults.standard.string(forKey: entryIDKey),
              let id = UUID(uuidString: idText) else {
            return nil
        }

        let selectedPaths = UserDefaults.standard.stringArray(forKey: selectedFilePathsKey) ?? []
        let shouldInjectMarkdown = UserDefaults.standard.bool(forKey: injectMarkdownKey)
        UserDefaults.standard.removeObject(forKey: entryIDKey)
        UserDefaults.standard.removeObject(forKey: selectedFilePathsKey)
        UserDefaults.standard.removeObject(forKey: injectMarkdownKey)

        guard let entries = try? LocalMemoryStore().loadEntries(),
              let entry = entries.first(where: { $0.id == id }) else {
            return nil
        }

        let store = LocalMemoryStore()
        let selectedURLs = selectedPaths
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        let composerText: String?
        if shouldInjectMarkdown {
            let markdown = store.markdownText(for: entry) ?? entry.content
            composerText = """
            Continue this saved ChatGPT conversation context. Use the saved context below as project memory. Current instructions override older context.

            \(markdown)
            """
        } else {
            composerText = nil
        }

        return PendingLocalMemoryPayload(
            fileURLs: selectedURLs,
            composerText: composerText
        )
    }

    static func consumeFileURLs() -> [URL] {
        consumePayload()?.fileURLs ?? []
    }
}
