import Foundation
import SwiftUI
import UIKit
import WebKit

struct DeveloperWebViewSession {
    let id: String
    let title: String
    let webView: WKWebView
}

private struct DeveloperDiscoveredPage: Decodable, Sendable {
    let pageURL: String
    let sources: [DeveloperDiscoveredSource]
}

private struct DeveloperDiscoveredSource: Decodable, Sendable {
    let key: String
    let displayName: String
    let url: String?
    let kind: String
    let inlineSource: String?
}

private struct DeveloperSourceFile: Identifiable, Sendable {
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

private struct DeveloperSourceSearchResult: Identifiable, Sendable {
    let source: DeveloperSourceFile
    let matchCount: Int
    let snippets: [String]
    let metadataMatched: Bool

    var id: String {
        source.id
    }
}

private struct DeveloperSourceSecondPassInventory: Sendable {
    let externalDescriptors: [DeveloperDiscoveredSource]
    let inlineFiles: [DeveloperSourceFile]
}

@MainActor
private final class DeveloperSourcesModel: ObservableObject {
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

            var collected: [DeveloperSourceFile] = []
            var scannedSessionCount = 0
            var firstPassCount = 0
            var secondPassCount = 0

            for session in sessions {
                guard !Task.isCancelled else { return }

                do {
                    let cookieHeader = await developerCookieHeader(for: session.webView)
                    let firstPage = try await Self.discoverSources(in: session.webView)
                    scannedSessionCount += 1

                    let firstInline = Self.inlineFiles(
                        from: firstPage.sources,
                        session: session,
                        pageURL: firstPage.pageURL
                    )
                    collected.append(contentsOf: firstInline)

                    let firstExternalDescriptors = firstPage.sources.filter {
                        $0.inlineSource == nil && $0.url != nil
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

                    let firstPassSessionFiles = firstInline + firstExternal
                    firstPassCount += firstPassSessionFiles.count

                    guard !Task.isCancelled else { return }
                    self.status = "Reconciling runtime and referenced sources..."

                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let latePage = try? await Self.discoverSources(in: session.webView)
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

            self.sources = DeveloperSourceSecondPassScanner.deduplicate(collected).sorted {
                if $0.sessionTitle == $1.sessionTitle {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.sessionTitle.localizedCaseInsensitiveCompare($1.sessionTitle) == .orderedAscending
            }
            self.snapshotFingerprint = DeveloperSourceMemoryArchiveBuilder.fingerprint(
                for: self.archiveSnapshot()
            )
            self.isScanning = false
            self.status = "Indexed \(self.sources.count) sources from \(scannedSessionCount) loaded session\(scannedSessionCount == 1 ? "" : "s") • \(firstPassCount) first pass • \(secondPassCount) second pass. Kept until ContextPort closes."
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

    private static func inlineFiles(
        from descriptors: [DeveloperDiscoveredSource],
        session: DeveloperWebViewSession,
        pageURL: String
    ) -> [DeveloperSourceFile] {
        descriptors.compactMap { descriptor -> DeveloperSourceFile? in
            guard let inlineSource = descriptor.inlineSource else { return nil }

            return DeveloperSourceFile(
                id: "\(session.id)::\(descriptor.key)",
                sessionTitle: session.title,
                pageURL: pageURL,
                displayName: descriptor.displayName,
                urlString: descriptor.url,
                kind: descriptor.kind,
                content: inlineSource,
                loadError: nil
            )
        }
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

            const classifyResource = (url, initiatorType) => {
                const clean = String(url || '').split('#')[0].toLowerCase();
                if (/\.css(?:$|\?)/i.test(clean)) return 'Stylesheet';
                if (/\.map(?:$|\?)/i.test(clean)) return 'Source Map';
                if (/\.wasm(?:$|\?)/i.test(clean)) return 'WebAssembly Binary';
                if (initiatorType === 'worker') return 'Worker JavaScript';
                if (initiatorType === 'script') return 'JavaScript';
                return 'Runtime Resource';
            };

            const addExternal = (rawURL, kind, fallbackName) => {
                if (!rawURL) return;

                let absoluteURL = rawURL;
                try {
                    absoluteURL = new URL(rawURL, document.baseURI).href;
                } catch (_) {}

                if (!/^https?:/i.test(absoluteURL) || seen.has(absoluteURL)) return;
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

            Array.from(document.querySelectorAll('link[href]')).forEach((link, index) => {
                const rel = String(link.rel || '').toLowerCase();
                const as = String(link.as || '').toLowerCase();
                const href = link.href;
                if (!href) return;

                if (rel.split(/\s+/).includes('stylesheet')) {
                    addExternal(href, 'Stylesheet', `Stylesheet ${index + 1}`);
                } else if (rel.split(/\s+/).includes('modulepreload')) {
                    addExternal(href, 'JavaScript Module Preload', `Module Preload ${index + 1}`);
                } else if (rel.split(/\s+/).includes('preload') && ['script', 'style', 'worker'].includes(as)) {
                    addExternal(href, classifyResource(href, as), `Preload ${index + 1}`);
                }
            });

            try {
                performance.getEntriesByType('resource').forEach((entry) => {
                    const type = String(entry.initiatorType || '').toLowerCase();
                    const supportedType = ['script', 'link', 'worker'].includes(type);
                    const supportedExtension = /\.(?:m?js|cjs|css|map|wasm)(?:$|\?)/i.test(entry.name || '');
                    if (supportedType || supportedExtension) {
                        addExternal(entry.name, classifyResource(entry.name, type), 'Runtime Resource');
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

private enum DeveloperSourceSecondPassScanner {
    private static let maximumSecondPassExternalSources = 512
    private static let maximumInlineDataSources = 64
    private static let maximumDataSourceBytes = 24 * 1024 * 1024

    private struct Candidate {
        let rawReference: String
        let kind: String
        let parentSourceID: String
        let baseURL: URL?
    }

    static func discover(
        firstPage: DeveloperDiscoveredPage,
        latePage: DeveloperDiscoveredPage?,
        firstPassFiles: [DeveloperSourceFile],
        sessionID: String,
        sessionTitle: String,
        pageURL: String
    ) -> DeveloperSourceSecondPassInventory {
        var seenURLs = Set(
            firstPage.sources.compactMap(\.url).compactMap(canonicalURLString)
        )
        var descriptors: [DeveloperDiscoveredSource] = []
        var inlineFiles: [DeveloperSourceFile] = []

        if let latePage {
            for descriptor in latePage.sources where descriptor.inlineSource == nil {
                guard descriptors.count < maximumSecondPassExternalSources,
                      let urlString = descriptor.url,
                      let canonical = canonicalURLString(urlString),
                      !seenURLs.contains(canonical) else {
                    continue
                }

                seenURLs.insert(canonical)
                descriptors.append(
                    DeveloperDiscoveredSource(
                        key: "second-pass:runtime:\(canonical)",
                        displayName: descriptor.displayName,
                        url: canonical,
                        kind: "Second Pass • Late \(descriptor.kind)",
                        inlineSource: nil
                    )
                )
            }
        }

        for file in firstPassFiles {
            guard descriptors.count < maximumSecondPassExternalSources,
                  let content = file.content,
                  !content.isEmpty else {
                continue
            }

            let candidates = referenceCandidates(in: content, source: file)
            for (index, candidate) in candidates.enumerated() {
                if candidate.rawReference.lowercased().hasPrefix("data:") {
                    guard inlineFiles.count < maximumInlineDataSources,
                          let decoded = decodeInlineDataReference(candidate.rawReference) else {
                        continue
                    }

                    inlineFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::second-pass:inline:\(candidate.parentSourceID):\(index)",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: "Inline Source Map \(inlineFiles.count + 1)",
                            urlString: "data:source-map",
                            kind: "Second Pass • Inline Source Map",
                            content: decoded,
                            loadError: nil
                        )
                    )
                    continue
                }

                guard descriptors.count < maximumSecondPassExternalSources,
                      let resolved = resolveReference(candidate.rawReference, relativeTo: candidate.baseURL),
                      let canonical = canonicalURLString(resolved.absoluteString),
                      !seenURLs.contains(canonical),
                      isSourceLikeURL(resolved) else {
                    continue
                }

                seenURLs.insert(canonical)
                descriptors.append(
                    DeveloperDiscoveredSource(
                        key: "second-pass:reference:\(canonical)",
                        displayName: displayName(for: resolved, fallback: "Referenced Source"),
                        url: canonical,
                        kind: "Second Pass • \(candidate.kind)",
                        inlineSource: nil
                    )
                )
            }
        }

        return DeveloperSourceSecondPassInventory(
            externalDescriptors: descriptors,
            inlineFiles: inlineFiles
        )
    }

    static func deduplicate(_ files: [DeveloperSourceFile]) -> [DeveloperSourceFile] {
        var seenIDs = Set<String>()
        var seenURLSessionPairs = Set<String>()
        var result: [DeveloperSourceFile] = []

        for file in files {
            guard !seenIDs.contains(file.id) else { continue }

            if let urlString = file.urlString,
               let canonical = canonicalURLString(urlString),
               !urlString.lowercased().hasPrefix("data:") {
                let pair = "\(file.sessionTitle)\u{1F}\(canonical)"
                guard !seenURLSessionPairs.contains(pair) else { continue }
                seenURLSessionPairs.insert(pair)
            }

            seenIDs.insert(file.id)
            result.append(file)
        }

        return result
    }

    private static func referenceCandidates(
        in content: String,
        source: DeveloperSourceFile
    ) -> [Candidate] {
        let baseURL = source.urlString.flatMap(URL.init(string:))
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        var candidates: [Candidate] = []
        var seen = Set<String>()

        let patterns: [(String, String)] = [
            (#"sourceMappingURL\s*=\s*([^\s*]+)"#, "Source Map"),
            (#"new\s+(?:Shared)?Worker\s*\(\s*[\"']([^\"']+)[\"']"#, "Worker JavaScript"),
            (#"importScripts\s*\(\s*[\"']([^\"']+)[\"']"#, "Imported Worker Script"),
            (#"import\s*\(\s*[\"']([^\"']+)[\"']\s*\)"#, "Dynamic JavaScript"),
            (#"(?:import|export)\s+(?:[^\"']*?\s+from\s+)?[\"']([^\"']+)[\"']"#, "Module JavaScript"),
            (#"[\"']([^\"']+\.(?:m?js|cjs|css|map|wasm)(?:\?[^\"']*)?)[\"']"#, "Referenced Source")
        ]

        for (pattern, kind) in patterns {
            guard candidates.count < 2_048,
                  let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            regex.enumerateMatches(in: content, options: [], range: fullRange) { match, _, stop in
                guard let match,
                      match.numberOfRanges > 1,
                      candidates.count < 2_048 else {
                    if candidates.count >= 2_048 {
                        stop.pointee = true
                    }
                    return
                }

                let range = match.range(at: 1)
                guard range.location != NSNotFound else { return }

                let raw = nsContent.substring(with: range)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
                guard !raw.isEmpty else { return }

                let key = "\(kind)\u{1F}\(raw)"
                guard !seen.contains(key) else { return }
                seen.insert(key)
                candidates.append(
                    Candidate(
                        rawReference: raw,
                        kind: kind,
                        parentSourceID: source.id,
                        baseURL: baseURL
                    )
                )
            }
        }

        return candidates
    }

    private static func resolveReference(_ raw: String, relativeTo baseURL: URL?) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.hasPrefix("#"),
              !trimmed.lowercased().hasPrefix("blob:"),
              !trimmed.lowercased().hasPrefix("javascript:") else {
            return nil
        }

        if let absolute = URL(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return absolute
        }

        guard let baseURL else { return nil }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func isSourceLikeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let path = url.path.lowercased()
        return [".js", ".mjs", ".cjs", ".css", ".map", ".wasm"].contains {
            path.hasSuffix($0)
        }
    }

    private static func canonicalURLString(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func displayName(for url: URL, fallback: String) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? fallback : name
    }

    private static func decodeInlineDataReference(_ raw: String) -> String? {
        guard raw.lowercased().hasPrefix("data:"),
              let comma = raw.firstIndex(of: ",") else {
            return nil
        }

        let metadata = String(raw[raw.index(raw.startIndex, offsetBy: 5)..<comma]).lowercased()
        guard metadata.contains("json") || metadata.contains("javascript") || metadata.contains("text") else {
            return nil
        }

        let payload = String(raw[raw.index(after: comma)...])
        let data: Data?
        if metadata.contains(";base64") {
            data = Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
        } else {
            data = payload.removingPercentEncoding?.data(using: .utf8)
        }

        guard let data,
              data.count <= maximumDataSourceBytes else {
            return nil
        }

        return String(data: data, encoding: .utf8)
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

private func developerCookieHeader(for webView: WKWebView) async -> String? {
    let cookies = await withCheckedContinuation { continuation in
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            continuation.resume(returning: cookies)
        }
    }

    guard !cookies.isEmpty else { return nil }
    return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
}

private func loadExternalDeveloperSources(
    _ descriptors: [DeveloperDiscoveredSource],
    sessionID: String,
    sessionTitle: String,
    pageURL: String,
    userAgent: String?,
    cookieHeader: String?
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
                        userAgent: userAgent,
                        cookieHeader: cookieHeader
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
    userAgent: String?,
    cookieHeader: String?
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
        if let cookieHeader, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.setValue(pageURL, forHTTPHeaderField: "Referer")

        let (data, response) = try await URLSession.shared.data(for: request)
        let maximumSourceBytes = 24 * 1024 * 1024

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DeveloperSourceLoadError.httpStatus(httpResponse.statusCode)
        }

        guard data.count <= maximumSourceBytes else {
            throw DeveloperSourceLoadError.sourceTooLarge(data.count)
        }

        let mimeType = response.mimeType?.lowercased() ?? ""
        if url.pathExtension.lowercased() == "wasm" || mimeType == "application/wasm" {
            throw DeveloperSourceLoadError.binaryResource(data.count)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw DeveloperSourceLoadError.notUTF8
        }

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
    case binaryResource(Int)
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Source request returned HTTP \(statusCode)."
        case .sourceTooLarge(let byteCount):
            return "Source is \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)), above the 24 MB per-source safety limit."
        case .binaryResource(let byteCount):
            return "Binary WebAssembly resource discovered (\(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file))). Recorded in the manifest but not decoded as source text."
        case .notUTF8:
            return "Source response is not valid UTF-8 text and was recorded without indexed content."
        }
    }
}

struct DeveloperSourcesView: View {
    let isActive: Bool

    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var profileSessionPool: ChatGPTProfileSessionPool
    @StateObject private var model = DeveloperSourcesModel()
    @State private var searchText = ""
    @State private var isSavingToMemory = false
    @State private var lastSavedSnapshotFingerprint: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        if model.isScanning || model.isSearching || isSavingToMemory {
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
                    .disabled(model.isScanning || isSavingToMemory)

                    Button {
                        saveSourcesToMemory()
                    } label: {
                        Label(
                            isCurrentSnapshotSaved ? "Saved to Memory" : "Save Sources to Memory",
                            systemImage: isCurrentSnapshotSaved ? "checkmark.circle.fill" : "archivebox.fill"
                        )
                    }
                    .disabled(
                        !model.hasSources
                        || model.isScanning
                        || isSavingToMemory
                        || isCurrentSnapshotSaved
                    )
                } header: {
                    Text("Source Inspector")
                } footer: {
                    Text("The first pass inventories loaded scripts, styles, module preloads, and runtime resources. A bounded second pass reconciles late runtime entries and source references for workers, imports, chunks, source maps, and WASM metadata. The retained index stays in memory until ContextPort closes. Save Sources to Memory packages the complete retained index into one ZIP regardless of the active search filter.")
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
            .searchable(text: $searchText, prompt: "Search source contents")
            .onChange(of: searchText) { query in
                model.scheduleSearch(query)
            }
            .task {
                if isActive {
                    model.scanIfNeeded(sessions: profileSessionPool.developerSourceSessions())
                }
            }
            .onChange(of: isActive) { active in
                if active {
                    model.scanIfNeeded(sessions: profileSessionPool.developerSourceSessions())
                }
            }
        }
    }

    private var isCurrentSnapshotSaved: Bool {
        guard let current = model.snapshotFingerprint,
              let lastSavedSnapshotFingerprint else {
            return false
        }
        return current == lastSavedSnapshotFingerprint
    }

    private func saveSourcesToMemory() {
        guard !isSavingToMemory else { return }
        let snapshot = model.archiveSnapshot()
        guard !snapshot.isEmpty else { return }

        let snapshotFingerprint = model.snapshotFingerprint
            ?? DeveloperSourceMemoryArchiveBuilder.fingerprint(for: snapshot)

        isSavingToMemory = true
        appModel.statusMessage = "Packaging \(snapshot.count) retained sources into one Memory ZIP..."

        Task { @MainActor in
            defer { isSavingToMemory = false }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try DeveloperSourceMemoryArchiveBuilder().saveToMemory(items: snapshot)
                }.value
                lastSavedSnapshotFingerprint = snapshotFingerprint
                appModel.reloadLocalMemory()
                appModel.statusMessage = result.message
            } catch {
                appModel.reloadLocalMemory()
                appModel.statusMessage = "Developer source ZIP save failed: \(error.localizedDescription)"
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

    @State private var isShowingInfo = false

    var body: some View {
        Group {
            if let content = result.source.content {
                VStack(spacing: 0) {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("\(result.matchCount) match\(result.matchCount == 1 ? "" : "es") for \"\(query)\"")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("First match shown")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.thinMaterial)
                    }

                    DeveloperSourceCodeTextView(
                        sourceID: result.source.id,
                        content: content,
                        searchQuery: query
                    )
                }
            } else {
                List {
                    Section("Source") {
                        LabeledContent("Name", value: result.source.displayName)
                        LabeledContent("Type", value: result.source.kind)
                        LabeledContent("Session", value: result.source.sessionTitle)
                    }

                    if let loadError = result.source.loadError {
                        Section("Load Error") {
                            Text(loadError)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle(result.source.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if result.source.content != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Source information")
                }
            }
        }
        .sheet(isPresented: $isShowingInfo) {
            DeveloperSourceInfoView(result: result, query: query)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct DeveloperSourceInfoView: View {
    let result: DeveloperSourceSearchResult
    let query: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Source Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DeveloperSourceCodeTextView: UIViewRepresentable {
    let sourceID: String
    let content: String
    let searchQuery: String

    final class Coordinator {
        var sourceID: String?
        var searchQuery = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .systemBackground
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 20, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if context.coordinator.sourceID != sourceID {
            textView.text = content
            textView.setContentOffset(.zero, animated: false)
            context.coordinator.sourceID = sourceID
            context.coordinator.searchQuery = ""
        }

        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard context.coordinator.searchQuery != normalizedQuery else { return }

        context.coordinator.searchQuery = normalizedQuery
        guard !normalizedQuery.isEmpty else {
            textView.selectedRange = NSRange(location: 0, length: 0)
            return
        }

        let range = (textView.text as NSString).range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        guard range.location != NSNotFound else { return }

        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }
}
