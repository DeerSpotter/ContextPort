import Foundation

private struct AIProfileSessionKey: Hashable {
    let providerID: AIProviderID
    let profileID: String
}

@MainActor
final class ChatGPTProfileSessionPool: ObservableObject {
    private var stores: [AIProfileSessionKey: ChatGPTWebViewStore] = [:]
    private var chatPerformanceConfiguration: ChatPerformanceConfiguration = .disabled

    // ChatGPT compatibility surface for existing callers.
    func store(
        for profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) -> ChatGPTWebViewStore {
        store(
            for: AIProviderID.chatGPT.provider,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
    }

    func persistSession(profileID: String) async {
        await persistSession(providerID: .chatGPT, profileID: profileID)
    }

    func setTypingPriority(_ isTyping: Bool, profileID: String) {
        setTypingPriority(isTyping, providerID: .chatGPT, profileID: profileID)
    }

    func removeSavedProfileSession(profileID: String) async {
        await removeSavedProfileSession(providerID: .chatGPT, profileID: profileID)
    }

    func resetGuest(
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) async {
        await resetGuest(
            provider: AIProviderID.chatGPT.provider,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
    }

    func store(
        for provider: AIProvider,
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) -> ChatGPTWebViewStore {
        let key = AIProfileSessionKey(providerID: provider.id, profileID: profile.id)
        if let existing = stores[key] {
            existing.updateChatPerformanceConfiguration(chatPerformanceConfiguration)
            existing.updateChatGPTMobileWebFallback(
                chatPerformanceConfiguration.chatGPTMobileWebFallbackEnabled
            )
            return existing
        }

        let navigationLabels = ["help", "help center", "support", "claude help center"]
        let existingProfileName = profile.displayName
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if navigationLabels.contains(existingProfileName) {
            onDetectedDisplayName(profile.id, "Current User")
        }

        let cookieVault = ChatGPTProfileCookieVault()
        let browserStateVault = ChatGPTProfileBrowserStateVault()
        let storageProfileID = profile.storageID(for: provider.id)

        // Reject a previously captured provider URL when the full authenticated URL rule
        // no longer accepts it. This clears stale Claude help/support routes without
        // discarding the provider cookie snapshot that may still contain a valid login.
        if profile.kind != .guest,
           let restoredURL = browserStateVault.lastURL(
            profileID: storageProfileID,
            allowedHostSuffixes: provider.authenticatedHostSuffixes
           ),
           !provider.isAuthenticatedContentURL(restoredURL) {
            browserStateVault.delete(profileID: storageProfileID)
        }

        // ChatGPT Current User keeps the shared default WebKit store for upgrade/session
        // compatibility. Other providers use the existing persistent-profile recovery
        // layer over an isolated nonpersistent WebKit store so Google/Apple auth state
        // cannot bleed between Claude, Gemini, and Grok Current User sessions.
        let webViewProfile: ChatGPTProfile
        if provider.id != .chatGPT, profile.kind == .primary {
            webViewProfile = ChatGPTProfile(
                id: profile.id,
                displayName: profile.displayName,
                kind: .saved
            )
        } else {
            webViewProfile = profile
        }

        let initialURL = profile.kind == .saved ? provider.loginURL : nil
        let store = ChatGPTWebViewStore(
            provider: provider,
            initialURL: initialURL,
            profile: webViewProfile,
            cookieVault: cookieVault,
            browserStateVault: browserStateVault,
            onDetectedDisplayName: { profileID, displayName in
                let normalizedName = displayName
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if navigationLabels.contains(normalizedName) {
                    onDetectedDisplayName(profileID, "Current User")
                    return
                }
                onDetectedDisplayName(profileID, displayName)
            }
        )
        store.updateChatPerformanceConfiguration(chatPerformanceConfiguration)
        store.updateChatGPTMobileWebFallback(
            chatPerformanceConfiguration.chatGPTMobileWebFallbackEnabled
        )
        stores[key] = store
        return store
    }

    func updateChatPerformanceConfiguration(_ configuration: ChatPerformanceConfiguration) {
        guard chatPerformanceConfiguration != configuration else {
            return
        }

        chatPerformanceConfiguration = configuration
        for store in stores.values {
            store.updateChatPerformanceConfiguration(configuration)
            store.updateChatGPTMobileWebFallback(configuration.chatGPTMobileWebFallbackEnabled)
        }
    }

    func persistSession(providerID: AIProviderID, profileID: String) async {
        let key = AIProfileSessionKey(providerID: providerID, profileID: profileID)
        guard let store = stores[key] else { return }
        await store.persistProfileSession()
    }

    func persistAllSessions() async {
        for store in stores.values {
            await store.persistProfileSession()
        }
    }

    func setTypingPriority(
        _ isTyping: Bool,
        providerID: AIProviderID,
        profileID: String
    ) {
        let key = AIProfileSessionKey(providerID: providerID, profileID: profileID)
        stores[key]?.setTypingPriority(isTyping)
    }

    func removeSavedProfileSession(providerID: AIProviderID, profileID: String) async {
        let key = AIProfileSessionKey(providerID: providerID, profileID: profileID)
        let storageProfileID = "\(providerID.rawValue)::\(profileID)"

        guard let store = stores.removeValue(forKey: key) else {
            let cookieVault = ChatGPTProfileCookieVault()
            let browserStateVault = ChatGPTProfileBrowserStateVault()
            cookieVault.delete(profileID: storageProfileID)
            browserStateVault.delete(profileID: storageProfileID)
            if providerID == .chatGPT {
                cookieVault.delete(profileID: profileID)
                browserStateVault.delete(profileID: profileID)
            }
            return
        }

        await store.removeSavedProfileSession()
    }

    func resetGuest(
        provider: AIProvider,
        profile: ChatGPTProfile,
        onDetectedDisplayName: @escaping (String, String) -> Void
    ) async {
        let store = store(
            for: provider,
            profile: profile,
            onDetectedDisplayName: onDetectedDisplayName
        )
        await store.resetGuestSession()
    }
}
