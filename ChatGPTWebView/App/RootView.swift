import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            ChatGPTTabView()
                .tabItem {
                    Label("ChatGPT", systemImage: "bubble.left.and.bubble.right")
                }

            Group {
                if appModel.configStore.config == nil {
                    SupabaseSetupView()
                } else if appModel.isAuthenticated {
                    MemoryTestView()
                } else {
                    AuthView()
                }
            }
            .tabItem {
                Label("Memory", systemImage: "externaldrive.connected.to.line.below")
            }
        }
    }
}
