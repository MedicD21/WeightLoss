import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private let service = Constants.Keychain.serviceName

    private init() {}

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

    func clearAll() {
        deleteToken()
        deleteRefreshToken()
    }

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save error: \(status)")
        }
    }

    private func get(key: String) -> String? {
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

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
