#if SETAPP
import Foundation
import Setapp
import SetappAI

/// Talks to the Setapp AI Gateway through the SetappAI SDK. The Setapp build
/// never touches the TransLite Worker or provider API keys: requests are paid
/// with the AI credits included in the user's Setapp plan, and the SDK handles
/// OAuth/token management using the client credentials in Info-Setapp.plist.
///
/// The model is chosen internally and never exposed to the user.
actor SetappAIClient {
    static let shared = SetappAIClient()

    /// Cheap-and-fast first. Matched as substrings because gateway model ids
    /// get renamed over time; anything unmatched falls back to the first
    /// available chat model.
    private static let preferredModelSubstrings = [
        "gpt-4o-mini", "gpt-4.1-mini", "gemini-2.0-flash", "haiku"
    ]

    private var isConfigured = false
    private var cachedModel: SetappAIAPI.Model?
    /// Models rejected by the gateway for this user's plan (modelNotAllowed),
    /// excluded from later selection.
    private var unavailableModelIDs: Set<String> = []

    // MARK: - Public API (mirrors OpenAIClient/ClaudeClient)

    func translate(text: String, targetLanguage: String, tone: String) async throws -> String {
        let systemPrompt = """
        You are a translation engine.

        Return ONLY the translated text.

        Preserve the original formatting and style as much as possible:
        - Preserve case (lowercase stays lowercase)
        - Preserve line breaks, spacing, lists, numbering
        - Do NOT add quotes unless present in the original
        - Do NOT add emojis or remove existing ones
        - Do NOT add markdown, code blocks, or wrappers

        Translation rules:
        - Keep the original meaning and tone
        - Allow minimal rephrasing ONLY when a literal translation sounds unnatural
        - Do NOT embellish, over-polish, or add new ideas
        - Avoid intensifiers or filler words unless they exist in the original
        - Punctuation may be adjusted only if strictly necessary for clarity in the target language

        If something cannot be translated, keep it as-is.
        """

        let userPrompt = """
        Target language: \(targetLanguage)
        Tone rule: \(tone)

        TEXT:
        \(text)
        """

        return try await complete(instructions: systemPrompt, input: userPrompt)
    }

    func improve(text: String) async throws -> String {
        let systemPrompt = """
        You are a writing assistant that improves text.

        Return ONLY the improved text.

        Rules:
        - Fix grammar, spelling, and punctuation errors
        - Improve clarity and readability
        - Keep the same language as the input (do NOT translate)
        - Preserve the original meaning and intent
        - Preserve formatting (line breaks, lists, etc.)
        - Do NOT add quotes, markdown, or wrappers
        - Do NOT add emojis unless present in original
        - Keep the same tone (formal/casual)
        - Make minimal changes - only fix what needs fixing
        """

        let userPrompt = """
        Improve this text:

        \(text)
        """

        return try await complete(instructions: systemPrompt, input: userPrompt)
    }

    // MARK: - Request plumbing

    private func complete(instructions: String, input: String) async throws -> String {
        try configureIfNeeded()

        do {
            let model = try await resolveModel()
            do {
                return try await run(model: model, instructions: instructions, input: input)
            } catch let error as SetappAIError where error.code == .modelNotAllowed {
                // The user's plan may not include the cached model; retry
                // once with the next candidate.
                unavailableModelIDs.insert(model.id)
                cachedModel = nil
                let fallback = try await resolveModel()
                return try await run(model: fallback, instructions: instructions, input: input)
            }
        } catch let error as SetappAIError {
            throw SetappAIClientError(error)
        }
    }

    private func run(model: SetappAIAPI.Model, instructions: String, input: String) async throws -> String {
        let stream = try await SetappManager.shared.ai.responses.createStream(
            model: model,
            input: [.message(input)],
            instructions: instructions,
            maxOutputTokens: 2048
        )

        var collected = ""
        for try await event in stream {
            if case let .response(.outputText(.delta(delta))) = event {
                collected += delta.delta
            }
        }

        let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SetappAIClientError.emptyResponse }
        return trimmed
    }

    /// Applies the OAuth configuration once. Credentials come from
    /// Setapp.xcconfig via Info-Setapp.plist; `.propagate` surfaces errors as
    /// thrown SetappAIErrors so TransLite's own HUD presents them.
    private func configureIfNeeded() throws {
        guard !isConfigured else { return }

        let clientID = Bundle.main.object(forInfoDictionaryKey: "SetappAIOAuthClientID") as? String ?? ""
        let secret = Bundle.main.object(forInfoDictionaryKey: "SetappAIOAuthSecret") as? String ?? ""
        guard !clientID.isEmpty, !secret.isEmpty else {
            throw SetappAIClientError.notConfigured
        }

        SetappManager.shared.ai.set(configuration: .init(
            authConfiguration: AuthConfiguration(
                oauthClientId: clientID,
                oauthSecret: secret
            ),
            mode: .propagate
        ))
        isConfigured = true
    }

    /// Fresh account-wide credit balance (current, plan grant). Debug/testing
    /// aid — the shipping UI never shows credits (Setapp owns that surface).
    func creditBalances() async throws -> (current: Decimal, max: Decimal) {
        try configureIfNeeded()
        let balances = try await SetappManager.shared.ai.credits.balances(forceUpdate: true)
        return (balances.totalAvailable.amount, balances.totalInitialAmount.amount)
    }

    private func resolveModel() async throws -> SetappAIAPI.Model {
        if let cachedModel {
            return cachedModel
        }

        let models = try await SetappManager.shared.ai.models.list()
        let chatModels = models.filter {
            $0.mode == .chat && !unavailableModelIDs.contains($0.id)
        }

        let preferred = Self.preferredModelSubstrings
            .compactMap { substring in
                chatModels.first { $0.id.localizedCaseInsensitiveContains(substring) }
            }
            .first

        guard let model = preferred ?? chatModels.first else {
            throw SetappAIClientError.noModelsAvailable
        }

        cachedModel = model
        return model
    }
}

// MARK: - Errors

/// Setapp gateway failures mapped into user-presentable TransLite errors.
/// Raw SDK/HTTP details never reach the HUD.
enum SetappAIClientError: LocalizedError {
    case notConfigured
    case insufficientCredits
    case rateLimited
    case noModelsAvailable
    case emptyResponse
    case gateway(String?)

    init(_ error: SetappAIError) {
        switch error.code {
        case .insufficientCredits:
            self = .insufficientCredits
        case .rateLimit:
            self = .rateLimited
        default:
            self = .gateway(nil)
        }
    }

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Setapp AI is not configured in this build"
        case .insufficientCredits:
            return "You've used your Setapp AI credits for this billing period."
        case .rateLimited:
            return "Too many requests — please wait a moment"
        case .noModelsAvailable:
            return "Translation service unavailable — please try again later"
        case .emptyResponse:
            return "Empty response from the translation service"
        case .gateway(let message):
            return message ?? "Translation service error — please try again"
        }
    }

    /// Category label for anonymous analytics (never contains user text).
    var analyticsCategory: String {
        switch self {
        case .notConfigured: return "not_configured"
        case .insufficientCredits: return "insufficient_credits"
        case .rateLimited: return "rate_limited"
        case .noModelsAvailable: return "provider_error"
        case .emptyResponse: return "empty_response"
        case .gateway: return "provider_error"
        }
    }
}
#endif
