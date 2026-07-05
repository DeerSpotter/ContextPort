import Foundation
import SwiftUI
import WebKit

struct DeveloperWebViewSession {
    let id: String
    let title: String
    let webView: WKWebView
}

private struct DeveloperDiscoveredPage: Decodable {
    let pageURL: String
    let sources: [DeveloperDiscoveredSource]
}

private struct DeveloperDiscoveredSource: Decodable {
    let key: String
    let displayName: String
    let url: String?
    let kind: String
    let inlineSource: String?
}

private struct DeveloperSourceFile: Identifiable {
    let id: String
    let sessionTitle: String
    let pageURL: String
    let displayName: String
    let urlString: String?
    let kind: String
    let content: String?
    let loadError: String?

    var byteCount: Int {
        content?.utf8.count ?? 0
    }
}

private struct DeveloperSourceSearchResult: Identifiable {
    let source: DeveloperSourceFile
    let matchCount: Int
    let snippets: [String]
    let metadataMatched: Bool

    var id: String {
        source.id
    }
}

@MainActor
private final class DeveloperSourcesModel: ObservableObject {
    @Published private(set) var results: [DeveloperSourceSearchResult] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isSearching = false
    @Published private(set) var status = "Open the Dev tab to inspect loaded source files."

    private var sources: [DeveloperSourceFile] = []
    private var scanTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var currentQuery = ""

    func scan(sessions: [DeveloperWebViewSession]) {
        scanTask?.cancel()
        searchTask?.cancel()
        sources.removeAll(keepingCapacity: false)
        results.removeAll(keepingCapacity: false)
        isSearching = false

        guard !sessions.isEmpty else {
            isScanning = false
            status = "No loaded AI browser sessions were found. Open an AI tab, then refresh Sources."
            return
        }

        isScanning = true
        status = "Reading loaded source inventories..."

        scanTask = Task { [weak self] in
            guard let self else { return }

            var collected: [DeveloperSourceFile] = []
            var scannedSessionCount = 0

            for session in sessions {
                guard !Task.isCancelled else { return }

                do {
                    let page = try await Self.discoverSources(in: session.webView)
                    scannedSessionCount += 1

                    let inlineSources = page.sources.compactMap { descriptor -> DeveloperSourceFile? in
                        guard let inlineSource = descriptor.inlineSource else { return nil }

                        return DeveloperSourceFile(
                            id: "\(session.id)::\(descriptor.key)",
                            sessionTitle: session.title,
                            pageURL: page.pageURL,
                            displayName: descriptor.displayName,
                            urlString: descriptor.url,
                            kind: descriptor.kind,
                            content: inlineSource,
                            loadError: nil
                        )
                    }
                    collected.append(contentsOf: inlineSources)

                    let externalDescriptors = page.sources.filter {
                        $0.inlineSource == nil && $0.url != nil
                    }
                    let loadedSources = await loadExternalDeveloperSources(
                        externalDescriptors,
                        sessionID: session.id,
                        sessionTitle: session.title,
                        pageURL: page.pageURL,
                        userAgent: session.webView.customUserAgent
                    )
                    collected.append(contentsOf: loadedSources)
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
                            loadError: error.localizedDescription
                        )
                    )
                }
            }

            guard !Task.isCancelled else { return }

            self.sources = collected.sorted {
                if $0.sessionTitle == $1.sessionTitle {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sessionTitle.localizedCaseInsensitiveCompare($1.sessionTitle) == .orderedAscending
            }
            self.isScanning = false
            self.status = "Indexed \(self.sources.count) sources from \(scannedSessionCount) loaded session\(scannedSessionCount == 1 ? "" : "s")."
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

    func cancel() {
        scanTask?.cancel()
        searchTask?.cancel()
        scanTask = nil
        searchTask = nil
        sources.removeAll(keepingCapacity: false)
        results.removeAll(keepingCapacity: false)
        isScanning = false
        isSearching = false
        status = "Source index released."
    }

    private static func discoverSources(in webView: WKWebView) async throws -> DeveloperDiscoveredPage {
        let script = #"""
        (() => {
            const sources = [];
            const seen = new Set();

            const displayName = (url, fallback) => {
                try {
                    const parsed = new URL(url, document.baseURI);
                    const name = parsed.pathname.split('/').filter(Boolean).pop();
                    return name || fallback || parsed.hostname;
                } catch (_) {
                    return fallback || url;
                }
            };

            const addExternal = (rawURL, kind, fallbackName) => {
                if (!rawURL) return;

                let absoluteURL = rawURL;
                try {
                    absoluteURL = new URL(rawURL, document.baseURI).href;
                } catch (_) {}

                if (seen.has(absoluteURL)) return;
                seen.add(absoluteURL);
                sources.push({
                    key: `external:${absoluteURL}`,
                    displayName: displayName(absoluteURL, fallbackName),
                    url: absoluteURL,
                    kind,
                    inlineSource: null
                });
            };

            Array.from(document.scripts).forEach((script, index) => {
                if (script.src) {
                    addExternal(script.src, 'JavaScript', `Script ${index + 1}`);
                    return;
                }

                const text = script.textContent || '';
                if (!text.trim()) return;

                sources.push({
                    key: `inline-script:${index}`,
                    displayName: `Inline Script ${index + 1}`,
                    url: null,
                    kind: 'Inline JavaScript',
                    inlineSource: text
                });
            });

            Array.from(document.querySelectorAll('link[rel~="stylesheet"][href]')).forEach((link, index) => {
                addExternal(link.href, 'Stylesheet', `Stylesheet ${index + 1}`);
            });

            try {
                performance.getEntriesByType('resource').forEach((entry) => {
                    if (entry.initiatorType === 'script') {
                        addExternal(entry.name, 'JavaScript', 'Loaded Script');
                    } else if (entry.initiatorType === 'link' && /\.css(?:$|\?)/i.test(entry.name)) {
                        addExternal(entry.name, 'Stylesheet', 'Loaded Stylesheet');
                    }
                });
            } catch (_) {}

            return JSON.stringify({
                pageURL: location.href,
                sources
            });
        })();
        """#

        let value = try await webView.evaluateJavaScript(script)
        guard let json = value as? String,
              let data = json.data(using: .utf8) else {
            throw DeveloperSourceScanError.invalidInventory
        }

        return try JSONDecoder().decode(DeveloperDiscoveredPage.self, from: data)
    }
}

private enum DeveloperSourceScanError: LocalizedError {
    case invalidInventory

    var errorDescription: String? {
        switch self {
        case .invalidInventory:
            return "The page did not return a readable source inventory."
        }
    }
}

private enum DeveloperSourceSearchEngine {
    static func search(
        _ sources: [DeveloperSourceFile],
        query: String
    ) -> [DeveloperSourceSearchResult] {
        sources.compactMap { source in
            let metadata = [
                source.sessionTitle,
                source.pageURL,
                source.displayName,
                source.urlString ?? "",
                source.kind,
                source.loadError ?? ""
            ].joined(separator: "\n")

            let metadataMatched = metadata.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil

            var matchCount = 0
            var snippets: [String] = []

            if let content = source.content, !content.isEmpty {
                var searchStart = content.startIndex

                while searchStart < content.endIndex,
                      let range = content.range(
                        of: query,
                        options: [.caseInsensitive, .diacriticInsensitive],
                        range: searchStart..<content.endIndex
                      ) {
                    matchCount += 1

                    if snippets.count < 12 {
                        snippets.append(makeSnippet(content: content, matchRange: range))
                    }

                    guard range.upperBound > searchStart else { break }
                    searchStart = range.upperBound

                    if matchCount >= 10_000 {
                        break
                    }
                }
            }

            guard metadataMatched || matchCount > 0 else { return nil }

            return DeveloperSourceSearchResult(
                source: source,
                matchCount: matchCount,
                snippets: snippets,
                metadataMatched: metadataMatched
            )
        }
        .sorted {
            if $0.matchCount == $1.matchCount {
                return $0.source.displayName.localizedCaseInsensitiveCompare($1.source.displayName) == .orderedAscending
            }
            return $0.matchCount > $1.matchCount
        }
    }

    private static func makeSnippet(content: String, matchRange: Range<String.Index>) -> String {
        let start = content.index(
            matchRange.lowerBound,
            offsetBy: -140,
            limitedBy: content.startIndex
        ) ?? content.startIndex
        let end = content.index(
            matchRange.upperBound,
            offsetBy: 220,
            limitedBy: content.endIndex
        ) ?? content.endIndex

        return String(content[start..<end])
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
    }
}

private func loadExternalDeveloperSources(
    _ descriptors: [DeveloperDiscoveredSource],
    sessionID: String,
    sessionTitle: String,
    pageURL: String,
    userAgent: String?
) async -> [DeveloperSourceFile] {
    guard !descriptors.isEmpty else { return [] }

    let batchSize = 4
    var loaded: [DeveloperSourceFile] = []
    var batchStart = 0

    while batchStart < descriptors.count {
        let batchEnd = min(batchStart + batchSize, descriptors.count)
        let batch = Array(descriptors[batchStart..<batchEnd])

        let batchResults = await withTaskGroup(of: DeveloperSourceFile.self) { group in
            for descriptor in batch {
                group.addTask {
                    await loadExternalDeveloperSource(
                        descriptor,
                        sessionID: sessionID,
                        sessionTitle: sessionTitle,
                        pageURL: pageURL,
                        userAgent: userAgent
                    )
                }
            }

            var results: [DeveloperSourceFile] = []
            for await source in group {
                results.append(source)
            }
            return results
        }

        loaded.append(contentsOf: batchResults)
        batchStart = batchEnd
    }

    return loaded
}

private func loadExternalDeveloperSource(
    _ descriptor: DeveloperDiscoveredSource,
    sessionID: String,
    sessionTitle: String,
    pageURL: String,
    userAgent: String?
) async -> DeveloperSourceFile {
    let sourceID = "\(sessionID)::\(descriptor.key)"

    guard let urlString = descriptor.url,
          let url = URL(string: urlString),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: descriptor.url,
            kind: descriptor.kind,
            content: nil,
            loadError: "This source uses a non-HTTP URL and cannot be loaded by the source reader."
        )
    }

    do {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        if let userAgent, !userAgent.isEmpty {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let maximumSourceBytes = 24 * 1024 * 1024

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DeveloperSourceLoadError.httpStatus(httpResponse.statusCode)
        }

        guard data.count <= maximumSourceBytes else {
            throw DeveloperSourceLoadError.sourceTooLarge(data.count)
        }

        let content = String(decoding: data, as: UTF8.self)
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: urlString,
            kind: descriptor.kind,
            content: content,
            loadError: nil
        )
    } catch {
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: urlString,
            kind: descriptor.kind,
            content: nil,
            loadError: error.localizedDescription
        )
    }
}

private enum DeveloperSourceLoadError: LocalizedError {
    case httpStatus(Int)
    case sourceTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Source request returned HTTP \(statusCode)."
        case .sourceTooLarge(let byteCount):
            return "Source is \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)), above the 24 MB per-source safety limit."
        }
    }
}

struct DeveloperSourcesView: View {
    @EnvironmentObject private var profileSessionPool: ChatGPTProfileSessionPool
    @StateObject private var model = DeveloperSourcesModel()
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        if model.isScanning || model.isSearching {
                            ProgressView()
                        }

                        Text(model.status)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        model.scan(sessions: profileSessionPool.developerSourceSessions())
                    } label: {
                        Label("Refresh Loaded Sources", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning)
                } header: {
                    Text("Source Inspector")
                } footer: {
                    Text("ContextPort indexes scripts and styles from browser sessions already loaded in the app. The index exists only while this Dev tab is open.")
                }

                Section("Sources") {
                    if model.results.isEmpty && !model.isScanning {
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "No sources indexed."
                             : "No source text matched \"\(searchText)\".")
                            .foregroundColor(.secondary)
                    }

                    ForEach(model.results) { result in
                        NavigationLink {
                            DeveloperSourceDetailView(result: result, query: searchText)
                        } label: {
                            DeveloperSourceRow(result: result)
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search loaded source text")
            .onChange(of: searchText) { query in
                model.scheduleSearch(query)
            }
            .task {
                model.scan(sessions: profileSessionPool.developerSourceSessions())
            }
            .onDisappear {
                model.cancel()
            }
        }
    }
}

private struct DeveloperSourceRow: View {
    let result: DeveloperSourceSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.source.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                if result.matchCount > 0 {
                    Text("\(result.matchCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Text("\(result.source.sessionTitle) • \(result.source.kind)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let snippet = result.snippets.first {
                Text(snippet)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(3)
                    .foregroundColor(.secondary)
            } else if let loadError = result.source.loadError {
                Text(loadError)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if result.metadataMatched {
                Text("Matched source name, URL, session, or source type.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DeveloperSourceDetailView: View {
    let result: DeveloperSourceSearchResult
    let query: String

    var body: some View {
        List {
            Section("Source") {
                LabeledContent("Name", value: result.source.displayName)
                LabeledContent("Type", value: result.source.kind)
                LabeledContent("Session", value: result.source.sessionTitle)

                if result.source.byteCount > 0 {
                    LabeledContent(
                        "Indexed Text",
                        value: ByteCountFormatter.string(
                            fromByteCount: Int64(result.source.byteCount),
                            countStyle: .file
                        )
                    )
                }

                if let urlString = result.source.urlString {
                    Text(urlString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if let loadError = result.source.loadError {
                Section("Load Error") {
                    Text(loadError)
                        .textSelection(.enabled)
                }
            }

            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Section("Search") {
                    LabeledContent("Query", value: query)
                    LabeledContent("Matches", value: "\(result.matchCount)")
                }

                if !result.snippets.isEmpty {
                    Section("Match Clues") {
                        ForEach(Array(result.snippets.enumerated()), id: \.offset) { index, snippet in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Match \(index + 1)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(snippet)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .navigationTitle(result.source.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
