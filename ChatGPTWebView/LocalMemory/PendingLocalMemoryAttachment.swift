import Foundation

struct PendingLocalMemoryPayload {
    let fileURLs: [URL]
    let composerText: String?
}

enum PendingLocalMemoryAttachment {
    private static let entryIDsKey = "PendingLocalMemoryAttachmentEntryIDs"
    private static let entryIDKey = "PendingLocalMemoryAttachmentEntryID"
    private static let selectedFilePathsKey = "PendingLocalMemoryAttachmentSelectedFilePaths"
    private static let injectMarkdownKey = "PendingLocalMemoryAttachmentInjectMarkdown"

    static func mark(_ entries: [LocalMemoryEntry], fileURLs: [URL] = [], injectMarkdown: Bool = false) {
        UserDefaults.standard.set(entries.map { $0.id.uuidString }, forKey: entryIDsKey)
        UserDefaults.standard.set(fileURLs.map(\.path), forKey: selectedFilePathsKey)
        UserDefaults.standard.set(injectMarkdown, forKey: injectMarkdownKey)
    }

    static func mark(_ entry: LocalMemoryEntry, fileURLs: [URL] = [], injectMarkdown: Bool = false) {
        mark([entry], fileURLs: fileURLs, injectMarkdown: injectMarkdown)
    }

    static func consumePayload() -> PendingLocalMemoryPayload? {
        let defaults = UserDefaults.standard
        var idTexts = defaults.stringArray(forKey: entryIDsKey) ?? []
        if idTexts.isEmpty, let legacyID = defaults.string(forKey: entryIDKey) {
            idTexts = [legacyID]
        }
        guard !idTexts.isEmpty else { return nil }

        let selectedPaths = defaults.stringArray(forKey: selectedFilePathsKey) ?? []
        let shouldInjectMarkdown = defaults.bool(forKey: injectMarkdownKey)
        defaults.removeObject(forKey: entryIDsKey)
        defaults.removeObject(forKey: entryIDKey)
        defaults.removeObject(forKey: selectedFilePathsKey)
        defaults.removeObject(forKey: injectMarkdownKey)

        let selectedIDs = idTexts.compactMap(UUID.init(uuidString:))
        guard let entries = try? LocalMemoryStore().loadEntries() else { return nil }
        let selectedEntries = selectedIDs.compactMap { id in entries.first(where: { $0.id == id }) }
        guard !selectedEntries.isEmpty else { return nil }

        let selectedURLs = selectedPaths.map(URL.init(fileURLWithPath:))
        let composerText = shouldInjectMarkdown
            ? MemoryContextBundleBuilder.composerText(for: selectedEntries)
            : nil

        return PendingLocalMemoryPayload(fileURLs: selectedURLs, composerText: composerText)
    }

    static func consumeFileURLs() -> [URL] {
        consumePayload()?.fileURLs ?? []
    }
}
