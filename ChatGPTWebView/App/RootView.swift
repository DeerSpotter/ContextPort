import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var updateChecker: AppUpdateChecker
    @EnvironmentObject private var providerManager: AIProviderManager
    @EnvironmentObject private var profileManager: ChatGPTProfileManager
    @EnvironmentObject private var profileSessionPool: ChatGPTProfileSessionPool
    @Environment(\.openURL) private var openURL
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @State private var selectedTab: AppTab = .assistant
    @State private var isShowingProfiles = false
    @State private var isShowingSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                AIChatTabView()
                    .opacity(selectedTab == .assistant ? 1 : 0)
                    .allowsHitTesting(selectedTab == .assistant)
                    .accessibilityHidden(selectedTab != .assistant)
                    .zIndex(selectedTab == .assistant ? 1 : 0)

                MemoryTestView()
                    .opacity(selectedTab == .memory ? 1 : 0)
                    .allowsHitTesting(selectedTab == .memory)
                    .accessibilityHidden(selectedTab != .memory)
                    .zIndex(selectedTab == .memory ? 1 : 0)

                DeveloperSourcesView(
                    isActive: developerModeEnabled && selectedTab == .developer
                )
                .opacity(developerModeEnabled && selectedTab == .developer ? 1 : 0)
                .allowsHitTesting(developerModeEnabled && selectedTab == .developer)
                .accessibilityHidden(!developerModeEnabled || selectedTab != .developer)
                .zIndex(developerModeEnabled && selectedTab == .developer ? 2 : 0)
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

                AIProfilePickerPopup(
                    providerManager: providerManager,
                    profileManager: profileManager,
                    onProviderSelected: { provider in
                        providerManager.selectProvider(provider)
                        selectedTab = .assistant
                        isShowingProfiles = false
                    },
                    onProfileSelected: { profile in
                        profileManager.selectProfile(profile, for: providerManager.activeProviderID)
                        selectedTab = .assistant
                        isShowingProfiles = false
                    },
                    onRemoveProfile: { profile in
                        removeProfile(profile, providerID: providerManager.activeProviderID)
                    },
                    onAddLogin: {
                        _ = profileManager.addLoginProfile(for: providerManager.activeProviderID)
                        selectedTab = .assistant
                        isShowingProfiles = false
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 40)
                .zIndex(3)
            }

            CompactBottomSwitcher(
                selectedTab: $selectedTab,
                provider: providerManager.activeProvider,
                developerModeEnabled: developerModeEnabled,
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
            selectedTab = .assistant
            isShowingProfiles = false
        }
        .onChange(of: developerModeEnabled) { isEnabled in
            if !isEnabled && selectedTab == .developer {
                selectedTab = .assistant
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(updateChecker: updateChecker)
                .presentationDetents([.medium, .large])
        }
        .alert(item: $updateChecker.availableUpdate) { update in
            Alert(
                title: Text("Update Available"),
                message: Text("ContextPort \(update.version) is available. This IPA was built as version \(update.currentVersion)."),
                primaryButton: .default(Text("View Release")) {
                    openURL(update.releaseURL)
                },
                secondaryButton: .cancel(Text("Later"))
            )
        }
    }

    private func removeProfile(_ profile: ChatGPTProfile, providerID: AIProviderID) {
        guard profile.kind == .saved else { return }

        Task { @MainActor in
            await profileSessionPool.removeSavedProfileSession(
                providerID: providerID,
                profileID: profile.id
            )
            profileManager.removeSavedProfile(profile, for: providerID)
            selectedTab = .assistant
            isShowingProfiles = false
        }
    }
}

private enum AppTab: Hashable {
    case assistant
    case memory
    case developer
}

private struct CompactBottomSwitcher: View {
    @Binding var selectedTab: AppTab
    let provider: AIProvider
    let developerModeEnabled: Bool
    let onProfiles: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            CompactTabButton(
                title: provider.displayName,
                systemImage: provider.systemImage,
                isSelected: selectedTab == .assistant
            ) {
                selectedTab = .assistant
            }

            CompactTabButton(
                title: "Memory",
                systemImage: "externaldrive.connected.to.line.below.fill",
                isSelected: selectedTab == .memory
            ) {
                selectedTab = .memory
            }

            if developerModeEnabled {
                CompactTabButton(
                    title: "Dev",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    isSelected: selectedTab == .developer
                ) {
                    selectedTab = .developer
                }
            }

            Button(action: onProfiles) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 32)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("AI and profiles")

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

private struct AIProfilePickerPopup: View {
    @ObservedObject var providerManager: AIProviderManager
    @ObservedObject var profileManager: ChatGPTProfileManager
    let onProviderSelected: (AIProvider) -> Void
    let onProfileSelected: (ChatGPTProfile) -> Void
    let onRemoveProfile: (ChatGPTProfile) -> Void
    let onAddLogin: () -> Void

    private var providerID: AIProviderID {
        providerManager.activeProviderID
    }

    var body: some View {
        VStack(spacing: 0) {
            providerStrip

            Divider()

            profileRow(
                profileManager.primaryProfile(for: providerID),
                title: primaryProfileTitle,
                removable: false
            )
            profileRow(
                profileManager.guestProfile(for: providerID),
                title: "Guest",
                removable: false
            )

            ForEach(profileManager.savedProfiles(for: providerID)) { profile in
                profileRow(profile, title: profile.displayName, removable: true)
            }

            Divider()

            Button(action: onAddLogin) {
                HStack(spacing: 9) {
                    Image(systemName: "plus")
                        .frame(width: 18)
                    Text("Add \(providerManager.activeProvider.displayName) Login")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(radius: 8)
    }

    private var providerStrip: some View {
        HStack(spacing: 0) {
            ForEach(providerManager.providers) { provider in
                Button {
                    onProviderSelected(provider)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: provider.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                        Text(provider.displayName)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundColor(
                        providerManager.activeProviderID == provider.id
                            ? .accentColor
                            : .secondary
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(provider.displayName)
            }
        }
    }

    private var primaryProfileTitle: String {
        let displayName = profileManager.primaryDisplayName(for: providerID)
        return displayName == "Current User"
            ? "Current User"
            : "Current User: \(displayName)"
    }

    @ViewBuilder
    private func profileRow(_ profile: ChatGPTProfile, title: String, removable: Bool) -> some View {
        HStack(spacing: 0) {
            Button {
                onProfileSelected(profile)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: profileManager.activeProfileID(for: providerID) == profile.id ? "checkmark" : "")
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
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
    @EnvironmentObject private var providerManager: AIProviderManager
    @EnvironmentObject private var launchSettings: MemoryLaunchSettings
    @EnvironmentObject private var chatPerformanceSettings: ChatPerformanceSettings
    @AppStorage("developerModeEnabled") private var developerModeEnabled = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(providerManager.allProviders) { provider in
                        Toggle(isOn: providerBinding(provider.id)) {
                            Label(provider.displayName, systemImage: provider.systemImage)
                        }
                    }
                } header: {
                    Text("AI Providers")
                } footer: {
                    Text("Choose which AIs are available throughout ContextPort. At least one AI must remain enabled.")
                }

                Section {
                    Toggle("Optimize Long Chats", isOn: $chatPerformanceSettings.isEnabled)
                        .disabled(chatPerformanceSettings.latestExchangeOnly)

                    Toggle(isOn: $chatPerformanceSettings.latestExchangeOnly) {
                        HStack(spacing: 8) {
                            Image(systemName: "bolt.fill")
                                .frame(width: 22)
                            Text("Latest Exchange Only")
                        }
                    }

                    Stepper(
                        value: $chatPerformanceSettings.visibleMessageLimit,
                        in: ChatPerformanceSettings.visibleMessageRange,
                        step: ChatPerformanceSettings.visibleMessageStep
                    ) {
                        HStack {
                            Text("Visible Messages")
                            Spacer()
                            Text("\(chatPerformanceSettings.visibleMessageLimit)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .disabled(!chatPerformanceSettings.isEnabled || chatPerformanceSettings.latestExchangeOnly)

                    Text("Optimize On")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(providerManager.allProviders) { provider in
                        Toggle(isOn: performanceProviderBinding(provider.id)) {
                            HStack(spacing: 8) {
                                Image(systemName: provider.systemImage)
                                    .frame(width: 22)
                                Text(provider.displayName)
                                if provider.id == .grok {
                                    Text("Experimental")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    Toggle(isOn: $chatPerformanceSettings.chatGPTMobileWebFallbackEnabled) {
                        HStack(spacing: 8) {
                            Image(systemName: AIProviderID.chatGPT.provider.systemImage)
                                .frame(width: 22)
                            Text("ChatGPT Mobile Fallback")
                            Text("Experimental")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Chat Performance")
                } footer: {
                    Text("Latest Exchange Only overrides the normal message window and keeps only your newest question plus the current AI response visible. Older loaded messages remain available to Save Context. Long-chat optimization otherwise hides older loaded messages without removing them. ChatGPT Mobile Fallback adds mweb_fallback=1 to ChatGPT conversation URLs only when the parameter is missing.")
                }

                Section("Memory Sharing") {
                    Picker("Context Format", selection: $launchSettings.sharingFormat) {
                        ForEach(MemorySharingFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                }

                Section {
                    Toggle(isOn: $developerModeEnabled) {
                        Label("Developer Mode", systemImage: "hammer.fill")
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Adds a Dev tab with an on-demand Sources inspector. No source indexing runs while Developer Mode is off. Once indexed, loaded source text stays available across tabs and is cleared only when ContextPort closes.")
                }

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

    private func providerBinding(_ providerID: AIProviderID) -> Binding<Bool> {
        Binding(
            get: {
                providerManager.isProviderEnabled(providerID)
            },
            set: { isEnabled in
                providerManager.setProviderEnabled(providerID, enabled: isEnabled)
            }
        )
    }

    private func performanceProviderBinding(_ providerID: AIProviderID) -> Binding<Bool> {
        Binding(
            get: {
                chatPerformanceSettings.isProviderEnabled(providerID)
            },
            set: { isEnabled in
                chatPerformanceSettings.setProviderEnabled(providerID, enabled: isEnabled)
            }
        )
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
