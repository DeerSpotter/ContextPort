import SwiftUI
import UIKit

struct ChatGPTTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var webViewStore = ChatGPTWebViewStore()
    @State private var isShowingSaveContext = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            SecureChatGPTWebView(store: webViewStore)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            HStack(spacing: 10) {
                CircleIconButton(
                    systemImage: "tray.and.arrow.down",
                    accessibilityLabel: "Save context",
                    accessibilityHint: "Opens a quick save sheet for saving ChatGPT context into memory"
                ) {
                    isShowingSaveContext = true
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
        .sheet(isPresented: $isShowingSaveContext) {
            SaveContextSheet()
                .environmentObject(appModel)
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
        .overlay(
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .shadow(radius: 2)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}

private struct SaveContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appModel: AppModel
    @State private var title = "ChatGPT context"
    @State private var content = ""
    @State private var tags = "chatgpt, context"

    var body: some View {
        NavigationView {
            Form {
                Section("Save Context") {
                    Text("Save the important part of the current ChatGPT session into the selected memory project. This avoids scraping the ChatGPT page while still making context capture fast.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    TextField("Title", text: $title)

                    TextField("Context", text: $content, axis: .vertical)
                        .lineLimit(6...14)

                    TextField("Tags, comma separated", text: $tags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        if let clipboardText = UIPasteboard.general.string,
                           !clipboardText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            content = clipboardText
                        } else {
                            appModel.statusMessage = "Clipboard does not contain text to paste."
                        }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                Section("Destination") {
                    Text(appModel.selectedProject?.name ?? "No memory project selected")
                        .foregroundColor(appModel.selectedProject == nil ? .secondary : .primary)

                    if appModel.selectedProject == nil {
                        Text("Open the Memory tab and create or select a project before saving context.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Save Context")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await appModel.saveMemory(title: title, content: content, tags: tags)
                            dismiss()
                        }
                    }
                    .disabled(appModel.isBusy || appModel.selectedProject == nil || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
