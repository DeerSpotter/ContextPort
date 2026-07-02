import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: AppTab = .chatgpt

    var body: some View {
        TabView(selection: $selectedTab) {
            ChatGPTTabView()
                .tabItem {
                    Label("ChatGPT", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(AppTab.chatgpt)

            MemoryTestView()
                .tabItem {
                    Label("Memory", systemImage: "externaldrive.connected.to.line.below")
                }
                .tag(AppTab.memory)
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            selectedTab = .chatgpt
        }
    }
}

private enum AppTab: Hashable {
    case chatgpt
    case memory
}

struct SupabaseSetupRequiredView: View {
    var body: some View {
        NavigationView {
            Text("Memory is local and available on this device.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
                .navigationTitle("Memory")
        }
    }
}
