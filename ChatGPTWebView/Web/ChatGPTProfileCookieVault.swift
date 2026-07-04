import Foundation
import Security

final class ChatGPTProfileCookieVault {
    private let service = "com.deerspotter.ChatGPTWebView.profile-cookies"

    func save(_ cookies: [HTTPCookie], profileID: String) {
        let propertyLists: [[String: Any]] = cookies.compactMap { cookie in
            guard let properties = cookie.properties else { return nil }
            var values: [String: Any] = [:]
            for (key, value) in properties {
                values[key.rawValue] = value
            }
            return values
        }

        guard PropertyListSerialization.propertyList(propertyLists, isValidFor: .binary),
              let data = try? PropertyListSerialization.data(
                fromPropertyList: propertyLists,
                format: .binary,
                options: 0
              ) else {
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
              let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ),
              let storedCookies = propertyList as? [[String: Any]] else {
            return []
        }

        return storedCookies.compactMap { stored in
            var properties: [HTTPCookiePropertyKey: Any] = [:]
            for (key, value) in stored {
                properties[HTTPCookiePropertyKey(key)] = value
            }
            return HTTPCookie(properties: properties)
        }
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
