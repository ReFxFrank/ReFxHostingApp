import Foundation
import Security

/// Token storage keys.
enum TokenKey: String {
    case accessToken = "refx.token.access"
    case refreshToken = "refx.token.refresh"
}

/// Abstraction over the token store so `AuthStore` can be unit-tested with an
/// in-memory fake (the real Keychain needs a host app + entitlements).
protocol TokenStoring {
    func set(_ value: String, for key: TokenKey)
    func get(_ key: TokenKey) -> String?
    func delete(_ key: TokenKey)
    func clear()
}

/// Thin Keychain wrapper for the access/refresh token pair. Items are stored
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable in the
/// background (for BGAppRefresh) but never migrated to a new device or backup.
/// Tokens live ONLY here, never in UserDefaults/plist, and are never logged.
struct KeychainService: TokenStoring {
    typealias Key = TokenKey

    private let service: String

    init(service: String = "com.refx.app.tokens") {
        self.service = service
    }

    func set(_ value: String, for key: Key) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        // Upsert: delete-then-add keeps the accessibility attribute correct.
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attrs as CFDictionary, nil)
    }

    func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    func delete(_ key: Key) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    func clear() {
        delete(.accessToken)
        delete(.refreshToken)
    }
}
