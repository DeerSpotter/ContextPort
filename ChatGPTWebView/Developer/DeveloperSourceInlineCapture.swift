import Foundation

private let developerInlineCaptureChunkCharacters = 64 * 1024

func loadBudgetedDeveloperInlineSources(
    from descriptors: [DeveloperDiscoveredSource],
    session: DeveloperWebViewSession,
    pageURL: String,
    budget: DeveloperSourceCaptureBudget
) async -> [DeveloperSourceFile] {
    var files: [DeveloperSourceFile] = []

    for descriptor in descriptors {
        guard !Task.isCancelled else { return files }
        guard let scriptIndex = descriptor.inlineSourceIndex else { continue }

        files.append(
            await loadBudgetedDeveloperInlineScript(
                descriptor: descriptor,
                scriptIndex: scriptIndex,
                session: session,
                pageURL: pageURL,
                budget: budget
            )
        )

        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    return files
}

private func loadBudgetedDeveloperInlineScript(
    descriptor: DeveloperDiscoveredSource,
    scriptIndex: Int,
    session: DeveloperWebViewSession,
    pageURL: String,
    budget: DeveloperSourceCaptureBudget
) async -> DeveloperSourceFile {
    let sourceID = "\(session.id)::\(descriptor.key)"
    let maximumBytes = DeveloperSourceCaptureBudget.maximumInlineSourceBytes
    let reportedCharacterCount = descriptor.inlineSourceCharacterCount ?? 0

    guard reportedCharacterCount <= maximumBytes else {
        await budget.recordOmission()
        return inlineMetadataOnlySource(
            sourceID: sourceID,
            descriptor: descriptor,
            session: session,
            pageURL: pageURL,
            note: "Inline script text was not retained because the page reported \(reportedCharacterCount) UTF-16 characters, above the 2 MB live-WebView per-script capture limit."
        )
    }

    let reservation = await budget.reserve(upTo: maximumBytes)
    guard reservation > 0 else {
        await budget.recordOmission()
        return inlineMetadataOnlySource(
            sourceID: sourceID,
            descriptor: descriptor,
            session: session,
            pageURL: pageURL,
            note: "Inline script text was not retained because the 32 MB Developer Sources refresh budget was already exhausted."
        )
    }

    do {
        let lengthScript = """
        (() => {
          const script = document.scripts[\(scriptIndex)];
          if (!script || script.src) return -1;
          return String(script.textContent || '').length;
        })();
        """
        let rawLength = try await session.webView.evaluateJavaScript(lengthScript)
        guard let number = rawLength as? NSNumber else {
            throw DeveloperSourceInlineCaptureError.scriptUnavailable
        }

        let characterCount = number.intValue
        guard characterCount >= 0 else {
            throw DeveloperSourceInlineCaptureError.scriptUnavailable
        }
        guard characterCount <= maximumBytes else {
            await budget.release(reservation: reservation, countAsOmission: true)
            return inlineMetadataOnlySource(
                sourceID: sourceID,
                descriptor: descriptor,
                session: session,
                pageURL: pageURL,
                note: "Inline script text was not retained because the live page contains \(characterCount) UTF-16 characters, above the 2 MB live-WebView per-script capture limit."
            )
        }

        var data = Data()
        data.reserveCapacity(min(characterCount, reservation))

        var start = 0
        while start < characterCount {
            guard !Task.isCancelled else { throw CancellationError() }

            let end = min(start + developerInlineCaptureChunkCharacters, characterCount)
            let chunkScript = """
            (() => {
              const script = document.scripts[\(scriptIndex)];
              if (!script || script.src) return null;
              return String(script.textContent || '').slice(\(start), \(end));
            })();
            """
            let rawChunk = try await session.webView.evaluateJavaScript(chunkScript)
            guard let chunk = rawChunk as? String else {
                throw DeveloperSourceInlineCaptureError.scriptUnavailable
            }

            let chunkData = Data(chunk.utf8)
            guard data.count + chunkData.count <= reservation else {
                await budget.release(reservation: reservation, countAsOmission: true)
                return inlineMetadataOnlySource(
                    sourceID: sourceID,
                    descriptor: descriptor,
                    session: session,
                    pageURL: pageURL,
                    note: "Inline script text was not retained because its UTF-8 representation exceeded the available 2 MB per-script or scan-wide capture budget."
                )
            }

            data.append(chunkData)
            start = end

            await Task.yield()
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw DeveloperSourceInlineCaptureError.invalidUTF8
        }

        await budget.commit(reservation: reservation, actualBytes: data.count)
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: session.title,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: descriptor.url,
            kind: descriptor.kind,
            content: content,
            metadataNote: "Inline script text was read from the live WebView in 64 KB character chunks under the shared 32 MB capture budget.",
            resourceByteCount: nil,
            loadError: nil
        )
    } catch is CancellationError {
        await budget.release(reservation: reservation)
        return inlineMetadataOnlySource(
            sourceID: sourceID,
            descriptor: descriptor,
            session: session,
            pageURL: pageURL,
            note: "Inline script capture was cancelled before the complete source body was retained."
        )
    } catch {
        await budget.release(reservation: reservation)
        return DeveloperSourceFile(
            id: sourceID,
            sessionTitle: session.title,
            pageURL: pageURL,
            displayName: descriptor.displayName,
            urlString: descriptor.url,
            kind: descriptor.kind,
            content: nil,
            metadataNote: nil,
            resourceByteCount: nil,
            loadError: error.localizedDescription
        )
    }
}

private func inlineMetadataOnlySource(
    sourceID: String,
    descriptor: DeveloperDiscoveredSource,
    session: DeveloperWebViewSession,
    pageURL: String,
    note: String
) -> DeveloperSourceFile {
    DeveloperSourceFile(
        id: sourceID,
        sessionTitle: session.title,
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

private enum DeveloperSourceInlineCaptureError: LocalizedError {
    case scriptUnavailable
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .scriptUnavailable:
            return "The inline script changed or disappeared before ContextPort could finish its bounded read."
        case .invalidUTF8:
            return "The inline script could not be retained as UTF-8 text."
        }
    }
}
