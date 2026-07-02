import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selectedTab: AppTab = .chatgpt

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .chatgpt:
                    ChatGPTTabView()
                case .memory:
                    MemoryTestView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 34)

            CompactBottomSwitcher(selectedTab: $selectedTab)
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

private struct CompactBottomSwitcher: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            CompactTabButton(
                title: "ChatGPT",
                systemImage: "bubble.left.and.bubble.right.fill",
                isSelected: selectedTab == .chatgpt
            ) {
                selectedTab = .chatgpt
            }

            CompactTabButton(
                title: "Memory",
                systemImage: "externaldrive.connected.to.line.below.fill",
                isSelected: selectedTab == .memory
            ) {
                selectedTab = .memory
            }
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.secondary.opacity(0.16)).frame(height: 0.5), alignment: .top)
    }
}

private struct CompactTabButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .foregroundColor(isSelected ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
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
