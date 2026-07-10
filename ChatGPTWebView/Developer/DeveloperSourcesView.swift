import Foundation
import SwiftUI
import UIKit

struct DeveloperSourcesView: View {
    let isActive: Bool

    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var profileSessionPool: ChatGPTProfileSessionPool
    @StateObject private var model = DeveloperSourcesModel()
    @State private var searchText = ""
    @State private var isSavingToMemory = false
    @State private var lastSavedSnapshotFingerprint: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        if model.isScanning || model.isSearching || isSavingToMemory {
                            ProgressView()
                        }

                        Text(model.status)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }

                    Button {
                        model.scan(sessions: profileSessionPool.developerSourceSessions())
                    } label: {
                        Label("Refresh Loaded Sources", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isScanning || isSavingToMemory)

                    Button {
                        saveSourcesToMemory()
                    } label: {
                        Label(
                            isCurrentSnapshotSaved ? "Saved to Memory" : "Save Sources to Memory",
                            systemImage: isCurrentSnapshotSaved ? "checkmark.circle.fill" : "archivebox.fill"
                        )
                    }
                    .disabled(
                        !model.hasSources
                        || model.isScanning
                        || isSavingToMemory
                        || isCurrentSnapshotSaved
                    )
                } header: {
                    Text("Source Inspector")
                } footer: {
                    Text("The first pass inventories loaded scripts, styles, module preloads, and runtime resources. A bounded second pass reconciles late runtime entries, explicit source references, and numeric Webpack/Rspack chunk calls against shipped runtime tables. One strict nested pass then inspects only resolved bundler JavaScript and worker chunks for explicit imports, workers, source maps, and runtime `.p + asset` dependencies. The retained index stays in memory until ContextPort closes. Save Sources to Memory packages the complete retained index into one ZIP regardless of the active search filter.")
                }

                Section("Sources") {
                    if model.results.isEmpty && !model.isScanning {
                        Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "No sources indexed."
                             : "No source text matched \"\(searchText)\".")
                            .foregroundColor(.secondary)
                    }

                    ForEach(model.results) { result in
                        NavigationLink {
                            DeveloperSourceDetailView(result: result, query: searchText)
                        } label: {
                            DeveloperSourceRow(result: result)
                        }
                    }
                }
            }
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search source contents")
            .onChange(of: searchText) { query in
                model.scheduleSearch(query)
            }
            .task {
                if isActive {
                    model.scanIfNeeded(sessions: profileSessionPool.developerSourceSessions())
                }
            }
            .onChange(of: isActive) { active in
                if active {
                    model.scanIfNeeded(sessions: profileSessionPool.developerSourceSessions())
                }
            }
        }
    }

    private var isCurrentSnapshotSaved: Bool {
        guard let current = model.snapshotFingerprint,
              let lastSavedSnapshotFingerprint else {
            return false
        }
        return current == lastSavedSnapshotFingerprint
    }

    private func saveSourcesToMemory() {
        guard !isSavingToMemory else { return }
        let snapshot = model.archiveSnapshot()
        guard !snapshot.isEmpty else { return }

        let snapshotFingerprint = model.snapshotFingerprint
            ?? DeveloperSourceMemoryArchiveBuilder.fingerprint(for: snapshot)

        isSavingToMemory = true
        appModel.statusMessage = "Packaging \(snapshot.count) retained sources into one Memory ZIP..."

        Task { @MainActor in
            defer { isSavingToMemory = false }

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try DeveloperSourceMemoryArchiveBuilder().saveToMemory(items: snapshot)
                }.value
                lastSavedSnapshotFingerprint = snapshotFingerprint
                appModel.reloadLocalMemory()
                appModel.statusMessage = result.message
            } catch {
                appModel.reloadLocalMemory()
                appModel.statusMessage = "Developer source ZIP save failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct DeveloperSourceRow: View {
    let result: DeveloperSourceSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(result.source.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                Spacer(minLength: 8)

                if result.matchCount > 0 {
                    Text("\(result.matchCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            Text("\(result.source.sessionTitle) • \(result.source.kind)")
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let snippet = result.snippets.first {
                Text(snippet)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(3)
                    .foregroundColor(.secondary)
            } else if let metadataNote = result.source.metadataNote {
                Text(metadataNote)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if let loadError = result.source.loadError {
                Text(loadError)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else if result.metadataMatched {
                Text("Matched source name, URL, session, or source type.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct DeveloperSourceDetailView: View {
    let result: DeveloperSourceSearchResult
    let query: String

    @State private var isShowingInfo = false

    var body: some View {
        Group {
            if let content = result.source.content {
                VStack(spacing: 0) {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text("\(result.matchCount) match\(result.matchCount == 1 ? "" : "es") for \"\(query)\"")
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text("First match shown")
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(.thinMaterial)
                    }

                    DeveloperSourceCodeTextView(
                        sourceID: result.source.id,
                        content: content,
                        searchQuery: query
                    )
                }
            } else {
                List {
                    Section("Source") {
                        LabeledContent("Name", value: result.source.displayName)
                        LabeledContent("Type", value: result.source.kind)
                        LabeledContent("Session", value: result.source.sessionTitle)
                    }

                    if let metadataNote = result.source.metadataNote {
                        Section("Resource Metadata") {
                            Text(metadataNote)
                                .textSelection(.enabled)
                        }
                    }

                    if let loadError = result.source.loadError {
                        Section("Load Error") {
                            Text(loadError)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle(result.source.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if result.source.content != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isShowingInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Source information")
                }
            }
        }
        .sheet(isPresented: $isShowingInfo) {
            DeveloperSourceInfoView(result: result, query: query)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct DeveloperSourceInfoView: View {
    let result: DeveloperSourceSearchResult
    let query: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Source") {
                    LabeledContent("Name", value: result.source.displayName)
                    LabeledContent("Type", value: result.source.kind)
                    LabeledContent("Session", value: result.source.sessionTitle)

                    if result.source.byteCount > 0 {
                        LabeledContent(
                            result.source.content == nil ? "Resource Size" : "Indexed Text",
                            value: ByteCountFormatter.string(
                                fromByteCount: Int64(result.source.byteCount),
                                countStyle: .file
                            )
                        )
                    }

                    if let urlString = result.source.urlString {
                        Text(urlString)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Search") {
                        LabeledContent("Query", value: query)
                        LabeledContent("Matches", value: "\(result.matchCount)")
                    }

                    if !result.snippets.isEmpty {
                        Section("Match Clues") {
                            ForEach(Array(result.snippets.enumerated()), id: \.offset) { index, snippet in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Match \(index + 1)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text(snippet)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Source Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct DeveloperSourceCodeTextView: UIViewRepresentable {
    let sourceID: String
    let content: String
    let searchQuery: String

    final class Coordinator {
        var sourceID: String?
        var searchQuery = ""
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .systemBackground
        textView.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        textView.keyboardDismissMode = .interactive
        textView.alwaysBounceVertical = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 20, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if context.coordinator.sourceID != sourceID {
            textView.text = content
            textView.setContentOffset(.zero, animated: false)
            context.coordinator.sourceID = sourceID
            context.coordinator.searchQuery = ""
        }

        let normalizedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard context.coordinator.searchQuery != normalizedQuery else { return }

        context.coordinator.searchQuery = normalizedQuery
        guard !normalizedQuery.isEmpty else {
            textView.selectedRange = NSRange(location: 0, length: 0)
            return
        }

        let range = (textView.text as NSString).range(
            of: normalizedQuery,
            options: [.caseInsensitive, .diacriticInsensitive]
        )
        guard range.location != NSNotFound else { return }

        textView.selectedRange = range
        textView.scrollRangeToVisible(range)
    }
}
