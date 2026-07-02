import SwiftUI
import UIKit

struct ChatGPTTabView: View {
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isExportingContext = false
    @State private var shareItems: [Any] = []
    @State private var isShowingShareSheet = false
    @State private var exportAlert: ExportAlert?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            HStack(spacing: 10) {
                CircleIconButton(
                    systemImage: isExportingContext ? "hourglass" : "tray.and.arrow.down",
                    accessibilityLabel: "Save ChatGPT context",
                    accessibilityHint: "Exports the current ChatGPT conversation to local Markdown and PDF files"
                ) {
                    exportCurrentConversation()
                }
                .disabled(isExportingContext)
                .opacity(isExportingContext ? 0.55 : 1.0)

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
            .padding(.top, 12)
            .padding(.trailing, 12)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            ExportShareSheet(activityItems: shareItems)
        }
        .alert(item: $exportAlert) { alert in
            Alert(title: Text(alert.title),
                  message: Text(alert.message),
                  dismissButton: .default(Text("OK")))
        }
    }

    private func exportCurrentConversation() {
        guard !isExportingContext else {
            return
        }

        isExportingContext = true

        Task {
            defer {
                isExportingContext = false
            }

            do {
                let result = try await webViewStore.exportCurrentConversation()
                shareItems = result.shareURLs
                isShowingShareSheet = true
            } catch {
                exportAlert = ExportAlert(title: "Save Context Failed",
                                          message: error.localizedDescription)
            }
        }
    }
}

private struct ExportAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct ExportShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
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
