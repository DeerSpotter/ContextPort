import SwiftUI
import UIKit

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isSavingContext = false

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            HStack(spacing: 10) {
                Button(isSavingContext ? "Saving" : "Save Context") {
                    saveCurrentChatToMemory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingContext)

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

            UIPasteboard.general.string = payload.composerText
            appModel.statusMessage = "Opening new chat with saved context. On iOS 16 the Markdown is inserted or copied for paste."

            Task { @MainActor in
                let inserted = await webViewStore.injectComposerText(payload.composerText)
                if inserted {
                    appModel.statusMessage = "Saved Markdown was inserted into the new chat. Review and send."
                } else {
                    appModel.statusMessage = "Saved Markdown copied. Paste it into the new chat."
                }
                await webViewStore.triggerPendingAttachmentPicker()
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
