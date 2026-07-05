import Foundation

@MainActor
final class AIProviderManager: ObservableObject {
    @Published var activeProviderID: AIProviderID {
        didSet {
            UserDefaults.standard.set(activeProviderID.rawValue, forKey: Self.activeProviderKey)
        }
    }

    private static let activeProviderKey = "MultiAIActiveProviderID"

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: Self.activeProviderKey),
           let providerID = AIProviderID(rawValue: rawValue) {
            activeProviderID = providerID
        } else {
            activeProviderID = .chatGPT
        }
    }

    var activeProvider: AIProvider {
        activeProviderID.provider
    }

    var providers: [AIProvider] {
        AIProvider.all
    }

    func selectProvider(_ provider: AIProvider) {
        activeProviderID = provider.id
    }
}
