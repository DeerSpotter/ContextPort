import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var updateChecker: AppUpdateChecker
    @EnvironmentObject private var profileManager: ChatGPTProfileManager
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: AppTab = .chatgpt
    @State private var isShowingSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ChatGPTTabView()
                    .opacity(selectedTab == .chatgpt ? 1 : 0)
                    .allowsHitTesting(selectedTab == .chatgpt)
                    .accessibilityHidden(selectedTab != .chatgpt)
                    .zIndex(selectedTab == .chatgpt ? 1 : 0)

                MemoryTestView()
                    .opacity(selectedTab == .memory ? 1 : 0)
                    .allowsHitTesting(selectedTab == .memory)
                    .accessibilityHidden(selectedTab != .memory)
                    .zIndex(selectedTab == .memory ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 34)

            CompactBottomSwitcher(
                selectedTab: $selectedTab,
                profileManager: profileManager,
                onProfileSelected: { profile in
                    profileManager.selectProfile(profile)
                    selectedTab = .chatgpt
                },
                onAddLogin: {
                    _ = profileManager.addLoginProfile()
                    selectedTab = .chatgpt
                },
                onSettings: {
                    isShowingSettings = true
                }
            )
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            selectedTab = .chatgpt
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(updateChecker: updateChecker)
                .presentationDetents([.medium])
        }
        .alert(item: $updateChecker.availableUpdate) { update in
            Alert(
                title: Text("Update Available"),
                message: Text("ChatGPT Memory \(update.version) is available. This IPA was built as version \(update.currentVersion)."),
                primaryButton: .default(Text("View Release")) {
                    openURL(update.releaseURL)
                },
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }
}

private enum AppTab: Hashable {
    case chatgpt
    case memory
}

private struct CompactBottomSwitcher: View {
    @Binding var selectedTab: AppTab
    @ObservedObject var profileManager: ChatGPTProfileManager
    let onProfileSelected: (ChatGPTProfile) -> Void
    let onAddLogin: () -> Void
    let onSettings: () -> Void

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

            Menu {
                profileButton(profileManager.primaryProfile, title: primaryProfileTitle)
                profileButton(profileManager.guestProfile, title: "Guest")

                ForEach(profileManager.savedProfiles) { profile in
                    profileButton(profile, title: profile.displayName)
                }

                Divider()

                Button(action: onAddLogin) {
                    Label("Add Login", systemImage: "plus")
                }
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 32)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Profiles")

            Button(action: onSettings) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 32)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .frame(height: 34)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().fill(Color.secondary.opacity(0.16)).frame(height: 0.5), alignment: .top)
    }

    private var primaryProfileTitle: String {
        profileManager.primaryDisplayName == "Current User"
            ? "Current User"
            : "Current User: \(profileManager.primaryDisplayName)"
    }

    @ViewBuilder
    private func profileButton(_ profile: ChatGPTProfile, title: String) -> some View {
        Button {
            onProfileSelected(profile)
        } label: {
            if profileManager.activeProfileID == profile.id {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
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

private struct SettingsView: View {
    @ObservedObject var updateChecker: AppUpdateChecker
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Updates") {
                    Toggle("Check for updates on start", isOn: $updateChecker.checkForUpdatesOnStart)
                }
            }
            .navigationTitle("Settings")
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
