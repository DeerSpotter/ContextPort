import SwiftUI

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var profileManager: ChatGPTProfileManager
    @StateObject private var sessionPool = ChatGPTProfileSessionPool()
    @State private var isSavingContext = false
    @State private var isPastingContext = false
    @State private var isAttachingFiles = false
    @State private var pendingPasteContextText: String?
    @State private var pendingAttachFileURLs: [URL] = []
    @State private var pendingPasteContextID = UUID()
    @State private var lastProfileID = ChatGPTProfile.primaryID

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
                .id(profileManager.activeProfileID)
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)

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

                CircleIconButton(systemImage: "stop.circle", accessibilityLabel: "Stop ChatGPT activity", accessibilityHint: "Stops current WebView activity") {
                    webViewStore.stopCurrentActivity()
                }

                CircleIconButton(systemImage: "arrow.clockwise", accessibilityLabel: "Reload ChatGPT session", accessibilityHint: "Reloads the current WebView page") {
                    webViewStore.reloadCurrentSession()
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
        .onAppear {
            lastProfileID = profileManager.activeProfileID
            handleActiveProfileAppearance()
            handlePendingMemoryStart()
        }
        .onChange(of: profileManager.activeProfileID) { newProfileID in
            let previousProfileID = lastProfileID
            lastProfileID = newProfileID
            handleProfileChange(from: previousProfileID)
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            handlePendingMemoryStart()
        }
    }

    private var webViewStore: ChatGPTWebViewStore {
        sessionPool.store(
            for: profileManager.activeProfile,
            onDetectedDisplayName: { profileID, displayName in
                profileManager.updateDetectedDisplayName(displayName, for: profileID)
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

    private func handleActiveProfileAppearance() {
        guard profileManager.activeProfile.kind == .guest else { return }
        Task { @MainActor in
            await sessionPool.resetGuest(
                profile: profileManager.guestProfile,
                onDetectedDisplayName: { _, _ in }
            )
        }
    }

    private func handleProfileChange(from previousProfileID: String) {
        let activeProfile = profileManager.activeProfile

        Task { @MainActor in
            await sessionPool.persistSession(profileID: previousProfileID)

            if activeProfile.kind == .guest {
                await sessionPool.resetGuest(
                    profile: activeProfile,
                    onDetectedDisplayName: { _, _ in }
                )
            }
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
            appModel.statusMessage = "Saved Markdown is ready. Tap Paste Context to insert it, or continue without it."
            watchForConversationStartWithoutPaste(pendingPasteContextID)
        } else if !payload.fileURLs.isEmpty {
            pendingAttachFileURLs = payload.fileURLs
            pendingPasteContextText = nil
            appModel.statusMessage = "Files are ready. Tap Attach Files to attach from app Memory."
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
                appModel.statusMessage = "Pasted saved context. Review and send."
            } else {
                appModel.statusMessage = "Could not paste yet. Wait for ChatGPT to finish loading, then tap Paste Context again."
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
                appModel.statusMessage = "Attached files from app Memory. Review the new chat before sending."
            } else {
                appModel.statusMessage = "Direct memory attach was attempted. If the file card did not appear, return to Memory and try again."
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
        appModel.statusMessage = "Saving chat to Memory..."
        Task { @MainActor in
            defer { isSavingContext = false }
            do {
                let export = try await webViewStore.exportCurrentConversation()
                let result = try LocalMemoryStore().saveExportedConversation(projectName: appModel.selectedProject?.name ?? "ChatGPT-WebView", title: export.title, markdownText: export.markdown, pdfData: export.pdfData, sourceURL: export.sourceURL, messageCount: export.messageCount, exportedAt: export.exportedAt)
                appModel.reloadLocalMemory()
                appModel.statusMessage = result.message
            } catch {
                appModel.statusMessage = "Save Context failed: \(error.localizedDescription)"
            }
        }
    }
}

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
