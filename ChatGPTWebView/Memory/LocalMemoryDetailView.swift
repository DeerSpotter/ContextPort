import PDFKit
import SwiftUI
import UIKit

struct LocalMemoryDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: LocalMemoryEntry

    @State private var launchRequest: MemoryLaunchRequest?

    private let store = LocalMemoryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title2.weight(.bold))

                Button {
                    launchRequest = MemoryLaunchRequest(entries: [entry])
                } label: {
                    Label("Start New Chat", systemImage: "bubble.left.and.bubble.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                memoryInfo

                VStack(alignment: .leading, spacing: 8) {
                    Text("Revision History")
                        .font(.headline)

                    ForEach(entry.orderedRevisions.reversed()) { revision in
                        NavigationLink {
                            LocalMemoryRevisionDetailView(entry: entry, revision: revision)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Revision \(revision.number)")
                                        .font(.body.weight(.semibold))
                                    Text(revision.createdAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(revision.source)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if let messageCount = revision.messageCount {
                                    Text("\(messageCount) msgs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $launchRequest) { request in
            MemoryLaunchSheet(entries: request.entries)
        }
    }

    private var memoryInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Revisions: \(entry.revisionCount)")
            Text("Created: \(entry.createdAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Updated: \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            Text("Project: \(entry.projectName)")
            Text("Latest source: \(entry.source)")
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .textSelection(.enabled)
    }
}

private struct LocalMemoryRevisionDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    let entry: LocalMemoryEntry
    let revision: LocalMemoryRevision

    @State private var isExporting = false
    @State private var exportShareItem: MemoryExportShareItem?

    private let store = LocalMemoryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title3.weight(.bold))

                Button {
                    exportRevision()
                } label: {
                    if isExporting {
                        HStack {
                            ProgressView()
                            Text("Preparing Revision ZIP")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Label("Export Revision", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || !hasExportableFiles)

                revisionInfo

                if let pdfURL = store.pdfURL(for: revision) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PDF")
                            .font(.headline)
                        LocalPDFPreview(url: pdfURL)
                            .frame(height: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Markdown")
                        .font(.headline)

                    if let markdown = store.markdownText(for: revision, in: entry) {
                        Text(markdown)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("Revision Markdown is unavailable on this device.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Revision \(revision.number)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportShareItem) { item in
            MemoryExportShareSheet(url: item.url)
        }
    }

    private var hasExportableFiles: Bool {
        store.pdfURL(for: revision) != nil || store.markdownURL(for: revision) != nil
    }

    private var revisionInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Saved: \(revision.createdAt.formatted(date: .abbreviated, time: .shortened))")
            if let messageCount = revision.messageCount {
                Text("Messages: \(messageCount)")
            }
            Text("Source: \(revision.source)")
            if let pdfFilename = revision.pdfFilename {
                Text("PDF: \(pdfFilename)")
            }
            if let markdownFilename = revision.markdownFilename {
                Text("Markdown: \(markdownFilename)")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .textSelection(.enabled)
    }

    private func exportRevision() {
        guard !isExporting, hasExportableFiles else { return }
        let memory = entry
        let selectedRevision = revision

        isExporting = true
        appModel.statusMessage = "Preparing Revision \(revision.number) ZIP..."

        Task { @MainActor in
            defer { isExporting = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try MemoryExportArchiveBuilder().exportRevision(
                        entry: memory,
                        revision: selectedRevision
                    )
                }.value
                exportShareItem = MemoryExportShareItem(url: url)
                appModel.statusMessage = "Revision \(revision.number) ZIP is ready to share or save to Files."
            } catch {
                appModel.statusMessage = "Revision export failed: \(error.localizedDescription)"
            }
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
