import Foundation

enum DeveloperSourceSafeMapRecovery {
    private static let maximumParentAssets = 64
    private static let maximumMapCandidates = 64
    private static let maximumMapBytes = 2 * 1024 * 1024
    private static let maximumOriginalSources = 128
    private static let maximumOriginalSourceBytes = 512 * 1024

    private struct Candidate {
        let identity: String
        let reference: String
        let discovery: String
        let parentSourceID: String
        let parentSourceURL: String?
        let baseURL: URL?
    }

    private struct SourceMapDocument: Decodable {
        let version: Int
        let file: String?
        let sourceRoot: String?
        let sources: [String]
        let sourcesContent: [String?]?
        let mappings: String
    }

    static func recover(
        from files: [DeveloperSourceFile],
        sessionID: String,
        sessionTitle: String,
        pageURL: String,
        userAgent: String?,
        cookieHeader: String?,
        budget: DeveloperSourceCaptureBudget
    ) async -> DeveloperSourceMapRecoveryResult {
        let eligibleParents = Array(files.filter(isEligibleParent).prefix(maximumParentAssets))
        guard !eligibleParents.isEmpty else {
            return DeveloperSourceMapRecoveryResult(mapFiles: [], originalSourceFiles: [])
        }

        let headerReferences = await DeveloperSourceResponseMetadataRegistry.shared.sourceMapReferences(
            for: eligibleParents.map(\.id)
        )
        let existingByURL = Dictionary(
            uniqueKeysWithValues: files.compactMap { file -> (String, DeveloperSourceFile)? in
                guard let rawURL = file.urlString,
                      let canonical = canonicalURLString(rawURL) else {
                    return nil
                }
                return (canonical, file)
            }
        )
        let candidates = discoverCandidates(
            parents: eligibleParents,
            headerReferences: headerReferences,
            existingFiles: files
        )

        var mapFiles: [DeveloperSourceFile] = []
        var originalSourceFiles: [DeveloperSourceFile] = []

        for candidate in candidates.prefix(maximumMapCandidates) {
            guard !Task.isCancelled else { break }
            guard let loaded = await loadValidatedMap(
                candidate,
                existingByURL: existingByURL,
                pageURL: pageURL,
                userAgent: userAgent,
                cookieHeader: cookieHeader
            ) else {
                continue
            }

            let mapURLString = loaded.urlString
            let document = loaded.document
            let sourcesContent = document.sourcesContent
            let embeddedCount = sourcesContent?.compactMap { $0 }.count ?? 0
            let mapMetadata = [
                "Discovery: \(candidate.discovery)",
                candidate.parentSourceURL.map { "Parent Source URL: \($0)" },
                "Validated SourceMap: version 3",
                "Embedded sources: \(document.sources.count)",
                "Embedded sourcesContent entries: \(embeddedCount)",
                embeddedCount > 0
                    ? "Retention: map JSON is metadata-only because embedded source text is handled individually under the shared capture budget."
                    : nil
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            if embeddedCount == 0 {
                let byteCount = loaded.content.utf8.count
                let reservation = await budget.reserve(upTo: byteCount)
                if reservation == byteCount {
                    await budget.commit(reservation: reservation, actualBytes: byteCount)
                    mapFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(mapURLString))",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForMap(mapURLString),
                            urlString: httpURLString(mapURLString),
                            kind: "Source Map • Validated v3",
                            content: loaded.content,
                            metadataNote: mapMetadata,
                            resourceByteCount: nil,
                            loadError: nil
                        )
                    )
                } else {
                    await budget.release(reservation: reservation, countAsOmission: true)
                    mapFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(mapURLString))",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForMap(mapURLString),
                            urlString: httpURLString(mapURLString),
                            kind: "Source Map • Validated v3",
                            content: nil,
                            metadataNote: mapMetadata + "\nRetention: map text exceeded the remaining 32 MB capture budget and was retained as metadata only.",
                            resourceByteCount: byteCount,
                            loadError: nil
                        )
                    )
                }
            } else {
                mapFiles.append(
                    DeveloperSourceFile(
                        id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(mapURLString))",
                        sessionTitle: sessionTitle,
                        pageURL: pageURL,
                        displayName: displayNameForMap(mapURLString),
                        urlString: httpURLString(mapURLString),
                        kind: "Source Map • Validated v3",
                        content: nil,
                        metadataNote: mapMetadata,
                        resourceByteCount: loaded.content.utf8.count,
                        loadError: nil
                    )
                )
            }

            guard let sourcesContent else {
                await Task.yield()
                continue
            }

            for (index, originalPath) in document.sources.enumerated() {
                guard originalSourceFiles.count < maximumOriginalSources,
                      index < sourcesContent.count,
                      let originalContent = sourcesContent[index],
                      !originalContent.isEmpty else {
                    continue
                }

                let sourceBytes = originalContent.utf8.count
                let metadata = [
                    "SourceMap URL: \(mapURLString)",
                    candidate.parentSourceURL.map { "Parent Source URL: \($0)" },
                    "Original Source Path: \(originalPath)",
                    document.sourceRoot.map { "Source Root: \($0)" },
                    document.file.map { "Generated File: \($0)" }
                ]
                .compactMap { $0 }
                .joined(separator: "\n")

                guard sourceBytes <= maximumOriginalSourceBytes else {
                    await budget.recordOmission()
                    originalSourceFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-original:\(stableIdentifier(mapURLString)):\(index)",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForOriginalSource(originalPath),
                            urlString: nil,
                            kind: "Original Source • Embedded SourceMap",
                            content: nil,
                            metadataNote: metadata + "\nRetention: original source text exceeded the 512 KB per-source limit and was retained as metadata only.",
                            resourceByteCount: sourceBytes,
                            loadError: nil
                        )
                    )
                    continue
                }

                let reservation = await budget.reserve(upTo: sourceBytes)
                if reservation == sourceBytes {
                    await budget.commit(reservation: reservation, actualBytes: sourceBytes)
                    originalSourceFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-original:\(stableIdentifier(mapURLString)):\(index)",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForOriginalSource(originalPath),
                            urlString: nil,
                            kind: "Original Source • Embedded SourceMap",
                            content: originalContent,
                            metadataNote: metadata,
                            resourceByteCount: nil,
                            loadError: nil
                        )
                    )
                } else {
                    await budget.release(reservation: reservation, countAsOmission: true)
                    originalSourceFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-original:\(stableIdentifier(mapURLString)):\(index)",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForOriginalSource(originalPath),
                            urlString: nil,
                            kind: "Original Source • Embedded SourceMap",
                            content: nil,
                            metadataNote: metadata + "\nRetention: original source text exceeded the remaining 32 MB capture budget and was retained as metadata only.",
                            resourceByteCount: sourceBytes,
                            loadError: nil
                        )
                    )
                }
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return DeveloperSourceMapRecoveryResult(
            mapFiles: mapFiles,
            originalSourceFiles: originalSourceFiles
        )
    }

    private struct LoadedMap {
        let urlString: String
        let content: String
        let document: SourceMapDocument
    }

    private static func loadValidatedMap(
        _ candidate: Candidate,
        existingByURL: [String: DeveloperSourceFile],
        pageURL: String,
        userAgent: String?,
        cookieHeader: String?
    ) async -> LoadedMap? {
        if candidate.reference.lowercased().hasPrefix("data:") {
            guard let content = decodeInlineMap(candidate.reference),
                  let document = decodeValidatedMap(content) else {
                return nil
            }
            return LoadedMap(
                urlString: "inline-source-map:\(candidate.parentSourceURL ?? candidate.parentSourceID)",
                content: content,
                document: document
            )
        }

        guard let resolved = resolveReference(candidate.reference, relativeTo: candidate.baseURL),
              let canonical = canonicalURLString(resolved.absoluteString) else {
            return nil
        }

        if let existing = existingByURL[canonical],
           let content = existing.content,
           content.utf8.count <= maximumMapBytes,
           let document = decodeValidatedMap(content) {
            return LoadedMap(urlString: canonical, content: content, document: document)
        }

        guard let content = await fetchText(
            from: resolved,
            pageURL: pageURL,
            userAgent: userAgent,
            cookieHeader: cookieHeader
        ),
        let document = decodeValidatedMap(content) else {
            return nil
        }

        return LoadedMap(urlString: canonical, content: content, document: document)
    }

    private static func fetchText(
        from url: URL,
        pageURL: String,
        userAgent: String?,
        cookieHeader: String?
    ) async -> String? {
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 15
            if let userAgent, !userAgent.isEmpty {
                request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            }
            if let cookieHeader, !cookieHeader.isEmpty {
                request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
            }
            request.setValue(pageURL, forHTTPHeaderField: "Referer")

            let loaded = try await DeveloperSourceBoundedRequest(maximumBytes: maximumMapBytes).load(request)
            if let httpResponse = loaded.response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                return nil
            }
            return String(data: loaded.data, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private static func discoverCandidates(
        parents: [DeveloperSourceFile],
        headerReferences: [String: [String]],
        existingFiles: [DeveloperSourceFile]
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        var seen = Set<String>()

        func append(
            reference: String,
            discovery: String,
            parent: DeveloperSourceFile,
            baseURL: URL?
        ) {
            guard candidates.count < maximumMapCandidates else { return }
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let identity: String
            if trimmed.lowercased().hasPrefix("data:") {
                identity = "inline:\(stableIdentifier(trimmed))"
            } else if let resolved = resolveReference(trimmed, relativeTo: baseURL),
                      let canonical = canonicalURLString(resolved.absoluteString) {
                identity = canonical
            } else {
                return
            }

            guard seen.insert(identity).inserted else { return }
            candidates.append(
                Candidate(
                    identity: identity,
                    reference: trimmed,
                    discovery: discovery,
                    parentSourceID: parent.id,
                    parentSourceURL: parent.urlString,
                    baseURL: baseURL
                )
            )
        }

        for parent in parents {
            let baseURL = parent.urlString.flatMap(URL.init(string:))
            for headerReference in headerReferences[parent.id] ?? [] {
                append(
                    reference: headerReference,
                    discovery: "SourceMap/X-SourceMap response header",
                    parent: parent,
                    baseURL: baseURL
                )
            }
            if let content = parent.content {
                for directive in sourceMappingDirectives(in: content) {
                    append(
                        reference: directive,
                        discovery: "sourceMappingURL directive",
                        parent: parent,
                        baseURL: baseURL
                    )
                }
            }
            if let fallback = fallbackMapURL(for: baseURL) {
                append(
                    reference: fallback.absoluteString,
                    discovery: "bounded .map fallback",
                    parent: parent,
                    baseURL: baseURL
                )
            }
        }

        for file in existingFiles {
            guard candidates.count < maximumMapCandidates,
                  let rawURL = file.urlString,
                  let url = URL(string: rawURL),
                  url.path.lowercased().hasSuffix(".map"),
                  let canonical = canonicalURLString(rawURL),
                  seen.insert(canonical).inserted else {
                continue
            }
            candidates.append(
                Candidate(
                    identity: canonical,
                    reference: canonical,
                    discovery: "captured Source Map resource",
                    parentSourceID: file.id,
                    parentSourceURL: nil,
                    baseURL: url
                )
            )
        }

        return candidates
    }

    private static func sourceMappingDirectives(in content: String) -> [String] {
        let patterns = [
            #"(?m)//[#@]\s*sourceMappingURL\s*=\s*([^\s]+)\s*$"#,
            #"(?s)/\*#\s*sourceMappingURL\s*=\s*([^*\s]+)\s*\*/"#
        ]
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        var result: [String] = []
        var seen = Set<String>()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: content, range: fullRange) {
                guard match.numberOfRanges > 1,
                      match.range(at: 1).location != NSNotFound else {
                    continue
                }
                let raw = nsContent.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` \t\r\n"))
                guard !raw.isEmpty, seen.insert(raw).inserted else { continue }
                result.append(raw)
            }
        }
        return result
    }

    private static func decodeValidatedMap(_ content: String) -> SourceMapDocument? {
        guard content.utf8.count <= maximumMapBytes,
              let data = content.data(using: .utf8),
              let document = try? JSONDecoder().decode(SourceMapDocument.self, from: data),
              document.version == 3,
              !document.sources.isEmpty,
              document.mappings.count > 10 else {
            return nil
        }
        return document
    }

    private static func decodeInlineMap(_ reference: String) -> String? {
        guard reference.lowercased().hasPrefix("data:"),
              let comma = reference.firstIndex(of: ",") else {
            return nil
        }
        let metadata = String(reference[reference.index(reference.startIndex, offsetBy: 5)..<comma]).lowercased()
        guard metadata.contains("json") else { return nil }
        let payload = String(reference[reference.index(after: comma)...])
        let data = metadata.contains(";base64")
            ? Data(base64Encoded: payload, options: [.ignoreUnknownCharacters])
            : payload.removingPercentEncoding?.data(using: .utf8)
        guard let data, data.count <= maximumMapBytes else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func isEligibleParent(_ file: DeveloperSourceFile) -> Bool {
        guard file.content != nil,
              let rawURL = file.urlString,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        return [".js", ".mjs", ".cjs", ".css"].contains { path.hasSuffix($0) }
    }

    private static func fallbackMapURL(for assetURL: URL?) -> URL? {
        guard let assetURL,
              var components = URLComponents(url: assetURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        components.path += ".map"
        return components.url
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

    private static func canonicalURLString(_ raw: String) -> String? {
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func httpURLString(_ raw: String) -> String? {
        canonicalURLString(raw)
    }

    private static func displayNameForMap(_ raw: String) -> String {
        guard let url = URL(string: raw), !url.lastPathComponent.isEmpty else {
            return "Inline Source Map"
        }
        return url.lastPathComponent
    }

    private static func displayNameForOriginalSource(_ originalPath: String) -> String {
        let normalized = originalPath
            .replacingOccurrences(of: "webpack:///", with: "")
            .replacingOccurrences(of: "webpack://", with: "")
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let readable = normalized
            .split(separator: "/")
            .filter { $0 != "." && $0 != ".." }
            .map(String.init)
            .joined(separator: " › ")
        return readable.isEmpty ? originalPath : readable
    }

    private static func stableIdentifier(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
            .prefix(120)
            .description
    }
}
