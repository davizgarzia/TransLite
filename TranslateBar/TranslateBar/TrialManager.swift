import Foundation
import Security

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

    /// Validates and saves a license key
    /// - Parameter key: The license key to validate
    /// - Returns: True if the license is valid and was saved
    func activateLicense(_ key: String) async -> Bool {
        // TODO: Validate against LemonSqueezy API
        // For now, accept any non-empty key that starts with expected prefix
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedKey.isEmpty else { return false }

        // In production, validate against LemonSqueezy API:
        // let isValid = await LemonSqueezyAPI.validateLicense(trimmedKey)
        // if isValid { saveLicenseKey(trimmedKey) }
        // return isValid

        // For now, save any key (replace with real validation later)
        saveLicenseKey(trimmedKey)
        return true
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
