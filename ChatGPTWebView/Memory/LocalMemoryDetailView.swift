import PDFKit
import SwiftUI
import UIKit

struct LocalMemoryDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: LocalMemoryEntry

    @State private var showNewChatFileSelection = false
    @State private var exportMessage: String?

    private let store = LocalMemoryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title2.weight(.bold))

                Button {
                    showNewChatFileSelection = true
                } label: {
                    Label("Start New Chat", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let exportMessage {
                    Text(exportMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                }

                fileInfo

                if let pdfURL = store.pdfURL(for: entry) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PDF")
                            .font(.headline)
                        LocalPDFPreview(url: pdfURL)
                            .frame(height: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
                    }
                }

                if let markdown = store.markdownText(for: entry) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Markdown")
                            .font(.headline)
                        Text(markdown)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Saved Chat")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Download files for this new chat",
            isPresented: $showNewChatFileSelection,
            titleVisibility: .visible
        ) {
            Button("PDF + Markdown") {
                startNewChat(exportPDF: true, exportMarkdown: true)
            }
            Button("PDF only") {
                startNewChat(exportPDF: true, exportMarkdown: false)
            }
            Button("Markdown only") {
                startNewChat(exportPDF: false, exportMarkdown: true)
            }
            Button("No file, insert Markdown text") {
                startNewChat(exportPDF: false, exportMarkdown: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only this saved chat will be downloaded into app storage. After ChatGPT opens, tap +, choose Files, then select the exported file from ChatGPT Memory.")
        }
    }

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let messageCount = entry.messageCount {
                Text("Messages: \(messageCount)")
            }
            if let pdfFilename = entry.pdfFilename {
                Text("PDF: \(pdfFilename)")
            }
            if let markdownFilename = entry.markdownFilename {
                Text("Markdown: \(markdownFilename)")
            }
            Text("Source: \(entry.source)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .textSelection(.enabled)
    }

    private func startNewChat(exportPDF: Bool, exportMarkdown: Bool) {
        do {
            var exportedURLs: [URL] = []

            if exportPDF {
                exportedURLs.append(try store.exportPDFToFiles(for: entry))
            }

            if exportMarkdown {
                exportedURLs.append(try store.exportMarkdownToFiles(for: entry))
            }

            PendingLocalMemoryAttachment.mark(entry, fileURLs: exportedURLs)
            appModel.startNewChat(using: entry)

            if exportedURLs.isEmpty {
                exportMessage = "Opening new chat. Saved Markdown will be inserted or copied for paste."
                appModel.statusMessage = exportMessage ?? "Opening new chat."
            } else {
                let fileList = exportedURLs.map(\.lastPathComponent).joined(separator: ", ")
                exportMessage = "Downloaded for this chat: \(fileList). In ChatGPT, tap + > Files > ChatGPT Memory."
                appModel.statusMessage = exportMessage ?? "Downloaded selected files for this chat."
            }
        } catch {
            exportMessage = "Could not download selected file: \(error.localizedDescription)"
            appModel.statusMessage = exportMessage ?? "Download failed."
        }
    }
}

private struct LocalPDFPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}
