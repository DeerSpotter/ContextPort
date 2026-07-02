import SwiftUI
import UIKit

struct LocalMemoryVaultCard: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var title = "Local ChatGPT session context"
    @State private var content = ""
    @State private var source = "chatgpt_web"
    @State private var tags = "local, session-import, chatgpt-webview"
    @State private var searchQuery = ""
    @State private var importance = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext.fill")
                    .foregroundColor(.accentColor)
                Text("Local Device Memory Vault")
                    .font(.headline)
            }

            Text("Save large context as a local PDF document first. Tap any saved title below to open the PDF-backed memory and start a new chat from it.")
                .font(.footnote)
                .foregroundColor(.secondary)

            HStack(spacing: 10) {
                LocalMemoryMetric(title: "Local PDFs", value: "\(appModel.localMemoryEntries.count)")
                LocalMemoryMetric(title: "Search results", value: "\(appModel.localMemorySearchResults.count)")
            }

            TextField("Chat title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Source", text: $source)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Tags, comma separated", text: $tags)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Stepper("Importance: \(importance)/5", value: $importance, in: 1...5)

            Text("Full chat/context text")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            TextEditor(text: $content)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )

            HStack(spacing: 10) {
                Button {
                    if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                        content = pasted
                        appModel.statusMessage = "Pasted clipboard into Local Vault import."
                    } else {
                        appModel.statusMessage = "Clipboard does not contain text."
                    }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    appModel.saveLocalSessionContext(
                        title: title,
                        content: content,
                        source: source,
                        tagsText: tags,
                        importance: importance
                    )
                } label: {
                    Label("Save PDF", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            HStack(spacing: 10) {
                TextField("Search local PDF memory", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    appModel.searchLocalMemory(query: searchQuery)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button {
                    appModel.renderLocalProjectContext()
                } label: {
                    Label("Render Context", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    if appModel.localRenderedContext.isEmpty {
                        appModel.renderLocalProjectContext()
                    }
                    UIPasteboard.general.string = appModel.localRenderedContext
                    appModel.statusMessage = "Copied local rendered context."
                } label: {
                    Label("Copy Render", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(appModel.localMemoryEntries.isEmpty)
            }

            if let result = appModel.lastLocalMemorySave {
                NavigationLink {
                    LocalMemoryDetailView(entry: result.entry)
                        .environmentObject(appModel)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(result.message)
                            .font(.caption.weight(.semibold))
                        LocalMemoryInfoRow(label: "Open saved PDF", value: result.entry.title)
                        LocalMemoryInfoRow(label: "Total local", value: "\(result.totalCount)")
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            if !appModel.localMemorySearchResults.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Saved Contexts")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    ForEach(appModel.localMemorySearchResults.prefix(10)) { entry in
                        NavigationLink {
                            LocalMemoryDetailView(entry: entry)
                                .environmentObject(appModel)
                        } label: {
                            LocalMemoryResultRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct LocalMemoryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct LocalMemoryInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct LocalMemoryResultRow: View {
    let entry: LocalMemoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.pdfFilename == nil ? "doc.text" : "doc.richtext")
                    .foregroundColor(.accentColor)
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(entry.importance)/5")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Text(entry.content)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(3)

            HStack {
                if let pdfFilename = entry.pdfFilename {
                    Text(pdfFilename)
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !entry.tags.isEmpty {
                    Text(entry.tags.prefix(4).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
