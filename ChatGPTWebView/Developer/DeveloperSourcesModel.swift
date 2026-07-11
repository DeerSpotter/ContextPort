import Foundation
import SwiftUI
import WebKit

struct DeveloperWebViewSession {
    let id: String
    let title: String
    let webView: WKWebView
}

struct DeveloperDiscoveredPage: Decodable, Sendable {
    let pageURL: String
    let sources: [DeveloperDiscoveredSource]
}

struct DeveloperDiscoveredSource: Decodable, Sendable {
    let key: String
    let displayName: String
    let url: String?
    let kind: String
    let inlineSource: String?
    let inlineSourceIndex: Int?
    let inlineSourceCharacterCount: Int?

    init(
        key: String,
        displayName: String,
        url: String?,
        kind: String,
        inlineSource: String?,
        inlineSourceIndex: Int? = nil,
        inlineSourceCharacterCount: Int? = nil
    ) {
        self.key = key
        self.displayName = displayName
        self.url = url
        self.kind = kind
        self.inlineSource = inlineSource
        self.inlineSourceIndex = inlineSourceIndex
        self.inlineSourceCharacterCount = inlineSourceCharacterCount
    }
}

struct DeveloperSourceFile: Identifiable, Sendable {
    let id: String
    let sessionTitle: String
    let pageURL: String
    let displayName: String
    let urlString: String?
    let kind: String
    let content: String?
    let metadataNote: String?
    let resourceByteCount: Int?
    let loadError: String?

    var byteCount: Int {
        content?.utf8.count ?? resourceByteCount ?? 0
    }
}

struct DeveloperSourceSearchResult: Identifiable, Sendable {
    let source: DeveloperSourceFile
    let matchCount: Int
    let snippets: [String]
    let metadataMatched: Bool

    var id: String {
        source.id
    }
}

struct DeveloperSourceSecondPassInventory: Sendable {
    let externalDescriptors: [DeveloperDiscoveredSource]
    let inlineFiles: [DeveloperSourceFile]
}

@MainActor
final class DeveloperSourcesModel: ObservableObject {
    @Published private(set) var results: [DeveloperSourceSearchResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isSearching = false
    @Published private(set) var status = "Open the Dev tab to inspect loaded source files."
    @Published private(set) var snapshotFingerprint: String?

    private var sources: [DeveloperSourceFile] = []
    private var scanTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var currentQuery = ""

    var hasSources: Bool {
        !sources.isEmpty
    }

    func archiveSnapshot() -> [DeveloperSourceArchiveItem] {
        sources.map { source in
            DeveloperSourceArchiveItem(
                id: source.id,
                sessionTitle: source.sessionTitle,
                pageURL: source.pageURL,
                displayName: source.displayName,
                urlString: source.urlString,
                kind: source.kind,
                content: source.content,
                metadataNote: source.metadataNote,
                resourceByteCount: source.resourceByteCount,
                loadError: source.loadError
            )
        }
    }

    func scanIfNeeded(sessions: [DeveloperWebViewSession]) {
        guard sources.isEmpty, !isScanning else { return }
        scan(sessions: sessions)
    }

    func scan(sessions: [DeveloperWebViewSession]) {
        scanTask?.cancel()
        searchTask?.cancel()
        sources.removeAll(keepingCapacity: false)
        results.removeAll(keepingCapacity: false)
        snapshotFingerprint = nil
        isSearching = false

        guard !sessions.isEmpty else {
            isScanning = false
            status = "No loaded AI browser sessions were found. Open an AI tab, then refresh Sources."
            return
        }

        isScanning = true
        status = "Reading first-pass source inventories..."

        scanTask = Task { [weak self] in
            guard let self else { return }

            await DeveloperSourceResponseMetadataRegistry.shared.clear()

            var collected: [DeveloperSourceFile] = []
            var scannedSessionCount = 0
            var firstPassCount = 0
            var secondPassCount = 0
            var nestedPassCount = 0
            var validatedSourceMapCount = 0
            var originalSourceCount = 0

            for session in sessions {
                guard !Task.isCancelled else { return }

                do {
                    let cookieHeader = await developerCookieHeader(for: session.webView)
                    let firstPage = try await discoverDeveloperSources(in: session.webView)
                    scannedSessionCount += 1

                    let firstExternalDescriptors = firstPage.sources.filter {
                        $0.inlineSourceIndex == nil && $0.inlineSource == nil && $0.url != nil
                    }
                    let firstExternal = await loadExternalDeveloperSources(
                        firstExternalDescriptors,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        pageURL: firstPage.pageURL,
                        userAgent: session.webView.customUserAgent,
                        cookieHeader: cookieHeader
                    )
                    collected.append(contentsOf: firstExternal)

                    guard !Task.isCancelled else { return }
                    self.status = "Reading inline sources in bounded chunks..."

                    let firstInline = await loadDeveloperInlineSourceFiles(
                        from: firstPage.sources,
                        session: session,
                        pageURL: firstPage.pageURL
                    )
                    collected.append(contentsOf: firstInline)

                    let firstPassSessionFiles = firstExternal + firstInline
                    firstPassCount += firstPassSessionFiles.count

                    guard !Task.isCancelled else { return }
                    self.status = "Reconciling runtime and referenced sources..."

                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let latePage = try? await discoverDeveloperSources(in: session.webView)
                    let secondInventory = DeveloperSourceSecondPassScanner.discover(
                        firstPage: firstPage,
                        latePage: latePage,
                        firstPassFiles: firstPassSessionFiles,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        pageURL: firstPage.pageURL
                    )

                    collected.append(contentsOf: secondInventory.inlineFiles)
                    let secondExternal = await loadExternalDeveloperSources(
                        secondInventory.externalDescriptors,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        pageURL: firstPage.pageURL,
                        userAgent: session.webView.customUserAgent,
                        cookieHeader: cookieHeader
                    )
                    collected.append(contentsOf: secondExternal)
                    secondPassCount += secondInventory.inlineFiles.count + secondExternal.count

                    guard !Task.isCancelled else { return }
                    self.status = "Reconciling nested bundler dependencies..."

                    let nestedDescriptors = DeveloperSourceNestedPassScanner.discover(
                        firstPassFiles: firstPassSessionFiles,
                        secondPassFiles: secondExternal,
                        existingFiles: firstPassSessionFiles + secondInventory.inlineFiles + secondExternal
                    )
                    let nestedExternal = await loadExternalDeveloperSources(
                        nestedDescriptors,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        pageURL: firstPage.pageURL,
                        userAgent: session.webView.customUserAgent,
                        cookieHeader: cookieHeader
                    )
                    collected.append(contentsOf: nestedExternal)
                    nestedPassCount += nestedExternal.count

                    guard !Task.isCancelled else { return }
                    self.status = "Recovering validated SourceMaps and original sources..."

                    let sourceMapInputs = firstPassSessionFiles
                        + secondInventory.inlineFiles
                        + secondExternal
                        + nestedExternal
                    let sourceMapRecovery = await DeveloperSourceMapRecovery.recover(
                        from: sourceMapInputs,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        pageURL: firstPage.pageURL,
                        userAgent: session.webView.customUserAgent,
                        cookieHeader: cookieHeader
                    )
                    collected.append(contentsOf: sourceMapRecovery.mapFiles)
                    collected.append(contentsOf: sourceMapRecovery.originalSourceFiles)
                    validatedSourceMapCount += sourceMapRecovery.mapFiles.count
                    originalSourceCount += sourceMapRecovery.originalSourceFiles.count
                } catch {
                    collected.append(
                        DeveloperSourceFile(
                            id: "\(session.id)::scan-error",
                            sessionTitle: session.title,
                            pageURL: session.webView.url?.absoluteString ?? "",
                            displayName: "Source inventory unavailable",
                            urlString: nil,
                            kind: "Scan Error",
                            content: nil,
                            metadataNote: nil,
                            resourceByteCount: nil,
                            loadError: error.localizedDescription
                        )
                    )
                }
            }

            guard !Task.isCancelled else { return }

            let preferredForDeduplication = collected.sorted {
                sourcePreference($0) > sourcePreference($1)
            }
            self.sources = DeveloperSourceSecondPassScanner.deduplicate(preferredForDeduplication).sorted {
                if $0.sessionTitle == $1.sessionTitle {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sessionTitle.localizedCaseInsensitiveCompare($1.sessionTitle) == .orderedAscending
            }
            self.snapshotFingerprint = DeveloperSourceMemoryArchiveBuilder.fingerprint(
                for: self.archiveSnapshot()
            )
            self.isScanning = false
            self.status = "Indexed \(self.sources.count) sources from \(scannedSessionCount) loaded session\(scannedSessionCount == 1 ? "" : "s") • \(firstPassCount) first pass • \(secondPassCount) second pass • \(nestedPassCount) nested dependencies • \(validatedSourceMapCount) validated SourceMaps • \(originalSourceCount) original sources. Kept until ContextPort closes."
            self.scheduleSearch(self.currentQuery)
        }
    }

    func scheduleSearch(_ query: String) {
        currentQuery = query
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = sources

        guard !trimmedQuery.isEmpty else {
            isSearching = false
            results = snapshot.map {
                DeveloperSourceSearchResult(
                    source: $0,
                    matchCount: 0,
                    snippets: [],
                    metadataMatched: false
                )
            }
            return
        }

        isSearching = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }

            let searchedResults = await Task.detached(priority: .utility) {
                DeveloperSourceSearchEngine.search(snapshot, query: trimmedQuery)
            }.value

            guard !Task.isCancelled, let self else { return }
            self.results = searchedResults
            self.isSearching = false
        }
    }

    private func sourcePreference(_ source: DeveloperSourceFile) -> Int {
        if source.kind == "Source Map • Validated v3" { return 300 }
        if source.kind == "Original Source • Embedded SourceMap" { return 250 }
        if source.loadError == nil { return 100 }
        return 0
    }
}
