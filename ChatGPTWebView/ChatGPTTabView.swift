import SwiftUI

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isSavingContext = false
    @State private var isPastingContext = false
    @State private var isAttachingFiles = false
    @State private var pendingPasteContextText: String?
    @State private var pendingAttachFileURLs: [URL] = []
    @State private var pendingPasteContextID = UUID()

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
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
            handlePendingMemoryStart()
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            handlePendingMemoryStart()
        }
    }

    private var contextButtonTitle: String {
        if isPastingContext { return "Pasting" }
        if isAttachingFiles { return "Attaching" }
        if pendingPasteContextText != nil { return "Paste Context" }
        if !pendingAttachFileURLs.isEmpty { return "Attach Files" }
        return isSavingContext ? "Saving" : "Save Context"
    }

    private func handlePendingMemoryStart() {
        let payload = PendingLocalMemoryAttachment.consumePayload()
        webViewStore.startNewChatWithPendingUploadURLs(payload?.fileURLs ?? [])

        guard let payload else { return }

        if let composerText = payload.composerText, !composerText.isEmpty {
            pendingPasteContextText = composerText
            pendingAttachFileURLs = []
            pendingPasteContextID = UUID()
            appModel.statusMessage = "Saved Markdown is ready. Tap Paste Context to insert it, or continue without it."
            watchForConversationStartWithoutPaste(pendingPasteContextID)
        } else if !payload.fileURLs.isEmpty {
            pendingAttachFileURLs = payload.fileURLs
            pendingPasteContextText = nil
            appModel.statusMessage = "Files are ready. Tap Attach Files to try direct memory attach."
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
            if memoryAttachWorked {
                pendingAttachFileURLs = []
                appModel.statusMessage = "Attached files from app Memory. Review the new chat before sending."
                return
            }

            webViewStore.preparePendingUploadURLs(urls)
            let opened = await webViewStore.activateComposerAndOpenAttachmentPicker()
            if opened {
                pendingAttachFileURLs = []
                appModel.statusMessage = "Attach menu opened. Choose Files, then select the exported PDF or Markdown from ChatGPT Memory."
            } else {
                appModel.statusMessage = "Could not open attach yet. Wait for ChatGPT to finish loading, then tap Attach Files again."
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
