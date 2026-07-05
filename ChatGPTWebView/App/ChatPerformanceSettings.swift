import Combine
import Foundation

struct ChatPerformanceConfiguration: Equatable {
    let isEnabled: Bool
    let visibleMessageLimit: Int
    let latestExchangeOnly: Bool
    let enabledProviderIDs: Set<AIProviderID>
    let chatGPTMobileWebFallbackEnabled: Bool

    static let disabled = ChatPerformanceConfiguration(
        isEnabled: false,
        visibleMessageLimit: 5,
        latestExchangeOnly: false,
        enabledProviderIDs: [],
        chatGPTMobileWebFallbackEnabled: false
    )

    func isEnabled(for providerID: AIProviderID) -> Bool {
        (isEnabled || latestExchangeOnly) && enabledProviderIDs.contains(providerID)
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

    @Published var latestExchangeOnly: Bool {
        didSet {
            userDefaults.set(latestExchangeOnly, forKey: Self.latestExchangeOnlyKey)
        }
    }

    @Published private(set) var enabledProviderIDs: Set<AIProviderID> {
        didSet {
            let values = enabledProviderIDs.map(\.rawValue).sorted()
            userDefaults.set(values, forKey: Self.enabledProviderIDsKey)
        }
    }

    @Published var chatGPTMobileWebFallbackEnabled: Bool {
        didSet {
            userDefaults.set(
                chatGPTMobileWebFallbackEnabled,
                forKey: Self.chatGPTMobileWebFallbackEnabledKey
            )
        }
    }

    private static let enabledKey = "ChatPerformanceEnabled"
    private static let visibleMessageLimitKey = "ChatPerformanceVisibleMessageLimit"
    private static let latestExchangeOnlyKey = "ChatPerformanceLatestExchangeOnly"
    private static let enabledProviderIDsKey = "ChatPerformanceEnabledProviderIDs"
    private static let chatGPTMobileWebFallbackEnabledKey = "ChatGPTMobileWebFallbackEnabled"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults

        if userDefaults.object(forKey: Self.enabledKey) == nil {
            self.isEnabled = false
        } else {
            self.isEnabled = userDefaults.bool(forKey: Self.enabledKey)
        }

        let storedLimit = userDefaults.integer(forKey: Self.visibleMessageLimitKey)
        self.visibleMessageLimit = Self.normalizedVisibleMessageLimit(storedLimit == 0 ? 5 : storedLimit)
        self.latestExchangeOnly = userDefaults.bool(forKey: Self.latestExchangeOnlyKey)

        if let storedProviderIDs = userDefaults.stringArray(forKey: Self.enabledProviderIDsKey) {
            self.enabledProviderIDs = Set(storedProviderIDs.compactMap(AIProviderID.init(rawValue:)))
        } else {
            self.enabledProviderIDs = [.chatGPT, .claude]
        }

        self.chatGPTMobileWebFallbackEnabled = userDefaults.bool(
            forKey: Self.chatGPTMobileWebFallbackEnabledKey
        )
    }

    var configuration: ChatPerformanceConfiguration {
        ChatPerformanceConfiguration(
            isEnabled: isEnabled,
            visibleMessageLimit: visibleMessageLimit,
            latestExchangeOnly: latestExchangeOnly,
            enabledProviderIDs: enabledProviderIDs,
            chatGPTMobileWebFallbackEnabled: chatGPTMobileWebFallbackEnabled
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
