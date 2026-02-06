import Foundation
import Security
import IOKit

/// Manages trial period and license validation using Keychain for persistence
final class TrialManager {
    static let shared = TrialManager()

    private let service = "com.translite.trial"
    private let trialStartKey = "trial-start-date"
    private let lastUsedKey = "last-used-date"
    private let licenseKey = "license-key"

    private let trialDays = 7

    private init() {}

    // MARK: - Trial Status

    enum TrialStatus {
        case active(daysRemaining: Int)
        case expired
        case licensed
    }

    /// Returns the current trial status
    var status: TrialStatus {
        // Check if licensed first
        if isLicensed {
            return .licensed
        }

        // Check for date manipulation
        if hasDateBeenManipulated {
            return .expired
        }

        // Calculate days remaining
        guard let startDate = trialStartDate else {
            // First launch - start trial
            startTrial()
            return .active(daysRemaining: trialDays)
        }

        let daysPassed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
        let daysRemaining = max(0, trialDays - daysPassed)

        if daysRemaining > 0 {
            return .active(daysRemaining: daysRemaining)
        } else {
            return .expired
        }
    }

    /// Whether the app can be used (trial active or licensed)
    var canUseApp: Bool {
        switch status {
        case .active, .licensed:
            return true
        case .expired:
            return false
        }
    }

    /// Updates the last used date - call this on each app launch
    func recordUsage() {
        saveDate(Date(), forKey: lastUsedKey)
    }

    // MARK: - Trial Management

    private var trialStartDate: Date? {
        getDate(forKey: trialStartKey)
    }

    private var lastUsedDate: Date? {
        getDate(forKey: lastUsedKey)
    }

    private var hasDateBeenManipulated: Bool {
        guard let lastUsed = lastUsedDate else { return false }
        // If current date is before last used date, user manipulated system clock
        return Date() < lastUsed
    }

    private func startTrial() {
        let now = Date()
        saveDate(now, forKey: trialStartKey)
        saveDate(now, forKey: lastUsedKey)
    }

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

    func removeLicense() {
        deleteLicenseKey()
    }

    // MARK: - Keychain Helpers

    private func saveDate(_ date: Date, forKey key: String) {
        let timestamp = String(date.timeIntervalSince1970)
        saveString(timestamp, forKey: key)
    }

    private func getDate(forKey key: String) -> Date? {
        guard let timestamp = getString(forKey: key),
              let interval = Double(timestamp) else { return nil }
        return Date(timeIntervalSince1970: interval)
    }

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
    var debugInfo: (startDate: String, lastUsed: String, status: String) {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        let start = trialStartDate.map { formatter.string(from: $0) } ?? "nil"
        let last = lastUsedDate.map { formatter.string(from: $0) } ?? "nil"

        let statusStr: String
        switch status {
        case .active(let days):
            statusStr = "Active (\(days)d left)"
        case .expired:
            statusStr = "Expired"
        case .licensed:
            statusStr = "Licensed"
        }

        return (start, last, statusStr)
    }

    func debugResetTrial() {
        let now = Date()
        saveDate(now, forKey: trialStartKey)
        saveDate(now, forKey: lastUsedKey)
        deleteLicenseKey()
    }

    func debugExpireTrial() {
        let expiredDate = Calendar.current.date(byAdding: .day, value: -(trialDays + 1), to: Date())!
        saveDate(expiredDate, forKey: trialStartKey)
        saveDate(Date(), forKey: lastUsedKey)
        deleteLicenseKey()
    }

    func debugSetDaysLeft(_ days: Int) {
        let startDate = Calendar.current.date(byAdding: .day, value: -(trialDays - days), to: Date())!
        saveDate(startDate, forKey: trialStartKey)
        saveDate(Date(), forKey: lastUsedKey)
        deleteLicenseKey()
    }
    #endif
}
