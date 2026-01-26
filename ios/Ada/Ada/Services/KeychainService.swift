import Foundation
import Security

/// Service for secure storage of sensitive data in Keychain
final class KeychainService {
    static let shared = KeychainService()

    private let service = Constants.Keychain.serviceName

    private init() {}

    // MARK: - Token Management

    func saveToken(_ token: String) {
        save(key: Constants.Keychain.accessTokenKey, value: token)
    }

    func getToken() -> String? {
        get(key: Constants.Keychain.accessTokenKey)
    }

    func deleteToken() {
        delete(key: Constants.Keychain.accessTokenKey)
    }

    func saveRefreshToken(_ token: String) {
        save(key: Constants.Keychain.refreshTokenKey, value: token)
    }

    func getRefreshToken() -> String? {
        get(key: Constants.Keychain.refreshTokenKey)
    }

    func deleteRefreshToken() {
        delete(key: Constants.Keychain.refreshTokenKey)
    }

    // MARK: - Generic Operations

    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete any existing item
        delete(key: key)

        // Create query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        // Add item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }

    func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }

    func clearAll() {
        deleteToken()
        deleteRefreshToken()
    }
}
