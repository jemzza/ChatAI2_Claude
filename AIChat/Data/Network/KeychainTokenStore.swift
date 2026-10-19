import Foundation
import Security

/// Токены сессий API в Keychain: только на этом устройстве, доступны после первой разблокировки
/// (фоновое продолжение генерации видео).
struct KeychainTokenStore: TokenStoring {
    private let service: String

    init(service: String = "com.labs.fviu.api-session") {
        self.service = service
    }

    func load(key: String) -> SessionTokens? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return try? JSONDecoder().decode(SessionTokens.self, from: data)
    }

    func save(_ tokens: SessionTokens, key: String) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(baseQuery(key).merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    func remove(key: String) {
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
