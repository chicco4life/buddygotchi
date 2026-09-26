import Foundation
import Security

/// API keys for the brains that need one (HARNESS.md §6), kept in the login
/// Keychain and nowhere else. One entry per service. Both calls can block
/// while macOS asks for access, so they never run on the main thread or on
/// the runtime's `home` queue.
public enum Keychain {
    public enum Account: String, Sendable {
        case jev
    }

    static let service = "com.boopcomputer.boop"

    public static func key(_ account: Account) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue, kSecReturnData as String: true,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func setKey(_ key: String?, for account: Account) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return true }
        var add = query
        add[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}
