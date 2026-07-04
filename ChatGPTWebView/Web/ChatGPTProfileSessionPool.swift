import Foundation

@MainActor
final class ChatGPTProfileSessionPool: ObservableObject {
    private var stores: [String: ChatGPTWebViewStore] = [:]

    func store(
        for profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) -> ChatGPTWebViewStore {
        if let existing = stores[profile.id] {
            return existing
        }

        let loginURL = URL(string: "https://chatgpt.com/auth/login")
        let initialURL = profile.kind == .saved ? loginURL : nil
        let store = ChatGPTWebViewStore(
            initialURL: initialURL,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
        stores[profile.id] = store
        return store
    }

    func persistSession(profileID: String) async {
        guard let store = stores[profileID] else { return }
        await store.persistProfileSession()
    }

    func persistAllSessions() async {
        for store in stores.values {
            await store.persistProfileSession()
        }
    }

    func setTypingPriority(_ isTyping: Bool, profileID: String) {
        stores[profileID]?.setTypingPriority(isTyping)
    }

    func removeSavedProfileSession(profileID: String) async {
        guard let store = stores.removeValue(forKey: profileID) else {
            ChatGPTProfileCookieVault().delete(profileID: profileID)
            ChatGPTProfileBrowserStateVault().delete(profileID: profileID)
            return
        }

        await store.removeSavedProfileSession()
    }

    func resetGuest(
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) async {
        let store = store(for: profile, onDetectedDisplayName: onDetectedDisplayName)
        await store.resetGuestSession()
    }
}
