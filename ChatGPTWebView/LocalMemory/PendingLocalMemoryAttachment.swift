import Foundation

struct PendingLocalMemoryPayload {
    let sourceMemoryIDs: [UUID]
    let fileURLs: [URL]
    let composerText: String?
}

enum PendingLocalMemoryAttachment {
    private static let entryIDsKey = "PendingLocalMemoryAttachmentEntryIDs"
    private static let entryIDKey = "PendingLocalMemoryAttachmentEntryID"
    private static let selectedFilePathsKey = "PendingLocalMemoryAttachmentSelectedFilePaths"
    private static let composerTextPathKey = "PendingLocalMemoryAttachmentComposerTextPath"
    private static let injectMarkdownKey = "PendingLocalMemoryAttachmentInjectMarkdown"

    static func mark(
        _ entries: [LocalMemoryEntry],
        fileURLs: [URL] = [],
        composerTextURL: URL? = nil
    ) {
        let defaults = UserDefaults.standard
        defaults.set(entries.map { $0.id.uuidString }, forKey: entryIDsKey)
        defaults.set(fileURLs.map(\.path), forKey: selectedFilePathsKey)
        defaults.set(composerTextURL?.path, forKey: composerTextPathKey)
        defaults.set(composerTextURL != nil, forKey: injectMarkdownKey)
    }

    static func mark(
        _ entry: LocalMemoryEntry,
        fileURLs: [URL] = [],
        composerTextURL: URL? = nil
    ) {
        mark([entry], fileURLs: fileURLs, composerTextURL: composerTextURL)
    }

    static func consumePayload() -> PendingLocalMemoryPayload? {
        let defaults = UserDefaults.standard
        var idTexts = defaults.stringArray(forKey: entryIDsKey) ?? []
        if idTexts.isEmpty, let legacyID = defaults.string(forKey: entryIDKey) {
            idTexts = [legacyID]
        }
        guard !idTexts.isEmpty else { return nil }

        let selectedPaths = defaults.stringArray(forKey: selectedFilePathsKey) ?? []
        let composerTextPath = defaults.string(forKey: composerTextPathKey)
        let shouldInjectMarkdown = defaults.bool(forKey: injectMarkdownKey)
        defaults.removeObject(forKey: entryIDsKey)
        defaults.removeObject(forKey: entryIDKey)
        defaults.removeObject(forKey: selectedFilePathsKey)
        defaults.removeObject(forKey: composerTextPathKey)
        defaults.removeObject(forKey: injectMarkdownKey)

        let selectedIDs = idTexts.compactMap(UUID.init(uuidString:))
        guard let entries = try? LocalMemoryStore().loadEntries() else { return nil }
        let selectedEntries = selectedIDs.compactMap { id in entries.first(where: { $0.id == id }) }
        guard !selectedEntries.isEmpty else { return nil }

        let selectedURLs = selectedPaths.map(URL.init(fileURLWithPath:))
        let composerText: String?
        if let composerTextPath {
            composerText = try? String(contentsOfFile: composerTextPath, encoding: .utf8)
        } else if shouldInjectMarkdown {
            // Compatibility for a pending inline handoff created by ContextPort 2.6 or older.
            composerText = MemoryContextBundleBuilder.composerText(for: selectedEntries)
        } else {
            composerText = nil
        }

        return PendingLocalMemoryPayload(
            sourceMemoryIDs: selectedEntries.map(\.id),
            fileURLs: selectedURLs,
            composerText: composerText
        )
    }

    static func consumeFileURLs() -> [URL] {
        consumePayload()?.fileURLs ?? []
    }
}
