import Foundation
import SwiftUI
import UIKit
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

            var collected: [DeveloperSourceFile] = []
            var scannedSessionCount = 0
            var firstPassCount = 0
            var secondPassCount = 0
            var nestedPassCount = 0

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
            self.status = "Indexed \(self.sources.count) sources from \(scannedSessionCount) loaded session\(scannedSessionCount == 1 ? "" : "s") • \(firstPassCount) first pass • \(secondPassCount) second pass • \(nestedPassCount) nested dependencies. Kept until ContextPort closes."
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
                metadataNote: nil,
                resourceByteCount: nil,
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
