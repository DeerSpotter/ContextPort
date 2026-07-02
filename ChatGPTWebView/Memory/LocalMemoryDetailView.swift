import PDFKit
import SwiftUI
import UIKit

struct LocalMemoryDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: LocalMemoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.title)
                        .font(.title2.weight(.bold))
                    Text("Project: \(entry.projectName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Source: \(entry.source) • Importance: \(entry.importance)/5")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !entry.tags.isEmpty {
                        Text(entry.tags.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        appModel.startNewChat(using: entry)
                    } label: {
                        Label("Start New Chat", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        UIPasteboard.general.string = entry.content
                        appModel.statusMessage = "Copied saved context text."
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Text("Start New Chat copies this saved context to the clipboard and switches to ChatGPT. Paste it into the new chat to use this PDF-backed local memory as context.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let pdfURL = appModel.localPDFURL(for: entry) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Saved PDF")
                                .font(.headline)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = pdfURL.lastPathComponent
                                appModel.statusMessage = "Copied local PDF filename."
                            } label: {
                                Label("Copy Name", systemImage: "doc.on.doc")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                        }

                        LocalPDFPreview(url: pdfURL)
                            .frame(height: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )
                    }
                } else {
                    Text("No local PDF file was found for this memory entry. The saved text is still available below.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Saved Text")
                        .font(.headline)
                    Text(entry.content)
                        .font(.footnote)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Saved Context")
        .navigationBarTitleDisplayMode(.inline)
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
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
