import Foundation

struct ChatGPTProfile: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case primary
        case saved
        case guest
    }

    let id: String
    var displayName: String
    let kind: Kind

    static let primaryID = "primary"
    static let guestID = "guest"
}

private struct StoredChatGPTProfile: Codable {
    let id: String
    var displayName: String
}

@MainActor
final class ChatGPTProfileManager: ObservableObject {
    @Published private(set) var savedProfiles: [ChatGPTProfile] = []
    @Published private(set) var primaryDisplayName: String
    @Published var activeProfileID: String {
        didSet {
            UserDefaults.standard.set(activeProfileID, forKey: Self.activeProfileKey)
        }
    }

    private static let savedProfilesKey = "ChatGPTSavedProfiles"
    private static let activeProfileKey = "ChatGPTActiveProfileID"
    private static let primaryDisplayNameKey = "ChatGPTPrimaryProfileDisplayName"

    init() {
        primaryDisplayName = UserDefaults.standard.string(forKey: Self.primaryDisplayNameKey) ?? "Current User"
        activeProfileID = UserDefaults.standard.string(forKey: Self.activeProfileKey) ?? ChatGPTProfile.primaryID
        loadSavedProfiles()

        if profile(withID: activeProfileID) == nil {
            activeProfileID = ChatGPTProfile.primaryID
        }
    }

    var primaryProfile: ChatGPTProfile {
        ChatGPTProfile(id: ChatGPTProfile.primaryID, displayName: primaryDisplayName, kind: .primary)
    }

    var guestProfile: ChatGPTProfile {
        ChatGPTProfile(id: ChatGPTProfile.guestID, displayName: "Guest", kind: .guest)
    }

    var activeProfile: ChatGPTProfile {
        profile(withID: activeProfileID) ?? primaryProfile
    }

    func profile(withID id: String) -> ChatGPTProfile? {
        if id == ChatGPTProfile.primaryID { return primaryProfile }
        if id == ChatGPTProfile.guestID { return guestProfile }
        return savedProfiles.first { $0.id == id }
    }

    func selectProfile(_ profile: ChatGPTProfile) {
        activeProfileID = profile.id
    }

    @discardableResult
    func addLoginProfile() -> ChatGPTProfile {
        let number = savedProfiles.count + 2
        let profile = ChatGPTProfile(
            id: UUID().uuidString,
            displayName: "Login \(number)",
            kind: .saved
        )
        savedProfiles.append(profile)
        saveSavedProfiles()
        activeProfileID = profile.id
        return profile
    }

    func updateDetectedDisplayName(_ value: String, for profileID: String) {
        let name = cleanedDisplayName(value)
        guard !name.isEmpty else { return }

        if profileID == ChatGPTProfile.primaryID {
            guard primaryDisplayName != name else { return }
            primaryDisplayName = name
            UserDefaults.standard.set(name, forKey: Self.primaryDisplayNameKey)
            return
        }

        guard let index = savedProfiles.firstIndex(where: { $0.id == profileID }),
              savedProfiles[index].displayName != name else {
            return
        }

        savedProfiles[index].displayName = name
        saveSavedProfiles()
    }

    private func loadSavedProfiles() {
        guard let data = UserDefaults.standard.data(forKey: Self.savedProfilesKey),
              let stored = try? JSONDecoder().decode([StoredChatGPTProfile].self, from: data) else {
            savedProfiles = []
            return
        }

        savedProfiles = stored.map {
            ChatGPTProfile(id: $0.id, displayName: $0.displayName, kind: .saved)
        }
    }

    private func saveSavedProfiles() {
        let stored = savedProfiles.map {
            StoredChatGPTProfile(id: $0.id, displayName: $0.displayName)
        }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        UserDefaults.standard.set(data, forKey: Self.savedProfilesKey)
    }

    private func cleanedDisplayName(_ value: String) -> String {
        let trimmed = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty,
              trimmed.count <= 120,
              !["chatgpt", "profile", "account", "menu", "user"].contains(trimmed.lowercased()) else {
            return ""
        }

        return trimmed
    }
}
