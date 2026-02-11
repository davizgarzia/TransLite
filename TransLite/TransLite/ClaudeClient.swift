import Foundation

/// Handles communication with the Claude (Anthropic) API for translation
final class ClaudeClient {
    static let shared = ClaudeClient()

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private let session = URLSession.shared

    private init() {}

    /// Translates text using the Claude API
    /// - Parameters:
    ///   - text: The text to translate
    ///   - apiKey: The Anthropic API key
    ///   - targetLanguage: The language to translate to (default: English)
    ///   - tone: The tone instruction for the translation
    /// - Returns: The translated text
    func translate(
        text: String,
        apiKey: String,
        targetLanguage: String = "English",
        tone: String = "Match the original tone. Allow minimal adjustments only if needed for naturalness."
    ) async throws -> String {

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

        let requestBody = ClaudeRequest(
            model: "claude-sonnet-4-20250514",
            max_tokens: 2048,
            system: systemPrompt,
            messages: [
                ClaudeMessage(role: "user", content: userPrompt)
            ]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            guard let textBlock = decoded.content.first(where: { $0.type == "text" }),
                  let content = textBlock.text else {
                throw ClaudeError.emptyResponse
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)

        case 401:
            throw ClaudeError.invalidAPIKey

        case 429:
            throw ClaudeError.rateLimited

        case 500...599:
            throw ClaudeError.serverError

        default:
            if let errorResponse = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                throw ClaudeError.apiError(errorResponse.error.message)
            }
            throw ClaudeError.unknownError(httpResponse.statusCode)
        }
    }
}

// MARK: - Request/Response Models

private struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [ClaudeMessage]
}

private struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

private struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}

private struct ClaudeErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case invalidResponse
    case emptyResponse
    case invalidAPIKey
    case rateLimited
    case serverError
    case apiError(String)
    case unknownError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from Claude"
        case .emptyResponse:
            return "Empty response from Claude"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimited:
            return "Rate limited - please wait"
        case .serverError:
            return "Claude server error"
        case .apiError(let message):
            return message
        case .unknownError(let code):
            return "Error: HTTP \(code)"
        }
    }
}
