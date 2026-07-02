import SwiftUI
import UIKit

struct MemoryTestView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var projectName = "ChatGPT-WebView"
    @State private var projectDescription = "Trusted iOS 16 ChatGPT companion app with Supabase memory."
    @State private var memoryTitle = "Trusted IPA source"
    @State private var memoryContent = "The trusted IPA should be built from this repository source through GitHub Actions, not downloaded from the upstream release."
    @State private var memoryTags = "repo, ipa, trust"
    @State private var searchQuery = "trusted ipa"
    @State private var sessionImportTitle = "Imported ChatGPT session context"
    @State private var sessionImportContent = ""
    @State private var sessionImportSource = "chatgpt_web"
    @State private var sessionImportTags = "session-import, chatgpt-webview"
    @State private var sessionImportImportance = 5
    @State private var virtualMCPTitle = "Virtual MCP memory direction"
    @State private var virtualMCPSummary = "The app should prototype the MCP connector as a virtual tool layer first. The virtual layer lives inside the app, uses the same tool name and JSON-style contract planned for the real MCP server, and saves approved context through the existing Supabase memory backend."
    @State private var virtualMCPDecisions = "Keep the fixed context pack script for repeatable project memory.\nAdd the optional local context pack UI for targeted file selection.\nContinue treating the MCP connector as the real memory system.\nPrototype save_context_after_approval as a virtual tool inside the app before building the real server."
    @State private var virtualMCPOpenTasks = "Add Phase 5 virtual MCP documentation.\nBuild the real HTTP MCP server after the virtual tool contract is proven.\nReuse the same tool names and schema in the real connector."
    @State private var virtualMCPFiles = "ChatGPTWebView/VirtualMCP/VirtualMCPModels.swift\nChatGPTWebView/VirtualMCP/VirtualMCPMemoryFormatter.swift\nChatGPTWebView/App/AppModel.swift"
    @State private var virtualMCPNextSteps = "Test the virtual save flow from the Memory tab.\nSearch memory for the saved virtual MCP result.\nPromote the same contract into mcp/memory-server later."
    @State private var virtualMCPTags = "virtual-mcp, memory, connector, approval"
    @State private var virtualMCPImportance = 5

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MemoryDashboardCard(
                        accountText: accountText,
                        projectText: selectedProjectText,
                        providerText: providerText,
                        memoryCountText: "\(appModel.searchResults.count)",
                        projectCountText: "\(appModel.projects.count)",
                        localCountText: "\(appModel.localMemoryEntries.count)",
                        isBusy: appModel.isBusy,
                        statusText: appModel.statusMessage.isEmpty ? "Ready." : appModel.statusMessage,
                        canCopyContext: !appModel.searchResults.isEmpty,
                        onRefresh: {
                            appModel.reloadLocalMemory()
                            Task { await appModel.refreshProjects() }
                        },
                        onCopyContext: {
                            UIPasteboard.general.string = appModel.formattedContextForChatGPT(searchQuery: searchQuery)
                            appModel.statusMessage = "Copied formatted Supabase memory context for ChatGPT."
                        }
                    )

                    LocalMemoryVaultCard()

                    MemoryCard(title: "Search Supabase Memory", systemImage: "magnifyingglass") {
                        Text("Find saved Supabase project memory, then copy a compact context block into the ChatGPT tab.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        TextField("Search query", text: $searchQuery)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        HStack(spacing: 10) {
                            Button {
                                Task { await appModel.searchMemory(query: searchQuery) }
                            } label: {
                                Label("Search", systemImage: "magnifyingglass")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appModel.isBusy || appModel.selectedProject == nil || searchQuery.isEmpty)

                            Button {
                                UIPasteboard.general.string = appModel.formattedContextForChatGPT(searchQuery: searchQuery)
                                appModel.statusMessage = "Copied formatted Supabase memory context for ChatGPT."
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.searchResults.isEmpty)
                        }

                        if !appModel.searchResults.isEmpty {
                            VStack(spacing: 10) {
                                ForEach(appModel.searchResults) { item in
                                    MemoryResultRow(item: item)
                                }
                            }
                        }
                    }

                    MemoryCard(title: "Import Session Context to Supabase", systemImage: "square.and.arrow.down.on.square") {
                        Text("Paste important context from this ChatGPT session and push it directly from the app into Supabase. Local Vault above works even when Supabase import is not deployed yet.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        TextField("Title", text: $sessionImportTitle)
                            .textFieldStyle(.roundedBorder)

                        TextField("Source", text: $sessionImportSource)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Tags, comma separated", text: $sessionImportTags)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Stepper("Importance: \(sessionImportImportance)/5", value: $sessionImportImportance, in: 1...5)

                        TextEditor(text: $sessionImportContent)
                            .frame(minHeight: 140)
                            .padding(8)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                            )

                        HStack(spacing: 10) {
                            Button {
                                if let pasted = UIPasteboard.general.string, !pasted.isEmpty {
                                    sessionImportContent = pasted
                                    appModel.statusMessage = "Pasted clipboard into Supabase import."
                                } else {
                                    appModel.statusMessage = "Clipboard does not contain text."
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button {
                                Task {
                                    await appModel.importSessionAfterApproval(
                                        title: sessionImportTitle,
                                        content: sessionImportContent,
                                        source: sessionImportSource,
                                        tagsText: sessionImportTags,
                                        importance: sessionImportImportance
                                    )
                                }
                            } label: {
                                Label("Approve Import", systemImage: "checkmark.seal")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(
                                appModel.isBusy
                                || appModel.selectedProject == nil
                                || sessionImportTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || sessionImportContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            )
                        }

                        if let result = appModel.lastSessionImportResult {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.message)
                                    .font(.caption.weight(.semibold))
                                MemoryInfoRow(label: "Tool", value: result.toolName)
                                MemoryInfoRow(label: "Memory item", value: result.memoryItemID.uuidString)
                                MemoryInfoRow(label: "Summary", value: result.sessionSummaryID.uuidString)
                                if let toolEventID = result.toolEventID {
                                    MemoryInfoRow(label: "Tool event", value: toolEventID.uuidString)
                                }
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    MemoryCard(title: "Virtual MCP Save", systemImage: "point.3.connected.trianglepath.dotted") {
                        Text("Review this structured memory, then approve the real backend `save_context_after_approval` tool call.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        ForEach(appModel.virtualMCPRegistry.tools) { tool in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(tool.name)
                                        .font(.caption.monospaced().weight(.semibold))
                                    Spacer()
                                    if tool.requiresApproval {
                                        Text("approval required")
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.15), in: Capsule())
                                    }
                                }
                                Text(tool.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                        }

                        TextField("Title", text: $virtualMCPTitle)
                            .textFieldStyle(.roundedBorder)

                        TextField("Summary", text: $virtualMCPSummary, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...8)

                        TextField("Decisions, one per line", text: $virtualMCPDecisions, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...8)

                        TextField("Open tasks, one per line", text: $virtualMCPOpenTasks, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)

                        TextField("Files discussed, one per line", text: $virtualMCPFiles, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        TextField("Next steps, one per line", text: $virtualMCPNextSteps, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...6)

                        TextField("Tags, comma separated", text: $virtualMCPTags)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Stepper("Importance: \(virtualMCPImportance)/5", value: $virtualMCPImportance, in: 1...5)

                        Button {
                            Task {
                                await appModel.runVirtualSaveContextAfterApproval(
                                    title: virtualMCPTitle,
                                    summary: virtualMCPSummary,
                                    decisionsText: virtualMCPDecisions,
                                    openTasksText: virtualMCPOpenTasks,
                                    filesDiscussedText: virtualMCPFiles,
                                    nextStepsText: virtualMCPNextSteps,
                                    tagsText: virtualMCPTags,
                                    importance: virtualMCPImportance
                                )
                            }
                        } label: {
                            Label("Approve Virtual Save", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.isBusy || appModel.selectedProject == nil || virtualMCPTitle.isEmpty || virtualMCPSummary.isEmpty)

                        if let result = appModel.lastVirtualMCPResult {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.message)
                                    .font(.caption.weight(.semibold))
                                MemoryInfoRow(label: "Tool", value: result.toolName)
                                MemoryInfoRow(label: "Memory item", value: result.memoryItemID.uuidString)
                                MemoryInfoRow(label: "Summary", value: result.sessionSummaryID.uuidString)
                                if let toolEventID = result.toolEventID {
                                    MemoryInfoRow(label: "Tool event", value: toolEventID.uuidString)
                                }
                            }
                            .padding(10)
                            .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    MemoryCard(title: "Save Supabase Memory", systemImage: "square.and.pencil") {
                        Text("Save compact facts, decisions, links, file notes, or next steps into Supabase.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        TextField("Title", text: $memoryTitle)
                            .textFieldStyle(.roundedBorder)

                        TextField("Content", text: $memoryContent, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(3...8)

                        TextField("Tags, comma separated", text: $memoryTags)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button {
                            Task {
                                await appModel.saveMemory(
                                    title: memoryTitle,
                                    content: memoryContent,
                                    tags: memoryTags
                                )
                            }
                        } label: {
                            Label("Save Supabase", systemImage: "tray.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.isBusy || appModel.selectedProject == nil || memoryTitle.isEmpty || memoryContent.isEmpty)
                    }

                    MemoryCard(title: "Project", systemImage: "folder") {
                        Text("The selected project controls where Supabase memory is saved. Local Vault uses this name when available, but can work without Supabase.")
                            .font(.footnote)
                            .foregroundColor(.secondary)

                        Picker("Selected", selection: $appModel.selectedProject) {
                            Text("None").tag(Optional<MemoryProject>.none)
                            ForEach(appModel.projects) { project in
                                Text(project.name).tag(Optional(project))
                            }
                        }

                        TextField("Project name", text: $projectName)
                            .textFieldStyle(.roundedBorder)

                        TextField("Description", text: $projectDescription, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...4)

                        HStack(spacing: 10) {
                            Button {
                                Task { await appModel.createProject(name: projectName, description: projectDescription) }
                            } label: {
                                Label("Create", systemImage: "plus.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.isBusy || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button {
                                Task { await appModel.refreshProjects() }
                            } label: {
                                Label("Refresh", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.isBusy)
                        }
                    }

                    MemoryCard(title: "Account and Setup", systemImage: "person.crop.circle") {
                        MemoryInfoRow(label: "Account", value: appModel.authEmail ?? "Not signed in")

                        if let config = appModel.configStore.config {
                            MemoryInfoRow(label: "Supabase project", value: config.projectRef)
                        }

                        Text("Setup stays available in its own tab. Local Vault stays on device when you log out or change Supabase config.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Button("Log Out", role: .destructive) {
                            appModel.signOut()
                        }

                        Button("Change Supabase Project", role: .destructive) {
                            appModel.clearConfig()
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Memory")
        }
    }

    private var accountText: String {
        appModel.authEmail ?? "Not signed in"
    }

    private var selectedProjectText: String {
        appModel.selectedProject?.name ?? "Local Vault only"
    }

    private var providerText: String {
        appModel.configStore.config?.projectRef ?? "Local device only"
    }
}

private struct MemoryDashboardCard: View {
    let accountText: String
    let projectText: String
    let providerText: String
    let memoryCountText: String
    let projectCountText: String
    let localCountText: String
    let isBusy: Bool
    let statusText: String
    let canCopyContext: Bool
    let onRefresh: () -> Void
    let onCopyContext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Memory Dashboard")
                        .font(.title2.weight(.bold))
                    Text("Local first memory, optional Supabase sync, and copy-ready context blocks.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 10) {
                MemoryInfoRow(label: "Account", value: accountText)
                MemoryInfoRow(label: "Selected project", value: projectText)
                MemoryInfoRow(label: "Backend", value: providerText)
            }

            HStack(spacing: 10) {
                MemoryMetricPill(title: "Local", value: localCountText, systemImage: "externaldrive")
                MemoryMetricPill(title: "Supabase", value: memoryCountText, systemImage: "doc.text.magnifyingglass")
                MemoryMetricPill(title: "Projects", value: projectCountText, systemImage: "folder")
            }

            HStack(spacing: 10) {
                Button {
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button {
                    onCopyContext()
                } label: {
                    Label("Copy Supabase", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canCopyContext)
            }

            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct MemoryCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: () -> Content

    init(title: String, systemImage: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MemoryMetricPill: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.caption)
            .foregroundColor(.secondary)

            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct MemoryInfoRow: View {
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

private struct MemoryResultRow: View {
    let item: MemoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)
            Text(item.content)
                .font(.footnote)
                .foregroundColor(.primary)
            if !item.tags.isEmpty {
                Text(item.tags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
