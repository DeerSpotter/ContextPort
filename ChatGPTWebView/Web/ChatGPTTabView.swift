import SwiftUI
import UIKit

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isSavingContext = false
    @State private var isPastingContext = false
    @State private var pendingPasteContextText: String?
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
                    } else {
                        saveCurrentChatToMemory()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingContext || isPastingContext)

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
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            let payload = PendingLocalMemoryAttachment.consumePayload()
            webViewStore.startNewChatWithPendingUploadURLs(payload?.fileURLs ?? [])

            guard let payload else { return }

            if let composerText = payload.composerText, !composerText.isEmpty {
                UIPasteboard.general.string = composerText
                pendingPasteContextText = composerText
                pendingPasteContextID = UUID()
                appModel.statusMessage = "Saved Markdown copied. Tap Paste Context to insert it, or continue without it."
                watchForConversationStartWithoutPaste(pendingPasteContextID)
            } else if !payload.fileURLs.isEmpty {
                appModel.statusMessage = "Opening new chat. Tap +, choose Files, then select the exported file from ChatGPT Memory."
                Task { @MainActor in
                    await webViewStore.triggerPendingAttachmentPicker()
                }
            }
        }
    }

    private var contextButtonTitle: String {
        if isPastingContext { return "Pasting" }
        if pendingPasteContextText != nil { return "Paste Context" }
        return isSavingContext ? "Saving" : "Save Context"
    }

    private func pastePendingContext(_ text: String) {
        guard !isPastingContext else { return }
        isPastingContext = true
        UIPasteboard.general.string = text

        Task { @MainActor in
            defer { isPastingContext = false }
            let inserted = await webViewStore.injectComposerText(text)
            if inserted {
                pendingPasteContextText = nil
                pendingPasteContextID = UUID()
                appModel.statusMessage = "Pasted saved context. Review and send."
            } else {
                appModel.statusMessage = "Context copied. Tap the ChatGPT composer and paste it manually."
            }
        }
    }

    private func watchForConversationStartWithoutPaste(_ id: UUID) {
        Task { @MainActor in
            for _ in 0..<90 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard pendingPasteContextID == id, pendingPasteContextText != nil else { return }
                if await webViewStore.hasStartedConversation() {
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
