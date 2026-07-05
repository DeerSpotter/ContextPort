import SwiftUI

enum MemorySharingFormat: String, CaseIterable, Hashable, Identifiable {
    case askEveryTime = "ask_every_time"
    case pdfAndMarkdown = "pdf_and_markdown"
    case pdfOnly = "pdf_only"
    case markdownOnly = "markdown_only"
    case insertMarkdownText = "insert_markdown_text"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .askEveryTime:
            return "Ask Every Time"
        case .pdfAndMarkdown:
            return "PDF + Markdown"
        case .pdfOnly:
            return "PDF Only"
        case .markdownOnly:
            return "Markdown Only"
        case .insertMarkdownText:
            return "Insert Markdown Text"
        }
    }

    var includesPDF: Bool {
        self == .pdfAndMarkdown || self == .pdfOnly
    }

    var includesMarkdownFile: Bool {
        self == .pdfAndMarkdown || self == .markdownOnly
    }

    var injectsMarkdownText: Bool {
        self == .insertMarkdownText
    }

    static var launchFormats: [MemorySharingFormat] {
        allCases.filter { $0 != .askEveryTime }
    }
}

@MainActor
final class MemoryLaunchSettings: ObservableObject {
    @Published var sharingFormat: MemorySharingFormat {
        didSet {
            UserDefaults.standard.set(sharingFormat.rawValue, forKey: Self.sharingFormatKey)
        }
    }

    private static let sharingFormatKey = "MemorySharingFormat"

    init() {
        let storedValue = UserDefaults.standard.string(forKey: Self.sharingFormatKey)
        self.sharingFormat = storedValue.flatMap(MemorySharingFormat.init(rawValue:)) ?? .askEveryTime
    }
}

struct MemoryLaunchRequest: Identifiable {
    let id = UUID()
    let entries: [LocalMemoryEntry]
}

struct MemoryLaunchSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var providerManager: AIProviderManager
    @EnvironmentObject private var launchSettings: MemoryLaunchSettings
    @Environment(\.dismiss) private var dismiss

    let entries: [LocalMemoryEntry]
    var onLaunched: () -> Void = {}

    @State private var pendingProvider: AIProvider?
    @State private var showFormatSelection = false
    @State private var isPreparing = false
    @State private var launchError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Choose AI") {
                    ForEach(providerManager.providers) { provider in
                        Button {
                            chooseProvider(provider)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: provider.systemImage)
                                    .frame(width: 24)
                                Text(provider.displayName)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparing)
                    }
                }

                Section {
                    Text("\(entries.count) \(entries.count == 1 ? "memory" : "memories") selected")
                        .foregroundColor(.secondary)
                }

                if let launchError {
                    Section {
                        Text(launchError)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Start New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(
                "Context Format",
                isPresented: $showFormatSelection,
                titleVisibility: .visible
            ) {
                ForEach(MemorySharingFormat.launchFormats) { format in
                    Button(format.displayName) {
                        guard let provider = pendingProvider else { return }
                        launch(provider: provider, format: format)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose how ContextPort should share the selected Memory with this AI.")
            }
        }
    }

    private func chooseProvider(_ provider: AIProvider) {
        launchError = nil
        if launchSettings.sharingFormat == .askEveryTime {
            pendingProvider = provider
            showFormatSelection = true
        } else {
            launch(provider: provider, format: launchSettings.sharingFormat)
        }
    }

    private func launch(provider: AIProvider, format: MemorySharingFormat) {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        do {
            let bundle = try MemoryContextBundleBuilder().build(entries: entries, format: format)
            PendingLocalMemoryAttachment.mark(
                entries,
                fileURLs: bundle.fileURLs,
                injectMarkdown: format.injectsMarkdownText
            )

            providerManager.selectProvider(provider)
            appModel.statusMessage = bundle.statusMessage(for: provider.displayName)
            appModel.openChatGPTTabRequestID = UUID()
            onLaunched()
            dismiss()
        } catch {
            launchError = "Could not prepare Memory context: \(error.localizedDescription)"
        }
    }
}
