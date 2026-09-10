import Foundation
import Security
import IOKit

/// Which product a license key belongs to.
enum LicenseKind: String {
    /// Pro subscription: translations run through our proxy with high limits.
    case pro
    /// Lifetime BYOK license: unlocks configuring the user's own API keys.
    case byok
}

/// Manages license validation and the per-device identifier, both persisted
/// in the Keychain. The app has three states: free tier (default), Pro
/// subscriber, or BYOK licensed.
final class LicenseManager {
    static let shared = LicenseManager()

    // LemonSqueezy product ids used to tell a Pro subscription key from a
    // BYOK lifetime key. Must match PRO_PRODUCT_IDS in worker/src/license.ts.
    private static let proProductIDs: Set<Int> = [
        1352278, // TransLite Pro (live)
        1352332  // TransLite Pro test-mode duplicate - REMOVE before launch
    ]

    // Keep the historical service name: existing licenses and instance ids
    // were stored under it before the trial was removed.
    private let service = "com.translite.trial"
    private let licenseKey = "license-key"
    private let licenseKindKey = "license-kind"

    private init() {}

    // MARK: - License Management

    var isLicensed: Bool {
        getLicenseKey() != nil
    }

    /// The stored license key, needed by the proxy for Pro requests.
    var storedLicenseKey: String? {
        getLicenseKey()
    }

    /// Kind of the stored license. Licenses saved before kinds existed
    /// (early BYOK buyers) have no stored kind and default to .byok.
    var licenseKind: LicenseKind? {
        guard isLicensed else { return nil }
        guard let raw = getString(forKey: licenseKindKey),
              let kind = LicenseKind(rawValue: raw) else { return .byok }
        return kind
    }

    /// Validates and saves a license key using LemonSqueezy API
    /// - Parameter key: The license key to validate
    /// - Returns: True if the license is valid and was saved
    func activateLicense(_ key: String) async -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return false }

        // Validate against LemonSqueezy API
        guard let productID = await validateWithLemonSqueezy(trimmedKey) else {
            return false
        }

        saveLicenseKey(trimmedKey)
        let kind: LicenseKind = Self.proProductIDs.contains(productID) ? .pro : .byok
        saveString(kind.rawValue, forKey: licenseKindKey)
        return true
    }

    /// Validates a license key with LemonSqueezy's API
    /// - Returns: the product id of the license when valid, nil otherwise
    private func validateWithLemonSqueezy(_ licenseKey: String) async -> Int? {
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
                return nil
            }

            // 200 = activated, 400 = already activated (which is fine)
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 400 {
                // Parse response to check if valid
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let meta = json["meta"] as? [String: Any]
                    // product_id distinguishes Pro subscription from BYOK
                    let productID = meta?["product_id"] as? Int ?? -1

                    // Check if license is valid (activated or already activated)
                    if let activated = json["activated"] as? Bool, activated {
                        return productID
                    }
                    // Check for "already activated" error (still valid)
                    if let error = json["error"] as? String,
                       error.contains("already") {
                        return productID
                    }
                    // Check meta for valid status
                    if let valid = meta?["valid"] as? Bool, valid {
                        return productID
                    }
                }
            }

            return nil
        } catch {
            print("License validation error: \(error)")
            return nil
        }
    }

    func removeLicense() {
        deleteLicenseKey()
        deleteString(forKey: licenseKindKey)
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

    private func deleteString(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func deleteLicenseKey() {
        deleteString(forKey: licenseKey)
    }

    // MARK: - Debug Methods

    #if DEBUG
    /// Saves a fake license locally WITHOUT LemonSqueezy validation —
    /// the real activateLicense would reject any non-purchased key.
    func debugActivateLicense(kind: LicenseKind) {
        saveLicenseKey("DEBUG-LICENSE-KEY")
        saveString(kind.rawValue, forKey: licenseKindKey)
    }
    #endif
}
