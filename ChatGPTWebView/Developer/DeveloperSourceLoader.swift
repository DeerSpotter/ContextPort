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
    let budget = DeveloperSourceCaptureBudget()
    return await loadExternalDeveloperSources(
        descriptors,
        sessionID: sessionID,
        sessionTitle: sessionTitle,
        pageURL: pageURL,
        userAgent: userAgent,
        cookieHeader: cookieHeader,
        budget: budget
    )
}

func loadExternalDeveloperSources(
    _ descriptors: [DeveloperDiscoveredSource],
    sessionID: String,
    sessionTitle: String,
    pageURL: String,
    userAgent: String?,
    cookieHeader: String?,
    budget: DeveloperSourceCaptureBudget
) async -> [DeveloperSourceFile] {
    guard !descriptors.isEmpty else { return [] }

    var loaded: [DeveloperSourceFile] = []
    loaded.reserveCapacity(descriptors.count)

    for descriptor in descriptors {
        guard !Task.isCancelled else { return loaded }

        loaded.append(
            await loadExternalDeveloperSource(
                descriptor,
                sessionID: sessionID,
                sessionTitle: sessionTitle,
                pageURL: pageURL,
                userAgent: userAgent,
                cookieHeader: cookieHeader,
                budget: budget
            )
        )

        await Task.yield()
        try? await Task.sleep(nanoseconds: 5_000_000)
    }

    return loaded
}

private func loadExternalDeveloperSource(
    _ descriptor: DeveloperDiscoveredSource,
    sessionID: String,
    sessionTitle: String,
    pageURL: String,
    userAgent: String?,
    cookieHeader: String?,
    budget: DeveloperSourceCaptureBudget
) async -> DeveloperSourceFile {
    let sourceID = "\(sessionID)::\(descriptor.key)"

    guard let urlString = descriptor.url,
          let url = URL(string: urlString),
          let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
        await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences([], for: sourceID)
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

    let reservation = await budget.reserve(
        upTo: DeveloperSourceCaptureBudget.maximumExternalSourceBytes
    )
    guard reservation > 0 else {
        await budget.recordOmission()
        await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences([], for: sourceID)
        return budgetMetadataOnlySource(
            sourceID: sourceID,
            descriptor: descriptor,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            note: "Source text was not loaded because the 32 MB Developer Sources refresh budget was already exhausted. URL and provenance were retained as metadata."
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

        let boundedRequest = DeveloperSourceBoundedRequest(maximumBytes: reservation)
        let loaded = try await boundedRequest.load(request)
        let data = loaded.data
        let response = loaded.response

        if let httpResponse = response as? HTTPURLResponse {
            let sourceMapReferences = [
                httpResponse.value(forHTTPHeaderField: "SourceMap"),
                httpResponse.value(forHTTPHeaderField: "X-SourceMap")
            ].compactMap { $0 }

            await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences(
                sourceMapReferences,
                for: sourceID
            )

            if !(200...299).contains(httpResponse.statusCode) {
                throw DeveloperSourceLoadError.httpStatus(httpResponse.statusCode)
            }
        } else {
            await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences([], for: sourceID)
        }

        let mimeType = response.mimeType?.lowercased() ?? ""
        if url.pathExtension.lowercased() == "wasm" || mimeType == "application/wasm" {
            await budget.release(reservation: reservation)
            return DeveloperSourceFile(
                id: sourceID,
                sessionTitle: sessionTitle,
                pageURL: pageURL,
                displayName: descriptor.displayName,
                urlString: urlString,
                kind: descriptor.kind,
                content: nil,
                metadataNote: "Binary WebAssembly resource reached a successful response and was retained as metadata-only evidence. ContextPort did not decode or execute it.",
                resourceByteCount: data.count,
                loadError: nil
            )
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw DeveloperSourceLoadError.notUTF8
        }

        await budget.commit(reservation: reservation, actualBytes: data.count)
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: urlString,
            kind: descriptor.kind,
            content: content,
            metadataNote: "External source text was downloaded sequentially through an 8 MB bounded response reader.",
            resourceByteCount: nil,
            loadError: nil
        )
    } catch is CancellationError {
        await budget.release(reservation: reservation)
        await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences([], for: sourceID)
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: urlString,
            kind: descriptor.kind,
            content: nil,
            metadataNote: "Source capture was cancelled before the complete source body was retained.",
            resourceByteCount: nil,
            loadError: nil
        )
    } catch let boundedError as DeveloperSourceBoundedLoadError {
        await budget.release(reservation: reservation, countAsOmission: true)
        await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences([], for: sourceID)
        let measured = boundedError.byteCount.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "an unknown size"
        return budgetMetadataOnlySource(
            sourceID: sourceID,
            descriptor: descriptor,
            sessionTitle: sessionTitle,
            pageURL: pageURL,
            note: "Source text was not retained because the response reached \(measured), above the available per-file or scan-wide capture budget. URL and provenance were retained as metadata."
        )
    } catch {
        await budget.release(reservation: reservation)
        await DeveloperSourceResponseMetadataRegistry.shared.recordSourceMapReferences([], for: sourceID)
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

private func budgetMetadataOnlySource(
    sourceID: String,
    descriptor: DeveloperDiscoveredSource,
    sessionTitle: String,
    pageURL: String,
    note: String
) -> DeveloperSourceFile {
    DeveloperSourceFile(
        id: sourceID,
        sessionTitle: sessionTitle,
        pageURL: pageURL,
        displayName: descriptor.displayName,
        urlString: descriptor.url,
        kind: descriptor.kind,
        content: nil,
        metadataNote: note,
        resourceByteCount: nil,
        loadError: nil
    )
}

private enum DeveloperSourceLoadError: LocalizedError {
    case httpStatus(Int)
    case notUTF8

    var errorDescription: String? {
        switch self {
        case .httpStatus(let statusCode):
            return "Source request returned HTTP \(statusCode)."
        case .notUTF8:
            return "Source response is not valid UTF-8 text and was recorded without indexed content."
        }
    }
}
