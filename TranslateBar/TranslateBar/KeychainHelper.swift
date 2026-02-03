import Foundation
import Security

/// Handles secure storage of the OpenAI API key using macOS Keychain Services
final class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.translatebar.apikey"
    private let account = "openai-api-key"

    private init() {}

    /// Saves the API key to the Keychain
    /// - Parameter apiKey: The OpenAI API key to store
    /// - Returns: True if successful, false otherwise
    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        // First, try to delete any existing key
        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieves the API key from the Keychain
    /// - Returns: The stored API key, or nil if not found
    func getAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            return nil
        }

        return apiKey
    }

    /// Deletes the API key from the Keychain
    /// - Returns: True if successful or key didn't exist, false on error
    @discardableResult
    func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Checks if an API key exists in the Keychain
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }
}
