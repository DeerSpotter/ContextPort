import Foundation
import Security

final class ChatGPTProfileCookieVault {
    private let service = "com.deerspotter.ChatGPTWebView.profile-cookies"

    func save(_ cookies: [HTTPCookie], profileID: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: cookies, requiringSecureCoding: true) else {
            return
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            attributes.forEach { newItem[$0.key] = $0.value }
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    func load(profileID: String) -> [HTTPCookie] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let cookies = try? NSKeyedUnarchiver.unarchivedObject(
                ofClasses: [NSArray.self, HTTPCookie.self],
                from: data
              ) as? [HTTPCookie] else {
            return []
        }

        return cookies
    }

    func delete(profileID: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID
        ]
        SecItemDelete(query as CFDictionary)
    }
}
