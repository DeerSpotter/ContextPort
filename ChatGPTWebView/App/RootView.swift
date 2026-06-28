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
                    SupabaseSetupRequiredView()
                } else if appModel.isAuthenticated {
                    MemoryTestView()
                } else {
                    AuthView()
                }
            }
            .tabItem {
                Label("Memory", systemImage: "externaldrive.connected.to.line.below")
            }

            SupabaseSetupView()
                .tabItem {
                    Label("Setup", systemImage: "gearshape")
                }
        }
    }
}

struct SupabaseSetupRequiredView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)

                Text("Supabase setup required")
                    .font(.headline)

                Text("Open the Setup tab to run assisted setup, diagnostics, and copy callback URLs before logging in.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Memory")
        }
    }
}
