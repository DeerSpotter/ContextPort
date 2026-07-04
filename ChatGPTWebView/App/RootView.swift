import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var updateChecker: AppUpdateChecker
    @EnvironmentObject private var profileManager: ChatGPTProfileManager
    @EnvironmentObject private var profileSessionPool: ChatGPTProfileSessionPool
    @Environment(\.openURL) private var openURL
    @State private var selectedTab: AppTab = .chatgpt
    @State private var isShowingProfiles = false
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

            if isShowingProfiles {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isShowingProfiles = false
                    }
                    .zIndex(2)

                ProfilePickerPopup(
                    profileManager: profileManager,
                    onProfileSelected: { profile in
                        profileManager.selectProfile(profile)
                        selectedTab = .chatgpt
                        isShowingProfiles = false
                    },
                    onRemoveProfile: { profile in
                        removeProfile(profile)
                    },
                    onAddLogin: {
                        _ = profileManager.addLoginProfile()
                        selectedTab = .chatgpt
                        isShowingProfiles = false
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 40)
                .zIndex(3)
            }

            CompactBottomSwitcher(
                selectedTab: $selectedTab,
                onProfiles: {
                    isShowingProfiles.toggle()
                },
                onSettings: {
                    isShowingProfiles = false
                    isShowingSettings = true
                }
            )
            .zIndex(4)
        }
        .onChange(of: appModel.openChatGPTTabRequestID) { _ in
            selectedTab = .chatgpt
            isShowingProfiles = false
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

    private func removeProfile(_ profile: ChatGPTProfile) {
        guard profile.kind == .saved else { return }

        Task { @MainActor in
            await profileSessionPool.removeSavedProfileSession(profileID: profile.id)
            profileManager.removeSavedProfile(profile)
            selectedTab = .chatgpt
            isShowingProfiles = false
        }
    }
}

private enum AppTab: Hashable {
    case chatgpt
    case memory
}

private struct CompactBottomSwitcher: View {
    @Binding var selectedTab: AppTab
    let onProfiles: () -> Void
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

            Button(action: onProfiles) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 32)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
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
}

private struct ProfilePickerPopup: View {
    @ObservedObject var profileManager: ChatGPTProfileManager
    let onProfileSelected: (ChatGPTProfile) -> Void
    let onRemoveProfile: (ChatGPTProfile) -> Void
    let onAddLogin: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            profileRow(profileManager.primaryProfile, title: primaryProfileTitle, removable: false)
            profileRow(profileManager.guestProfile, title: "Guest", removable: false)

            ForEach(profileManager.savedProfiles) { profile in
                profileRow(profile, title: profile.displayName, removable: true)
            }

            Divider()

            Button(action: onAddLogin) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .frame(width: 18)
                    Text("Add Login")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 300)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(radius: 8)
    }

    private var primaryProfileTitle: String {
        profileManager.primaryDisplayName == "Current User"
            ? "Current User"
            : "Current User: \(profileManager.primaryDisplayName)"
    }

    @ViewBuilder
    private func profileRow(_ profile: ChatGPTProfile, title: String, removable: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                onProfileSelected(profile)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: profileManager.activeProfileID == profile.id ? "checkmark" : "")
                        .frame(width: 18)
                    Text(title)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.leading, 12)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if removable {
                Button {
                    onRemoveProfile(profile)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
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
