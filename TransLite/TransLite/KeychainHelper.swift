import Foundation
import Security

/// Handles secure storage of API keys using macOS Keychain Services
final class KeychainHelper {
    static let shared = KeychainHelper()

    private let service = "com.translite.apikey"
    private let openAIAccount = "openai-api-key"
    private let claudeAccount = "claude-api-key"

    private init() {}

    // MARK: - OpenAI API Key

    /// Saves the OpenAI API key to the Keychain
    @discardableResult
    func saveAPIKey(_ apiKey: String) -> Bool {
        saveKey(apiKey, account: openAIAccount)
    }

    /// Retrieves the OpenAI API key from the Keychain
    func getAPIKey() -> String? {
        getKey(account: openAIAccount)
    }

    /// Deletes the OpenAI API key from the Keychain
    @discardableResult
    func deleteAPIKey() -> Bool {
        deleteKey(account: openAIAccount)
    }

    /// Checks if an OpenAI API key exists in the Keychain
    var hasAPIKey: Bool {
        getAPIKey() != nil
    }

    // MARK: - Claude API Key

    /// Saves the Claude API key to the Keychain
    @discardableResult
    func saveClaudeAPIKey(_ apiKey: String) -> Bool {
        saveKey(apiKey, account: claudeAccount)
    }

    /// Retrieves the Claude API key from the Keychain
    func getClaudeAPIKey() -> String? {
        getKey(account: claudeAccount)
    }

    /// Deletes the Claude API key from the Keychain
    @discardableResult
    func deleteClaudeAPIKey() -> Bool {
        deleteKey(account: claudeAccount)
    }

    /// Checks if a Claude API key exists in the Keychain
    var hasClaudeAPIKey: Bool {
        getClaudeAPIKey() != nil
    }

    // MARK: - Private Helpers

    private func saveKey(_ key: String, account: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }

        deleteKey(account: account)

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

    private func getKey(account: String) -> String? {
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

    @discardableResult
    private func deleteKey(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
