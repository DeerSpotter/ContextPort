import Foundation

struct ChatGPTProfileOriginBrowserState: Codable {
    var localStorage: [String: String]
}

struct ChatGPTProfileBrowserState: Codable {
    var origins: [String: ChatGPTProfileOriginBrowserState]
    var lastURL: String?
    var capturedAt: Date

    static let empty = ChatGPTProfileBrowserState(
        origins: [:],
        lastURL: nil,
        capturedAt: .distantPast
    )
}

final class ChatGPTProfileBrowserStateVault {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        directoryURL = baseURL
            .appendingPathComponent("ChatGPTWebView", isDirectory: true)
            .appendingPathComponent("ProfileBrowserState", isDirectory: true)

        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func load(profileID: String) -> ChatGPTProfileBrowserState {
        let url = fileURL(profileID: profileID)
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(ChatGPTProfileBrowserState.self, from: data) else {
            return .empty
        }
        return state
    }

    func save(
        origin: String,
        localStorage: [String: String],
        lastURL: String?,
        profileID: String
    ) {
        guard !origin.isEmpty else { return }

        var state = load(profileID: profileID)
        state.origins[origin] = ChatGPTProfileOriginBrowserState(localStorage: localStorage)
        state.lastURL = lastURL ?? state.lastURL
        state.capturedAt = Date()

        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(
            to: fileURL(profileID: profileID),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        )
    }

    func lastURL(profileID: String) -> URL? {
        guard let value = load(profileID: profileID).lastURL,
              let url = URL(string: value),
              url.scheme?.lowercased() == "https" else {
            return nil
        }
        return url
    }

    func documentStartRestoreScript(profileID: String) -> String? {
        let states = load(profileID: profileID).origins.mapValues(\.localStorage)
        guard !states.isEmpty,
              let data = try? JSONEncoder().encode(states),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return """
        (() => {
          const statesByOrigin = \(json);
          try {
            const values = statesByOrigin[window.location.origin];
            if (!values) return;
            for (const [key, value] of Object.entries(values)) {
              try { window.localStorage.setItem(key, value); } catch (_) {}
            }
          } catch (_) {}
        })();
        """
    }

    func delete(profileID: String) {
        try? fileManager.removeItem(at: fileURL(profileID: profileID))
    }

    private func fileURL(profileID: String) -> URL {
        let safeID = profileID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directoryURL.appendingPathComponent("\(safeID).json", isDirectory: false)
    }
}
