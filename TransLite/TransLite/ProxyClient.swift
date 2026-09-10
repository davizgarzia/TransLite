import Foundation

/// Talks to the TransLite API Worker (worker/ in this repo), which proxies
/// free-tier (and later pro-tier) requests to the LLM providers using our
/// server-side API keys and enforces per-tier limits. BYOK users never use
/// this client.
final class ProxyClient {
    static let shared = ProxyClient()

    private let baseURL = URL(string: "https://translite-api.translite-api.workers.dev")!

    private let session = URLSession.shared

    /// Free-tier limits, used for pre-flight checks before spending a request.
    /// Refreshed from GET /v1/config at launch; the fallback mirrors the
    /// server defaults in worker/src/config.ts.
    struct TierLimits {
        var maxChars: Int
        var dailyQuota: Int?
        /// Target languages the tier may translate into; nil = all.
        var allowedTargets: [String]?
    }

    private(set) var freeLimits = TierLimits(maxChars: 1000, dailyQuota: 20, allowedTargets: ["English"])

    /// Translations left today for this device, from the last response's
    /// X-Quota-Remaining header. Persisted per UTC day (the server's reset
    /// boundary); nil until the first proxied request of the day.
    private(set) var quotaRemaining: Int? {
        didSet {
            guard let value = quotaRemaining else { return }
            UserDefaults.standard.set(value, forKey: "freeQuotaRemaining")
            UserDefaults.standard.set(Self.utcDay(), forKey: "freeQuotaRemainingDay")
        }
    }

    private static func utcDay() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date())
    }

    private init() {
        if UserDefaults.standard.string(forKey: "freeQuotaRemainingDay") == Self.utcDay(),
           let cachedRemaining = UserDefaults.standard.object(forKey: "freeQuotaRemaining") as? Int {
            quotaRemaining = cachedRemaining
        }
        if let cachedMaxChars = UserDefaults.standard.object(forKey: "freeTierMaxChars") as? Int {
            freeLimits.maxChars = cachedMaxChars
        }
        if let cachedQuota = UserDefaults.standard.object(forKey: "freeTierDailyQuota") as? Int {
            freeLimits.dailyQuota = cachedQuota
        }
        if let cachedTargets = UserDefaults.standard.stringArray(forKey: "freeTierTargets") {
            freeLimits.allowedTargets = cachedTargets
        }
    }

    // MARK: - Config

    /// Fetches current limits so client-side checks stay in sync with the
    /// server without shipping an app update. Safe to call at every launch.
    func refreshLimits() async {
        struct ConfigResponse: Decodable {
            struct Tier: Decodable {
                let max_chars: Int
                let daily_quota: Int?
                let target_languages: [String]?
            }
            let tiers: [String: Tier]
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/config"))
        request.timeoutInterval = 10

        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(ConfigResponse.self, from: data),
              let free = decoded.tiers["free"] else {
            return
        }

        freeLimits = TierLimits(
            maxChars: free.max_chars,
            dailyQuota: free.daily_quota,
            allowedTargets: free.target_languages
        )
        UserDefaults.standard.set(free.max_chars, forKey: "freeTierMaxChars")
        if let quota = free.daily_quota {
            UserDefaults.standard.set(quota, forKey: "freeTierDailyQuota")
        }
        if let targets = free.target_languages {
            UserDefaults.standard.set(targets, forKey: "freeTierTargets")
        } else {
            UserDefaults.standard.removeObject(forKey: "freeTierTargets")
        }
    }

    // MARK: - Completion

    func translate(text: String, targetLanguage: String, tone: TranslationTone) async throws -> String {
        try await send(path: "v1/translate", body: [
            "text": text,
            "target_language": targetLanguage,
            "tone": tone.rawValue,
            "device_id": LicenseManager.shared.deviceId
        ])
    }

    func improve(text: String) async throws -> String {
        try await send(path: "v1/improve", body: [
            "text": text,
            "device_id": LicenseManager.shared.deviceId
        ])
    }

    private func send(path: String, body: [String: String]) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProxyError.invalidResponse
        }

        if let remaining = httpResponse.value(forHTTPHeaderField: "X-Quota-Remaining").flatMap(Int.init) {
            quotaRemaining = remaining
        }

        if httpResponse.statusCode == 200 {
            struct SuccessResponse: Decodable { let text: String }
            guard let decoded = try? JSONDecoder().decode(SuccessResponse.self, from: data) else {
                throw ProxyError.invalidResponse
            }
            return decoded.text
        }

        struct ErrorResponse: Decodable {
            struct Detail: Decodable {
                let code: String
                let message: String
            }
            let error: Detail
        }
        guard let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            throw ProxyError.serverError(httpResponse.statusCode)
        }

        switch decoded.error.code {
        case "text_too_long": throw ProxyError.textTooLong(decoded.error.message)
        case "quota_exceeded":
            quotaRemaining = 0
            throw ProxyError.quotaExceeded(decoded.error.message)
        case "language_not_allowed": throw ProxyError.languageNotAllowed(decoded.error.message)
        case "upstream_busy": throw ProxyError.busy(decoded.error.message)
        default: throw ProxyError.apiError(decoded.error.message)
        }
    }
}

// MARK: - Errors

enum ProxyError: LocalizedError {
    case invalidResponse
    case textTooLong(String)
    case quotaExceeded(String)
    case languageNotAllowed(String)
    case busy(String)
    case apiError(String)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from TransLite service"
        case .textTooLong(let message), .quotaExceeded(let message),
             .languageNotAllowed(let message), .busy(let message),
             .apiError(let message):
            return message
        case .serverError(let code):
            return "TransLite service error (HTTP \(code))"
        }
    }
}
