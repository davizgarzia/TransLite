import Foundation
import Security
import IOKit

/// Manages license validation and the per-device identifier, both persisted
/// in the Keychain. The app has two states: free tier (default) or licensed
/// (unlocks BYOK).
final class LicenseManager {
    static let shared = LicenseManager()

    // Keep the historical service name: existing licenses and instance ids
    // were stored under it before the trial was removed.
    private let service = "com.translite.trial"
    private let licenseKey = "license-key"

    private init() {}

    // MARK: - License Management

    var isLicensed: Bool {
        getLicenseKey() != nil
    }

    /// Validates and saves a license key using LemonSqueezy API
    /// - Parameter key: The license key to validate
    /// - Returns: True if the license is valid and was saved
    func activateLicense(_ key: String) async -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }

        // Validate against LemonSqueezy API
        let isValid = await validateWithLemonSqueezy(trimmedKey)

        if isValid {
            saveLicenseKey(trimmedKey)
        }

        return isValid
    }

    /// Validates a license key with LemonSqueezy's API
    private func validateWithLemonSqueezy(_ licenseKey: String) async -> Bool {
        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/activate")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Get a unique instance identifier for this Mac
        let instanceId = getOrCreateInstanceId()

        let body: [String: Any] = [
            "license_key": licenseKey,
            "instance_name": instanceId
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }

            // 200 = activated, 400 = already activated (which is fine)
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 400 {
                // Parse response to check if valid
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check if license is valid (activated or already activated)
                    if let activated = json["activated"] as? Bool, activated {
                        return true
                    }
                    // Check for "already activated" error (still valid)
                    if let error = json["error"] as? String,
                       error.contains("already") {
                        return true
                    }
                    // Check meta for valid status
                    if let meta = json["meta"] as? [String: Any],
                       let valid = meta["valid"] as? Bool {
                        return valid
                    }
                }
            }

            return false
        } catch {
            print("License validation error: \(error)")
            return false
        }
    }

    func removeLicense() {
        deleteLicenseKey()
    }

    // MARK: - Device Identity

    /// Stable per-Mac identifier, also used by the free-tier proxy for
    /// daily quota accounting.
    var deviceId: String {
        getOrCreateInstanceId()
    }

    /// Gets or creates a unique instance identifier for this Mac
    private func getOrCreateInstanceId() -> String {
        let instanceKey = "instance-id"

        if let existingId = getString(forKey: instanceKey) {
            return existingId
        }

        // Create a new instance ID based on hardware UUID or generate random
        let newId: String
        if let hardwareUUID = getHardwareUUID() {
            newId = "mac-\(hardwareUUID.prefix(8))"
        } else {
            newId = "mac-\(UUID().uuidString.prefix(8))"
        }

        saveString(newId, forKey: instanceKey)
        return newId
    }

    /// Gets the hardware UUID of this Mac
    private func getHardwareUUID() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }

        guard let uuid = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String else {
            return nil
        }

        return uuid
    }

    // MARK: - Keychain Helpers

    private func saveString(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func getString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    private func saveLicenseKey(_ key: String) {
        saveString(key, forKey: licenseKey)
    }

    private func getLicenseKey() -> String? {
        getString(forKey: licenseKey)
    }

    private func deleteLicenseKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: licenseKey
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Debug Methods

    #if DEBUG
    /// Saves a fake license locally WITHOUT LemonSqueezy validation —
    /// the real activateLicense would reject any non-purchased key.
    func debugActivateLicense() {
        saveLicenseKey("DEBUG-LICENSE-KEY")
    }
    #endif
}
