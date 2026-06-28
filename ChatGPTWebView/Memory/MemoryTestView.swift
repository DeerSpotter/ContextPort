import SwiftUI

struct MemoryTestView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var projectName = "ChatGPT-WebView"
    @State private var projectDescription = "Trusted iOS 16 ChatGPT companion app with Supabase memory."
    @State private var memoryTitle = "Trusted IPA source"
    @State private var memoryContent = "The trusted IPA should be built from this repository source through GitHub Actions, not downloaded from the upstream release."
    @State private var memoryTags = "repo, ipa, trust"
    @State private var searchQuery = "trusted ipa"

    var body: some View {
        NavigationView {
            Form {
                Section("Account") {
                    Text(appModel.authEmail ?? "Signed in")
                        .font(.footnote)
                    Button("Sign Out", role: .destructive) {
                        appModel.signOut()
                    }
                }

                Section("Project") {
                    TextField("Project name", text: $projectName)
                    TextField("Description", text: $projectDescription, axis: .vertical)
                        .lineLimit(2...4)

                    Button("Create Project") {
                        Task { await appModel.createProject(name: projectName, description: projectDescription) }
                    }
                    .disabled(appModel.isBusy || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Refresh Projects") {
                        Task { await appModel.refreshProjects() }
                    }
                    .disabled(appModel.isBusy)

                    Picker("Selected", selection: $appModel.selectedProject) {
                        Text("None").tag(Optional<MemoryProject>.none)
                        ForEach(appModel.projects) { project in
                            Text(project.name).tag(Optional(project))
                        }
                    }
                }

                Section("Save Memory") {
                    TextField("Title", text: $memoryTitle)
                    TextField("Content", text: $memoryContent, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Tags, comma separated", text: $memoryTags)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button("Save Memory") {
                        Task {
                            await appModel.saveMemory(
                                title: memoryTitle,
                                content: memoryContent,
                                tags: memoryTags
                            )
                        }
                    }
                    .disabled(appModel.isBusy || appModel.selectedProject == nil || memoryTitle.isEmpty || memoryContent.isEmpty)
                }

                Section("Search Memory") {
                    TextField("Search query", text: $searchQuery)
                    Button("Search") {
                        Task { await appModel.searchMemory(query: searchQuery) }
                    }
                    .disabled(appModel.isBusy || appModel.selectedProject == nil || searchQuery.isEmpty)

                    ForEach(appModel.searchResults) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            Text(item.content)
                                .font(.footnote)
                            if !item.tags.isEmpty {
                                Text(item.tags.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Status") {
                    if appModel.isBusy {
                        ProgressView()
                    }
                    Text(appModel.statusMessage.isEmpty ? "Ready." : appModel.statusMessage)
                        .font(.footnote)
                }
            }
            .navigationTitle("Memory Test")
        }
    }
}
