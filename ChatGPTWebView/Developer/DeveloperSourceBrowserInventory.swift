import Foundation
import WebKit

func developerInlineSourceFiles(
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

func discoverDeveloperSources(in webView: WKWebView) async throws -> DeveloperDiscoveredPage {
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

private enum DeveloperSourceScanError: LocalizedError {
    case invalidInventory

    var errorDescription: String? {
        switch self {
        case .invalidInventory:
            return "The page did not return a readable source inventory."
        }
    }
}
