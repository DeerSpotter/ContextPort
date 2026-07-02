import PDFKit
import SwiftUI
import UIKit

struct LocalMemoryDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: LocalMemoryEntry

    private let store = LocalMemoryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title2.weight(.bold))

                Button {
                    appModel.startNewChat(using: entry)
                } label: {
                    Label("Start New Chat", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

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
