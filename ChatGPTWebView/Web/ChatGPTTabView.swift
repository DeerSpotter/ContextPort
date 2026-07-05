import SwiftUI
import UIKit

struct AIChatTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var providerManager: AIProviderManager
    @EnvironmentObject private var profileManager: ChatGPTProfileManager
    @EnvironmentObject private var sessionPool: ChatGPTProfileSessionPool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSavingContext = false
    @State private var isPastingContext = false
    @State private var isAttachingFiles = false
    @State private var isKeyboardVisible = false
    @State private var pendingPasteContextText: String?
    @State private var pendingAttachFileURLs: [URL] = []
    @State private var pendingPasteContextID = UUID()
    @State private var lastProviderID = AIProviderID.chatGPT
    @State private var lastProfileID = ChatGPTProfile.primaryID

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
                .id(activeSessionID)
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            if !isKeyboardVisible {
                HStack(spacing: 10) {
                    Button(contextButtonTitle) {
                        if let pendingPasteContextText {
                            pastePendingContext(pendingPasteContextText)
                        } else if !pendingAttachFileURLs.isEmpty {
                            attachPendingFiles(pendingAttachFileURLs)
                        } else {
                            saveCurrentChatToMemory()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingContext || isPastingContext || isAttachingFiles)

                    CircleIconButton(
                        systemImage: "stop.circle",
                        accessibilityLabel: "Stop \(provider.displayName) activity",
                        accessibilityHint: "Stops current WebView activity"
                    ) {
                        webViewStore.stopCurrentActivity()
                    }

                    CircleIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Reload \(provider.displayName) session",
                        accessibilityHint: "Reloads the current WebView page"
                    ) {
                        webViewStore.reloadCurrentSession()
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
            }
        }
        .onAppear {
            lastProviderID = provider.id
            lastProfileID = activeProfile.id
            handleActiveSessionAppearance()
            handlePendingMemoryStart()
        }
        .onChange(of: activeSessionID) { _ in
            let previousProviderID = lastProviderID
            let previousProfileID = lastProfileID
            lastProviderID = provider.id
            lastProfileID = activeProfile.id
            handleSessionChange(
                fromProviderID: previousProviderID,
                previousProfileID: previousProfileID
            )
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            handlePendingMemoryStart()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            persistAllLiveProfileSessions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            setTypingPriority(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            setTypingPriority(false)
        }
    }

    private var provider: AIProvider {
        providerManager.activeProvider
    }

    private var activeProfile: ChatGPTProfile {
        profileManager.activeProfile(for: provider.id)
    }

    private var activeSessionID: String {
        "\(provider.id.rawValue)::\(activeProfile.id)"
    }

    private var webViewStore: ChatGPTWebViewStore {
        let providerID = provider.id
        return sessionPool.store(
            for: provider,
            profile: activeProfile,
            onDetectedDisplayName: { profileID, displayName in
                profileManager.updateDetectedDisplayName(
                    displayName,
                    for: profileID,
                    providerID: providerID
                )
            }
        )
    }

    private var contextButtonTitle: String {
        if isPastingContext { return "Pasting" }
        if isAttachingFiles { return "Attaching" }
        if pendingPasteContextText != nil { return "Paste Context" }
        if !pendingAttachFileURLs.isEmpty { return "Attach Files" }
        return isSavingContext ? "Saving" : "Save Context"
    }

    private func setTypingPriority(_ isTyping: Bool) {
        isKeyboardVisible = isTyping
        sessionPool.setTypingPriority(
            isTyping,
            providerID: provider.id,
            profileID: activeProfile.id
        )
    }

    private func handleActiveSessionAppearance() {
        guard activeProfile.kind == .guest else { return }
        Task { @MainActor in
            await sessionPool.resetGuest(
                provider: provider,
                profile: activeProfile,
                onDetectedDisplayName: { _, _ in }
            )
        }
    }

    private func handleSessionChange(
        fromProviderID previousProviderID: AIProviderID,
        previousProfileID: String
    ) {
        let activeProvider = provider
        let newActiveProfile = activeProfile
        isKeyboardVisible = false

        sessionPool.setTypingPriority(
            false,
            providerID: previousProviderID,
            profileID: previousProfileID
        )
        sessionPool.setTypingPriority(
            false,
            providerID: activeProvider.id,
            profileID: newActiveProfile.id
        )

        Task { @MainActor in
            await sessionPool.persistSession(
                providerID: previousProviderID,
                profileID: previousProfileID
            )

            if newActiveProfile.kind == .guest {
                await sessionPool.resetGuest(
                    provider: activeProvider,
                    profile: newActiveProfile,
                    onDetectedDisplayName: { _, _ in }
                )
            }
        }
    }

    private func persistAllLiveProfileSessions() {
        Task { @MainActor in
            await sessionPool.persistAllSessions()
        }
    }

    private func handlePendingMemoryStart() {
        guard let payload = PendingLocalMemoryAttachment.consumePayload() else {
            return
        }

        webViewStore.startNewChatWithPendingUploadURLs(payload.fileURLs)

        if let composerText = payload.composerText, !composerText.isEmpty {
            pendingPasteContextText = composerText
            pendingAttachFileURLs = []
            pendingPasteContextID = UUID()
            appModel.statusMessage = "Saved Markdown is ready for \(provider.displayName). Tap Paste Context to insert it, or continue without it."
            watchForConversationStartWithoutPaste(pendingPasteContextID)
        } else if !payload.fileURLs.isEmpty {
            pendingAttachFileURLs = payload.fileURLs
            pendingPasteContextText = nil
            appModel.statusMessage = "Files are ready. Tap Attach Files to attach from app Memory to \(provider.displayName)."
        }
    }

    private func pastePendingContext(_ text: String) {
        guard !isPastingContext else { return }
        isPastingContext = true

        Task { @MainActor in
            defer { isPastingContext = false }
            let inserted = await webViewStore.injectComposerText(text)
            if inserted {
                pendingPasteContextText = nil
                pendingPasteContextID = UUID()
                appModel.statusMessage = "Pasted saved context into \(provider.displayName). Review and send."
            } else {
                appModel.statusMessage = "Could not paste yet. Wait for \(provider.displayName) to finish loading, then tap Paste Context again."
            }
        }
    }

    private func attachPendingFiles(_ urls: [URL]) {
        guard !isAttachingFiles else { return }
        isAttachingFiles = true
        webViewStore.preparePendingUploadURLs(urls)

        Task { @MainActor in
            defer { isAttachingFiles = false }
            let memoryAttachWorked = await webViewStore.injectFilesIntoChatGPTUpload(urls)
            pendingAttachFileURLs = []

            if memoryAttachWorked {
                appModel.statusMessage = "Attached files from app Memory to \(provider.displayName). Review the new chat before sending."
            } else {
                appModel.statusMessage = "Direct memory attach was attempted in \(provider.displayName). If the file card did not appear, return to Memory and try again."
            }
        }
    }

    private func watchForConversationStartWithoutPaste(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let baselineUserMessages = await webViewStore.userMessageCount()

            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard pendingPasteContextID == id, pendingPasteContextText != nil else { return }
                guard !isKeyboardVisible else { continue }

                let currentUserMessages = await webViewStore.userMessageCount()
                if currentUserMessages > baselineUserMessages {
                    pendingPasteContextText = nil
                    pendingPasteContextID = UUID()
                    appModel.statusMessage = "Continuing without pasted Memory context. Save Context is available again."
                    return
                }
            }
        }
    }

    private func saveCurrentChatToMemory() {
        guard !isSavingContext else { return }
        isSavingContext = true
        appModel.statusMessage = "Saving \(provider.displayName) chat to Memory..."
        Task { @MainActor in
            defer { isSavingContext = false }
            do {
                let export = try await webViewStore.exportCurrentConversation()
                let result = try LocalMemoryStore().saveExportedConversation(
                    projectName: appModel.selectedProject?.name ?? "ChatGPT-WebView",
                    title: export.title,
                    markdownText: export.markdown,
                    pdfData: export.pdfData,
                    sourceURL: export.sourceURL,
                    messageCount: export.messageCount,
                    exportedAt: export.exportedAt
                )
                appModel.reloadLocalMemory()
                appModel.statusMessage = result.message
            } catch {
                appModel.statusMessage = "Save Context failed: \(error.localizedDescription)"
            }
        }
    }
}

typealias ChatGPTTabView = AIChatTabView

private struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(radius: 2)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
