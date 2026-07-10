import Foundation
import WebKit

func developerCookieHeader(for webView: WKWebView) async -> String? {
    let cookies = await withCheckedContinuation { continuation in
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            continuation.resume(returning: cookies)
        }
    }

    guard !cookies.isEmpty else { return nil }
    return HTTPCookie.requestHeaderFields(with: cookies)["Cookie"]
}

func loadExternalDeveloperSources(
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
            metadataNote: nil,
            resourceByteCount: nil,
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
            return DeveloperSourceFile(
                id: sourceID,
                sessionTitle: sessionTitle,
                pageURL: pageURL,
                displayName: descriptor.displayName,
                urlString: urlString,
                kind: descriptor.kind,
                content: nil,
                metadataNote: "Binary WebAssembly resource fetched successfully and retained as metadata-only evidence. ContextPort did not decode or execute it.",
                resourceByteCount: data.count,
                loadError: nil
            )
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
            metadataNote: nil,
            resourceByteCount: nil,
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
            metadataNote: nil,
            resourceByteCount: nil,
            loadError: error.localizedDescription
        )
    }
}

private enum DeveloperSourceLoadError: LocalizedError {
    case httpStatus(Int)
    case sourceTooLarge(Int)
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Source request returned HTTP \(statusCode)."
        case .sourceTooLarge(let byteCount):
            return "Source is \(ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)), above the 24 MB per-source safety limit."
        case .notUTF8:
            return "Source response is not valid UTF-8 text and was recorded without indexed content."
        }
    }
}
