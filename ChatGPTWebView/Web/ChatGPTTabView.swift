import SwiftUI
import UIKit

struct AIChatTabView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var providerManager: AIProviderManager
    @EnvironmentObject private var profileManager: ChatGPTProfileManager
    @EnvironmentObject private var sessionPool: ChatGPTProfileSessionPool
    @Environment(\.scenePhase) private var scenePhase
    @State private var isSavingContext = false
    @State private var isPastingContext = false
    @State private var isAttachingFiles = false
    @State private var isHardRefreshing = false
    @State private var isKeyboardVisible = false
    @State private var isShowingSaveContextOptions = false
    @State private var isShowingMemoryRevisionPicker = false
    @State private var pendingPasteContextText: String?
    @State private var pendingAttachFileURLs: [URL] = []
    @State private var pendingPasteContextID = UUID()
    @State private var sourceMemoryIDs: [UUID] = []
    @State private var sourceMemorySessionID: String?
    @State private var lastProviderID = AIProviderID.chatGPT
    @State private var lastProfileID = ChatGPTProfile.primaryID

    var body: some View {
        ZStack(alignment: .top) {
            SecureChatGPTWebView(store: webViewStore)
                .id(activeSessionID)
                .ignoresSafeArea(.container, edges: .bottom)
                .ignoresSafeArea(.keyboard, edges: .bottom)

            if !isKeyboardVisible {
                HStack(spacing: 10) {
                    Button(contextButtonTitle) {
                        if let pendingPasteContextText {
                            pastePendingContext(pendingPasteContextText)
                        } else if !pendingAttachFileURLs.isEmpty {
                            attachPendingFiles(pendingAttachFileURLs)
                        } else {
                            presentSaveContextChoices()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingContext || isPastingContext || isAttachingFiles)

                    CircleIconButton(
                        systemImage: "stop.circle",
                        accessibilityLabel: "Stop \(provider.displayName) activity",
                        accessibilityHint: "Stops current WebView activity",
                        foregroundColor: .primary
                    ) {
                        webViewStore.stopCurrentActivity()
                    }

                    CircleIconButton(
                        systemImage: "arrow.clockwise",
                        accessibilityLabel: "Hard refresh \(provider.displayName) session",
                        accessibilityHint: "Leaves and reloads the current AI page while preserving the active session",
                        foregroundColor: isHardRefreshing ? .red : .primary
                    ) {
                        hardRefreshCurrentSession()
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
            }
        }
        .onAppear {
            lastProviderID = provider.id
            lastProfileID = activeProfile.id
            handleActiveSessionAppearance()
            handlePendingMemoryStart()
        }
        .onChange(of: activeSessionID) { _ in
            let previousProviderID = lastProviderID
            let previousProfileID = lastProfileID
            lastProviderID = provider.id
            lastProfileID = activeProfile.id
            handleSessionChange(
                fromProviderID: previousProviderID,
                previousProfileID: previousProfileID
            )
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            handlePendingMemoryStart()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .inactive || newPhase == .background else { return }
            persistAllLiveProfileSessions()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            setTypingPriority(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            setTypingPriority(false)
        }
        .confirmationDialog(
            "Save Context",
            isPresented: $isShowingSaveContextOptions,
            titleVisibility: .visible
        ) {
            ForEach(sourceMemoryEntries) { entry in
                Button("Add Revision to \"\(entry.title)\"") {
                    saveCurrentChatToMemory(destination: .revision(entry))
                }
            }

            if !appModel.localMemoryEntries.isEmpty {
                Button("Choose Existing Memory") {
                    isShowingMemoryRevisionPicker = true
                }
            }

            Button("Save as New Memory") {
                saveCurrentChatToMemory(destination: .newMemory)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Add this full chat as a new revision of an existing Memory, or create a new Memory.")
        }
        .sheet(isPresented: $isShowingMemoryRevisionPicker) {
            MemoryRevisionDestinationPicker(entries: appModel.localMemoryEntries) { entry in
                isShowingMemoryRevisionPicker = false
                saveCurrentChatToMemory(destination: .revision(entry))
            }
        }
    }

    private var provider: AIProvider {
        providerManager.activeProvider
    }

    private var activeProfile: ChatGPTProfile {
        profileManager.activeProfile(for: provider.id)
    }

    private var activeSessionID: String {
        "\(provider.id.rawValue)::\(activeProfile.id)"
    }

    private var webViewStore: ChatGPTWebViewStore {
        let providerID = provider.id
        return sessionPool.store(
            for: provider,
            profile: activeProfile,
            onDetectedDisplayName: { profileID, displayName in
                profileManager.updateDetectedDisplayName(
                    displayName,
                    for: profileID,
                    providerID: providerID
                )
            }
        )
    }

    private var sourceMemoryEntries: [LocalMemoryEntry] {
        guard sourceMemorySessionID == activeSessionID else { return [] }
        return sourceMemoryIDs.compactMap { id in
            appModel.localMemoryEntries.first(where: { $0.id == id })
        }
    }

    private var contextButtonTitle: String {
        if isPastingContext { return "Pasting" }
        if isAttachingFiles { return "Attaching" }
        if pendingPasteContextText != nil { return "Paste Context" }
        if !pendingAttachFileURLs.isEmpty { return "Attach Files" }
        return isSavingContext ? "Saving" : "Save Context"
    }

    private func setTypingPriority(_ isTyping: Bool) {
        isKeyboardVisible = isTyping
        sessionPool.setTypingPriority(
            isTyping,
            providerID: provider.id,
            profileID: activeProfile.id
        )
    }

    private func handleActiveSessionAppearance() {
        guard activeProfile.kind == .guest else { return }
        Task { @MainActor in
            await sessionPool.resetGuest(
                provider: provider,
                profile: activeProfile,
                onDetectedDisplayName: { _, _ in }
            )
        }
    }

    private func handleSessionChange(
        fromProviderID previousProviderID: AIProviderID,
        previousProfileID: String
    ) {
        let activeProvider = provider
        let newActiveProfile = activeProfile
        isKeyboardVisible = false
        isHardRefreshing = false

        sessionPool.setTypingPriority(
            false,
            providerID: previousProviderID,
            profileID: previousProfileID
        )
        sessionPool.setTypingPriority(
            false,
            providerID: activeProvider.id,
            profileID: newActiveProfile.id
        )

        Task { @MainActor in
            await sessionPool.persistSession(
                providerID: previousProviderID,
                profileID: previousProfileID
            )

            if newActiveProfile.kind == .guest {
                await sessionPool.resetGuest(
                    provider: activeProvider,
                    profile: newActiveProfile,
                    onDetectedDisplayName: { _, _ in }
                )
            }
        }
    }

    private func persistAllLiveProfileSessions() {
        Task { @MainActor in
            await sessionPool.persistAllSessions()
        }
    }

    private func handlePendingMemoryStart() {
        guard let payload = PendingLocalMemoryAttachment.consumePayload() else {
            return
        }

        sourceMemoryIDs = payload.sourceMemoryIDs
        sourceMemorySessionID = activeSessionID

        switch payload.handoffMode {
        case .newConversation:
            webViewStore.startNewChatWithPendingUploadURLs(payload.fileURLs)
        case .currentConversation:
            webViewStore.preparePendingUploadURLs(payload.fileURLs)
        }

        let destination = payload.handoffMode == .currentConversation
            ? "the current \(provider.displayName) conversation"
            : provider.displayName

        if let composerText = payload.composerText, !composerText.isEmpty {
            pendingPasteContextText = composerText
            pendingAttachFileURLs = payload.fileURLs
            pendingPasteContextID = UUID()
            if payload.fileURLs.isEmpty {
                appModel.statusMessage = "Saved Markdown is ready for \(destination). Tap Paste Context to insert it, or continue without it."
            } else {
                appModel.statusMessage = "Saved Markdown and \(payload.fileURLs.count) Memory attachment\(payload.fileURLs.count == 1 ? "" : "s") are ready for \(destination). Tap Paste Context first, then Attach Files."
            }
            watchForConversationStartWithoutPaste(pendingPasteContextID)
        } else if !payload.fileURLs.isEmpty {
            pendingAttachFileURLs = payload.fileURLs
            pendingPasteContextText = nil
            appModel.statusMessage = "Files are ready. Tap Attach Files to attach from app Memory to \(destination)."
        }
    }

    private func pastePendingContext(_ text: String) {
        guard !isPastingContext else { return }
        isPastingContext = true

        Task { @MainActor in
            defer { isPastingContext = false }
            let inserted = await webViewStore.injectComposerText(text)
            if inserted {
                pendingPasteContextText = nil
                pendingPasteContextID = UUID()
                if pendingAttachFileURLs.isEmpty {
                    appModel.statusMessage = "Pasted saved context into \(provider.displayName). Review and send."
                } else {
                    appModel.statusMessage = "Pasted saved context into \(provider.displayName). Tap Attach Files to add the remaining Memory attachment\(pendingAttachFileURLs.count == 1 ? "" : "s")."
                }
            } else {
                appModel.statusMessage = "Could not paste yet. Wait for \(provider.displayName) to finish loading, then tap Paste Context again."
            }
        }
    }

    private func attachPendingFiles(_ urls: [URL]) {
        guard !isAttachingFiles else { return }
        isAttachingFiles = true
        webViewStore.preparePendingUploadURLs(urls)

        Task { @MainActor in
            defer { isAttachingFiles = false }
            let memoryAttachWorked = await webViewStore.injectFilesIntoChatGPTUpload(urls)

            pendingAttachFileURLs = []
            webViewStore.preparePendingUploadURLs([])

            if memoryAttachWorked {
                appModel.statusMessage = "Context bundle handoff completed for \(provider.displayName). Review the attached context before sending."
            } else {
                appModel.statusMessage = "Context bundle attach was attempted in \(provider.displayName). Save Context is available again. Return to Memory to retry the bundle if needed."
            }
        }
    }

    private func hardRefreshCurrentSession() {
        guard !isHardRefreshing else { return }
        isHardRefreshing = true
        appModel.statusMessage = "Hard refreshing \(provider.displayName)..."

        Task { @MainActor in
            await webViewStore.hardRefreshCurrentSession()
            isHardRefreshing = false
            appModel.statusMessage = "Hard refresh completed for \(provider.displayName)."
        }
    }

    private func watchForConversationStartWithoutPaste(_ id: UUID) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            let baselineUserMessages = await webViewStore.userMessageCount()

            for _ in 0..<120 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard pendingPasteContextID == id, pendingPasteContextText != nil else { return }
                guard !isKeyboardVisible else { continue }

                let currentUserMessages = await webViewStore.userMessageCount()
                if currentUserMessages > baselineUserMessages {
                    pendingPasteContextText = nil
                    pendingPasteContextID = UUID()
                    if pendingAttachFileURLs.isEmpty {
                        appModel.statusMessage = "Continuing without pasted Memory context. Save Context is available again."
                    } else {
                        appModel.statusMessage = "Continuing without pasted Memory text. Tap Attach Files to add the remaining Memory attachment\(pendingAttachFileURLs.count == 1 ? "" : "s")."
                    }
                    return
                }
            }
        }
    }

    private func presentSaveContextChoices() {
        guard !isSavingContext else { return }
        appModel.reloadLocalMemory()
        isShowingSaveContextOptions = true
    }

    private func saveCurrentChatToMemory(destination: MemorySaveDestination) {
        guard !isSavingContext else { return }
        isSavingContext = true

        switch destination {
        case .newMemory:
            appModel.statusMessage = "Saving \(provider.displayName) chat as a new Memory..."
        case .revision(let memory):
            appModel.statusMessage = "Adding a new revision to \"\(memory.title)\"..."
        }

        Task { @MainActor in
            defer { isSavingContext = false }
            do {
                let export = try await webViewStore.exportCurrentConversation()
                let store = LocalMemoryStore()
                let result: LocalMemorySaveResult

                switch destination {
                case .newMemory:
                    result = try store.saveExportedConversation(
                        projectName: appModel.selectedProject?.name ?? "ContextPort",
                        title: export.title,
                        markdownText: export.markdown,
                        pdfData: export.pdfData,
                        sourceURL: export.sourceURL,
                        messageCount: export.messageCount,
                        exportedAt: export.exportedAt
                    )
                case .revision(let memory):
                    result = try store.addRevision(
                        to: memory,
                        markdownText: export.markdown,
                        pdfData: export.pdfData,
                        sourceURL: export.sourceURL,
                        messageCount: export.messageCount,
                        exportedAt: export.exportedAt
                    )
                }

                sourceMemoryIDs = [result.entry.id]
                sourceMemorySessionID = activeSessionID
                appModel.reloadLocalMemory()
                appModel.statusMessage = result.message
            } catch {
                appModel.statusMessage = "Save Context failed: \(error.localizedDescription)"
            }
        }
    }
}

typealias ChatGPTTabView = AIChatTabView

private enum MemorySaveDestination {
    case newMemory
    case revision(LocalMemoryEntry)
}

private struct MemoryRevisionDestinationPicker: View {
    @Environment(\.dismiss) private var dismiss

    let entries: [LocalMemoryEntry]
    let onSelect: (LocalMemoryEntry) -> Void

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: entry.isFavorite ? "star.fill" : "externaldrive.connected.to.line.below")
                            .foregroundColor(entry.isFavorite ? .yellow : .secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.title)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                            Text(revisionLabel(for: entry))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Choose Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func revisionLabel(for entry: LocalMemoryEntry) -> String {
        let noun = entry.revisionCount == 1 ? "revision" : "revisions"
        return "\(entry.revisionCount) \(noun)"
    }
}

private struct CircleIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let accessibilityHint: String
    let foregroundColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.plain)
        .foregroundColor(foregroundColor)
        .background(.ultraThinMaterial, in: Circle())
        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
        .shadow(radius: 2)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
