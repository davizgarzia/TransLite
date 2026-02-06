import Foundation

/// Handles communication with the OpenAI API for translation
final class OpenAIClient {
    static let shared = OpenAIClient()

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let session = URLSession.shared

    private init() {}

    /// Translates text using the OpenAI API
    /// - Parameters:
    ///   - text: The text to translate
    ///   - apiKey: The OpenAI API key
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

    let requestBody = OpenAIRequest(
        model: "gpt-4o-mini",
        messages: [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: userPrompt)
        ],
        temperature: 0.1,
        max_tokens: 2048
    )

    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(requestBody)
    request.timeoutInterval = 30

    let (data, response) = try await session.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw OpenAIError.invalidResponse
    }

    switch httpResponse.statusCode {
    case 200:
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw OpenAIError.emptyResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)

    case 401:
        throw OpenAIError.invalidAPIKey

    case 429:
        throw OpenAIError.rateLimited

    case 500...599:
        throw OpenAIError.serverError

    default:
        if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
            throw OpenAIError.apiError(errorResponse.error.message)
        }
        throw OpenAIError.unknownError(httpResponse.statusCode)
    }
}
}

// MARK: - Request/Response Models

private struct OpenAIRequest: Encodable {
    let model: String
    let messages: [Message]
    let temperature: Double
    let max_tokens: Int
}

private struct Message: Codable {
    let role: String
    let content: String
}

private struct OpenAIResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }
}

private struct OpenAIErrorResponse: Decodable {
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let message: String
    }
}

// MARK: - Errors

enum OpenAIError: LocalizedError {
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
            return "Invalid response from OpenAI"
        case .emptyResponse:
            return "Empty response from OpenAI"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimited:
            return "Rate limited - please wait"
        case .serverError:
            return "OpenAI server error"
        case .apiError(let message):
            return message
        case .unknownError(let code):
            return "Error: HTTP \(code)"
        }
    }
}
