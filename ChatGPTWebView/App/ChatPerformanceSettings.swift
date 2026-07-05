import Combine
import Foundation

struct ChatPerformanceConfiguration: Equatable {
    let isEnabled: Bool
    let visibleMessageLimit: Int
    let enabledProviderIDs: Set<AIProviderID>

    static let disabled = ChatPerformanceConfiguration(
        isEnabled: false,
        visibleMessageLimit: 20,
        enabledProviderIDs: []
    )

    func isEnabled(for providerID: AIProviderID) -> Bool {
        isEnabled && enabledProviderIDs.contains(providerID)
    }
}

@MainActor
final class ChatPerformanceSettings: ObservableObject {
    static let visibleMessageRange = 5...100
    static let visibleMessageStep = 5

    @Published var isEnabled: Bool {
        didSet {
            userDefaults.set(isEnabled, forKey: Self.enabledKey)
        }
    }

    @Published var visibleMessageLimit: Int {
        didSet {
            let normalized = Self.normalizedVisibleMessageLimit(visibleMessageLimit)
            if visibleMessageLimit != normalized {
                visibleMessageLimit = normalized
                return
            }
            userDefaults.set(visibleMessageLimit, forKey: Self.visibleMessageLimitKey)
        }
    }

    @Published private(set) var enabledProviderIDs: Set<AIProviderID> {
        didSet {
            let values = enabledProviderIDs.map(\.rawValue).sorted()
            userDefaults.set(values, forKey: Self.enabledProviderIDsKey)
        }
    }

    private static let enabledKey = "ChatPerformanceEnabled"
    private static let visibleMessageLimitKey = "ChatPerformanceVisibleMessageLimit"
    private static let enabledProviderIDsKey = "ChatPerformanceEnabledProviderIDs"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if userDefaults.object(forKey: Self.enabledKey) == nil {
            self.isEnabled = false
        } else {
            self.isEnabled = userDefaults.bool(forKey: Self.enabledKey)
        }

        let storedLimit = userDefaults.integer(forKey: Self.visibleMessageLimitKey)
        self.visibleMessageLimit = Self.normalizedVisibleMessageLimit(storedLimit == 0 ? 20 : storedLimit)

        if let storedProviderIDs = userDefaults.stringArray(forKey: Self.enabledProviderIDsKey) {
            self.enabledProviderIDs = Set(storedProviderIDs.compactMap(AIProviderID.init(rawValue:)))
        } else {
            self.enabledProviderIDs = [.chatGPT, .claude]
        }
    }

    var configuration: ChatPerformanceConfiguration {
        ChatPerformanceConfiguration(
            isEnabled: isEnabled,
            visibleMessageLimit: visibleMessageLimit,
            enabledProviderIDs: enabledProviderIDs
        )
    }

    func isProviderEnabled(_ providerID: AIProviderID) -> Bool {
        enabledProviderIDs.contains(providerID)
    }

    func setProviderEnabled(_ providerID: AIProviderID, enabled: Bool) {
        if enabled {
            enabledProviderIDs.insert(providerID)
        } else {
            enabledProviderIDs.remove(providerID)
        }
    }

    private static func normalizedVisibleMessageLimit(_ value: Int) -> Int {
        let clamped = min(max(value, visibleMessageRange.lowerBound), visibleMessageRange.upperBound)
        let step = visibleMessageStep
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }
}
