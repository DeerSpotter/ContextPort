import CryptoKit
import Foundation

struct DeveloperSourceMapCandidate: Identifiable, Sendable {
    let id: String
    let reference: String?
    let inlineCacheURL: URL?
    let discovery: String
    let parentSourceID: String
    let parentSourceURL: String?
    let baseURLString: String?
    let displayName: String
    let estimatedByteCount: Int?
}

struct DeveloperValidatedSourceMap: Identifiable, Sendable {
    let id: String
    let candidate: DeveloperSourceMapCandidate
    let mapURLString: String
    let cacheURL: URL
    let byteCount: Int
    let sourceCount: Int
    let generatedFile: String?
    let sourceRoot: String?
}

enum DeveloperSourceMapStagedRecovery {
    private static let maximumParentAssets = 64
    private static let maximumMapCandidates = 64
    private static let maximumMapBytes = 2 * 1024 * 1024
    private static let maximumEncodedInlineMapBytes = 3 * 1024 * 1024
    private static let maximumOriginalSources = 128
    private static let maximumOriginalSourceBytes = 512 * 1024

    private struct ValidationDocument: Decodable {
        let version: Int
        let file: String?
        let sourceRoot: String?
        let sources: [String]
        let mappings: String
    }

    private struct DecodeDocument: Decodable {
        let version: Int
        let file: String?
        let sourceRoot: String?
        let sources: [String]
        let sourcesContent: [String?]?
        let mappings: String
    }

    static func discover(
        from files: [DeveloperSourceFile]
    ) async -> [DeveloperSourceMapCandidate] {
        let eligibleParents = Array(files.lazy.filter(isEligibleParent).prefix(maximumParentAssets))
        guard !eligibleParents.isEmpty else { return [] }

        let headerReferences = await DeveloperSourceResponseMetadataRegistry.shared.sourceMapReferences(
            for: eligibleParents.map(\.id)
        )

        var candidates: [DeveloperSourceMapCandidate] = []
        var seen = Set<String>()

        func appendCandidate(
            reference: String,
            discovery: String,
            parent: DeveloperSourceFile,
            baseURL: URL?
        ) {
            guard candidates.count < maximumMapCandidates else { return }
            let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            if trimmed.lowercased().hasPrefix("data:") {
                let identity = "inline:\(stableIdentifier(trimmed))"
                guard seen.insert(identity).inserted,
                      let data = decodeInlineMapData(trimmed),
                      let cacheURL = writeTemporaryMapData(data, category: "Candidates") else {
                    return
                }

                candidates.append(
                    DeveloperSourceMapCandidate(
                        id: identity,
                        reference: nil,
                        inlineCacheURL: cacheURL,
                        discovery: discovery,
                        parentSourceID: parent.id,
                        parentSourceURL: parent.urlString,
                        baseURLString: baseURL?.absoluteString,
                        displayName: "Inline Source Map",
                        estimatedByteCount: data.count
                    )
                )
                return
            }

            guard let resolved = resolveReference(trimmed, relativeTo: baseURL),
                  let canonical = canonicalURLString(resolved.absoluteString),
                  seen.insert(canonical).inserted else {
                return
            }

            candidates.append(
                DeveloperSourceMapCandidate(
                    id: canonical,
                    reference: trimmed,
                    inlineCacheURL: nil,
                    discovery: discovery,
                    parentSourceID: parent.id,
                    parentSourceURL: parent.urlString,
                    baseURLString: baseURL?.absoluteString,
                    displayName: displayNameForMap(canonical),
                    estimatedByteCount: nil
                )
            )
        }

        for parent in eligibleParents {
            let baseURL = parent.urlString.flatMap(URL.init(string:))

            for headerReference in headerReferences[parent.id] ?? [] {
                appendCandidate(
                    reference: headerReference,
                    discovery: "SourceMap/X-SourceMap response header",
                    parent: parent,
                    baseURL: baseURL
                )
            }

            if let content = parent.content {
                for directive in sourceMappingDirectives(in: content) {
                    appendCandidate(
                        reference: directive,
                        discovery: "sourceMappingURL directive",
                        parent: parent,
                        baseURL: baseURL
                    )
                }
            }

            if let fallback = fallbackMapURL(for: baseURL) {
                appendCandidate(
                    reference: fallback.absoluteString,
                    discovery: "bounded .map fallback",
                    parent: parent,
                    baseURL: baseURL
                )
            }
        }

        for file in files {
            guard candidates.count < maximumMapCandidates,
                  let rawURL = file.urlString,
                  let url = URL(string: rawURL),
                  url.path.lowercased().hasSuffix(".map"),
                  let canonical = canonicalURLString(rawURL),
                  seen.insert(canonical).inserted else {
                continue
            }

            candidates.append(
                DeveloperSourceMapCandidate(
                    id: canonical,
                    reference: canonical,
                    inlineCacheURL: nil,
                    discovery: "captured Source Map resource",
                    parentSourceID: file.id,
                    parentSourceURL: nil,
                    baseURLString: url.absoluteString,
                    displayName: displayNameForMap(canonical),
                    estimatedByteCount: file.byteCount > 0 ? file.byteCount : nil
                )
            )
        }

        return candidates
    }

    static func candidateFiles(
        _ candidates: [DeveloperSourceMapCandidate],
        sessionID: String,
        sessionTitle: String,
        pageURL: String
    ) -> [DeveloperSourceFile] {
        candidates.map { candidate in
            DeveloperSourceFile(
                id: "\(sessionID)::sourcemap-candidate:\(stableIdentifier(candidate.id))",
                sessionTitle: sessionTitle,
                pageURL: pageURL,
                displayName: candidate.displayName,
                urlString: candidate.reference.flatMap { reference in
                    resolveReference(reference, relativeTo: candidate.baseURLString.flatMap(URL.init(string:)))
                        .flatMap { canonicalURLString($0.absoluteString) }
                },
                kind: "Source Map Candidate",
                content: nil,
                metadataNote: "Discovery: \(candidate.discovery)\nValidation and decoding have not run yet.",
                resourceByteCount: candidate.estimatedByteCount,
                loadError: nil
            )
        }
    }

    static func validate(
        candidates: [DeveloperSourceMapCandidate],
        existingFiles: [DeveloperSourceFile],
        sessionID: String,
        pageURL: String,
        userAgent: String?,
        cookieHeader: String?
    ) async -> [DeveloperValidatedSourceMap] {
        var existingByURL: [String: DeveloperSourceFile] = [:]
        for file in existingFiles {
            guard let rawURL = file.urlString,
                  let canonical = canonicalURLString(rawURL) else {
                continue
            }

            if let existing = existingByURL[canonical] {
                if existing.content == nil, file.content != nil {
                    existingByURL[canonical] = file
                }
            } else {
                existingByURL[canonical] = file
            }
        }

        var validated: [DeveloperValidatedSourceMap] = []
        validated.reserveCapacity(min(candidates.count, maximumMapCandidates))

        for candidate in candidates.prefix(maximumMapCandidates) {
            guard !Task.isCancelled else { break }

            defer {
                if let inlineCacheURL = candidate.inlineCacheURL {
                    try? FileManager.default.removeItem(at: inlineCacheURL)
                }
            }

            guard let loaded = await loadCandidateData(
                candidate,
                existingByURL: existingByURL,
                pageURL: pageURL,
                userAgent: userAgent,
                cookieHeader: cookieHeader
            ),
            let document = decodeValidationDocument(loaded.data),
            let cacheURL = writeTemporaryMapData(loaded.data, category: "Validated") else {
                await Task.yield()
                continue
            }

            validated.append(
                DeveloperValidatedSourceMap(
                    id: "\(sessionID)::validated-sourcemap:\(stableIdentifier(loaded.mapURLString))",
                    candidate: candidate,
                    mapURLString: loaded.mapURLString,
                    cacheURL: cacheURL,
                    byteCount: loaded.data.count,
                    sourceCount: document.sources.count,
                    generatedFile: document.file,
                    sourceRoot: document.sourceRoot
                )
            )

            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }

        return validated
    }

    static func validationFiles(
        _ validatedMaps: [DeveloperValidatedSourceMap],
        sessionID: String,
        sessionTitle: String,
        pageURL: String
    ) -> [DeveloperSourceFile] {
        validatedMaps.map { validated in
            let metadata = [
                "Discovery: \(validated.candidate.discovery)",
                validated.candidate.parentSourceURL.map { "Parent Source URL: \($0)" },
                "Validated SourceMap: version 3",
                "Original source paths: \(validated.sourceCount)",
                validated.generatedFile.map { "Generated File: \($0)" },
                validated.sourceRoot.map { "Source Root: \($0)" },
                "Embedded sourcesContent decoding is pending Step 4C."
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            return DeveloperSourceFile(
                id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(validated.mapURLString))",
                sessionTitle: sessionTitle,
                pageURL: pageURL,
                displayName: displayNameForMap(validated.mapURLString),
                urlString: httpURLString(validated.mapURLString),
                kind: "Source Map • Validated v3",
                content: nil,
                metadataNote: metadata,
                resourceByteCount: validated.byteCount,
                loadError: nil
            )
        }
    }

    static func decode(
        validatedMaps: [DeveloperValidatedSourceMap],
        sessionID: String,
        sessionTitle: String,
        pageURL: String,
        budget: DeveloperSourceCaptureBudget
    ) async -> DeveloperSourceMapRecoveryResult {
        var mapFiles: [DeveloperSourceFile] = []
        var originalSourceFiles: [DeveloperSourceFile] = []

        for validated in validatedMaps {
            guard !Task.isCancelled else { break }

            defer {
                try? FileManager.default.removeItem(at: validated.cacheURL)
            }

            guard let data = try? Data(contentsOf: validated.cacheURL, options: [.mappedIfSafe]),
                  data.count <= maximumMapBytes,
                  let document = decodeFullDocument(data) else {
                await Task.yield()
                continue
            }

            let sourcesContent = document.sourcesContent
            let embeddedCount = sourcesContent?.compactMap { $0 }.count ?? 0
            let mapMetadata = [
                "Discovery: \(validated.candidate.discovery)",
                validated.candidate.parentSourceURL.map { "Parent Source URL: \($0)" },
                "Validated SourceMap: version 3",
                "Embedded sources: \(document.sources.count)",
                "Embedded sourcesContent entries: \(embeddedCount)",
                embeddedCount > 0
                    ? "Retention: validated map JSON is metadata-only because embedded sourcesContent was decoded into original source entries."
                    : nil
            ]
            .compactMap { $0 }
            .joined(separator: "\n")

            if embeddedCount == 0,
               let mapText = String(data: data, encoding: .utf8) {
                let reservation = await budget.reserve(upTo: data.count)
                if reservation == data.count {
                    await budget.commit(reservation: reservation, actualBytes: data.count)
                    mapFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(validated.mapURLString))",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForMap(validated.mapURLString),
                            urlString: httpURLString(validated.mapURLString),
                            kind: "Source Map • Validated v3",
                            content: mapText,
                            metadataNote: mapMetadata,
                            resourceByteCount: nil,
                            loadError: nil
                        )
                    )
                } else {
                    await budget.release(reservation: reservation, countAsOmission: true)
                    mapFiles.append(
                        DeveloperSourceFile(
                            id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(validated.mapURLString))",
                            sessionTitle: sessionTitle,
                            pageURL: pageURL,
                            displayName: displayNameForMap(validated.mapURLString),
                            urlString: httpURLString(validated.mapURLString),
                            kind: "Source Map • Validated v3",
                            content: nil,
                            metadataNote: mapMetadata + "\nRetention: map text exceeded the remaining 32 MB capture budget and was retained as metadata only.",
                            resourceByteCount: data.count,
                            loadError: nil
                        )
                    )
                }
            } else {
                mapFiles.append(
                    DeveloperSourceFile(
                        id: "\(sessionID)::safe-sourcemap:\(stableIdentifier(validated.mapURLString))",
                        sessionTitle: sessionTitle,
                        pageURL: pageURL,
                        displayName: displayNameForMap(validated.mapURLString),
                        urlString: httpURLString(validated.mapURLString),
                        kind: "Source Map • Validated v3",
                        content: nil,
                        metadataNote: mapMetadata,
                        resourceByteCount: data.count,
                        loadError: nil
                    )
                )
            }

            if let sourcesContent {
                for (index, originalPath) in document.sources.enumerated() {
                    guard originalSourceFiles.count < maximumOriginalSources,
                          index < sourcesContent.count,
                          let originalContent = sourcesContent[index],
                          !originalContent.isEmpty else {
                        continue
                    }

                    let sourceBytes = originalContent.utf8.count
                    let metadata = [
                        "SourceMap URL: \(validated.mapURLString)",
                        validated.candidate.parentSourceURL.map { "Parent Source URL: \($0)" },
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
                                id: "\(sessionID)::safe-original:\(stableIdentifier(validated.mapURLString)):\(index)",
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
                                id: "\(sessionID)::safe-original:\(stableIdentifier(validated.mapURLString)):\(index)",
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
                                id: "\(sessionID)::safe-original:\(stableIdentifier(validated.mapURLString)):\(index)",
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
            }

            await Task.yield()
            try? await Task.sleep(nanoseconds: 25_000_000)
        }

        cleanupEmptyTemporaryDirectories()
        return DeveloperSourceMapRecoveryResult(
            mapFiles: mapFiles,
            originalSourceFiles: originalSourceFiles
        )
    }

    static func cleanup(candidates: [DeveloperSourceMapCandidate], validatedMaps: [DeveloperValidatedSourceMap]) {
        for candidate in candidates {
            if let inlineCacheURL = candidate.inlineCacheURL {
                try? FileManager.default.removeItem(at: inlineCacheURL)
            }
        }
        for validated in validatedMaps {
            try? FileManager.default.removeItem(at: validated.cacheURL)
        }
        cleanupEmptyTemporaryDirectories()
    }

    private struct LoadedCandidateData {
        let mapURLString: String
        let data: Data
    }

    private static func loadCandidateData(
        _ candidate: DeveloperSourceMapCandidate,
        existingByURL: [String: DeveloperSourceFile],
        pageURL: String,
        userAgent: String?,
        cookieHeader: String?
    ) async -> LoadedCandidateData? {
        if let inlineCacheURL = candidate.inlineCacheURL,
           let data = try? Data(contentsOf: inlineCacheURL, options: [.mappedIfSafe]),
           data.count <= maximumMapBytes {
            return LoadedCandidateData(
                mapURLString: "inline-source-map:\(candidate.parentSourceURL ?? candidate.parentSourceID)",
                data: data
            )
        }

        guard let reference = candidate.reference,
              let resolved = resolveReference(
                reference,
                relativeTo: candidate.baseURLString.flatMap(URL.init(string:))
              ),
              let canonical = canonicalURLString(resolved.absoluteString) else {
            return nil
        }

        if let existing = existingByURL[canonical],
           let content = existing.content {
            let data = Data(content.utf8)
            if data.count <= maximumMapBytes {
                return LoadedCandidateData(mapURLString: canonical, data: data)
            }
        }

        do {
            var request = URLRequest(url: resolved)
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
            if let response = loaded.response as? HTTPURLResponse,
               !(200...299).contains(response.statusCode) {
                return nil
            }
            return LoadedCandidateData(mapURLString: canonical, data: loaded.data)
        } catch {
            return nil
        }
    }

    private static func decodeValidationDocument(_ data: Data) -> ValidationDocument? {
        guard data.count <= maximumMapBytes,
              let document = try? JSONDecoder().decode(ValidationDocument.self, from: data),
              document.version == 3,
              !document.sources.isEmpty,
              document.mappings.count > 10 else {
            return nil
        }
        return document
    }

    private static func decodeFullDocument(_ data: Data) -> DecodeDocument? {
        guard data.count <= maximumMapBytes,
              let document = try? JSONDecoder().decode(DecodeDocument.self, from: data),
              document.version == 3,
              !document.sources.isEmpty,
              document.mappings.count > 10 else {
            return nil
        }
        return document
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
            regex.enumerateMatches(in: content, range: fullRange) { match, _, stop in
                guard let match,
                      result.count < maximumMapCandidates,
                      match.numberOfRanges > 1,
                      match.range(at: 1).location != NSNotFound else {
                    if result.count >= maximumMapCandidates { stop.pointee = true }
                    return
                }

                let raw = nsContent.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` \t\r\n"))
                guard !raw.isEmpty, seen.insert(raw).inserted else { return }
                result.append(raw)
            }
        }
        return result
    }

    private static func decodeInlineMapData(_ reference: String) -> Data? {
        guard reference.lowercased().hasPrefix("data:"),
              reference.utf8.count <= maximumEncodedInlineMapBytes,
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
        return data
    }

    private static func writeTemporaryMapData(_ data: Data, category: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextPortSourceMapStages", isDirectory: true)
            .appendingPathComponent(category, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(UUID().uuidString).map")
            try data.write(to: url, options: [.atomic])
            return url
        } catch {
            return nil
        }
    }

    private static func cleanupEmptyTemporaryDirectories() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContextPortSourceMapStages", isDirectory: true)
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else { return }

        for child in children {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: child.path)) ?? []
            if entries.isEmpty {
                try? FileManager.default.removeItem(at: child)
            }
        }
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        if remaining.isEmpty {
            try? FileManager.default.removeItem(at: root)
        }
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
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}