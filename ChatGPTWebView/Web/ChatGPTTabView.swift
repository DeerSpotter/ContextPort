import SwiftUI
import UIKit

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isExportingContext = false

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SaveContextOverlayButton(isExporting: isExportingContext) {
                        exportCurrentChatPDF()
                    }

                    CircleIconButton(
                        systemImage: "stop.circle",
                        accessibilityLabel: "Stop ChatGPT activity",
                        accessibilityHint: "Attempts to stop the current WebView activity quickly"
                    ) {
                        webViewStore.stopCurrentActivity()
                    }

                    CircleIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Reload ChatGPT session",
                        accessibilityHint: "Reloads the current ChatGPT WebView page if the app feels frozen"
                    ) {
                        webViewStore.reloadCurrentSession()
                    }
                }

                if appModel.pendingLocalStartContext != nil {
                    PendingContextBanner(
                        onCopy: {
                            UIPasteboard.general.string = appModel.pendingLocalStartContext
                            appModel.statusMessage = "Copied saved context reminder again."
                        },
                        onClear: {
                            appModel.clearPendingLocalStartContext()
                        }
                    )
                }
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            webViewStore.startNewChat()
        }
    }

    private func exportCurrentChatPDF() {
        guard !isExportingContext else {
            return
        }

        isExportingContext = true
        appModel.statusMessage = "Exporting current chat to local PDF..."

        Task { @MainActor in
            defer { isExportingContext = false }

            do {
                let export = try await webViewStore.exportCurrentPagePDF()
                let result = try LocalMemoryStore().saveExportedPDF(
                    projectName: appModel.selectedProject?.name ?? "ChatGPT-WebView",
                    title: export.title,
                    pdfData: export.data,
                    sourceURL: export.sourceURL
                )
                appModel.reloadLocalMemory()
                appModel.statusMessage = result.message
            } catch {
                appModel.statusMessage = "PDF export failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct SaveContextOverlayButton: View {
    let isExporting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isExporting {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(isExporting ? "Saving" : "Save Context")
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(height: 36)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 2)
        .disabled(isExporting)
        .accessibilityLabel("Export current chat to local PDF memory")
        .accessibilityHint("Exports the current ChatGPT page as a local PDF under the chat title")
    }
}

private struct PendingContextBanner: View {
    let onCopy: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.caption.weight(.semibold))
            Text("Saved PDF context selected. Paste the reminder into ChatGPT, then use the saved PDF as context.")
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Copy") {
                onCopy()
            }
            .font(.caption.weight(.semibold))
            Button {
                onClear()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundColor(.primary)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 2)
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
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 2)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
