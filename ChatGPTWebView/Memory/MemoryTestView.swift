import SwiftUI

struct MemoryTestView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            List {
                if appModel.localMemoryEntries.isEmpty {
                    Text("No saved chats yet. Open the ChatGPT tab and tap Save Context.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(appModel.localMemoryEntries) { entry in
                        NavigationLink {
                            LocalMemoryDetailView(entry: entry)
                                .environmentObject(appModel)
                        } label: {
                            Text(entry.title)
                                .lineLimit(2)
                        }
                    }
                    .onDelete(perform: deleteSavedChats)
                }
            }
            .navigationTitle("Memory")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        appModel.reloadLocalMemory()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh saved chats")
                }
            }
        }
        .onAppear {
            appModel.reloadLocalMemory()
        }
    }

    private func deleteSavedChats(at offsets: IndexSet) {
        let entries = appModel.localMemoryEntries
        let store = LocalMemoryStore()
        for offset in offsets {
            guard entries.indices.contains(offset) else { continue }
            try? store.deleteEntry(entries[offset])
        }
        appModel.reloadLocalMemory()
        appModel.statusMessage = "Deleted saved chat."
    }
}
