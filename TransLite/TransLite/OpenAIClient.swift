import Foundation

/// Handles communication with the OpenAI API for translation
final class OpenAIClient {
    static let shared = OpenAIClient()
    static let defaultBaseURL = "https://api.openai.com/v1"
    static let defaultModel = "gpt-4o-mini"

    private let session = URLSession.shared

    private init() {}

    private func makeEndpointURL(baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmed)/chat/completions") else {
            throw OpenAIError.invalidEndpointURL
        }
        return url
    }

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
    tone: String = "Match the original tone. Allow minimal adjustments only if needed for naturalness.",
    baseURL: String = OpenAIClient.defaultBaseURL,
    model: String = OpenAIClient.defaultModel
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
        model: model,
        messages: [
            Message(role: "system", content: systemPrompt),
            Message(role: "user", content: userPrompt)
        ],
        temperature: 0.1,
        max_tokens: 2048
    )

    var request = URLRequest(url: try makeEndpointURL(baseURL: baseURL))
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
        throw OpenAIError.rateLimited(Self.rateLimitMessage(from: data, response: httpResponse))

    case 500...599:
        throw OpenAIError.serverError

    default:
        if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
            throw OpenAIError.apiError(errorResponse.error.message)
        }
        throw OpenAIError.unknownError(httpResponse.statusCode)
    }
}

    /// Improves text grammar and clarity using the OpenAI API
    /// - Parameters:
    ///   - text: The text to improve
    ///   - apiKey: The OpenAI API key
    /// - Returns: The improved text
    func improve(
        text: String,
        apiKey: String,
        baseURL: String = OpenAIClient.defaultBaseURL,
        model: String = OpenAIClient.defaultModel
    ) async throws -> String {
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

        let requestBody = OpenAIRequest(
            model: model,
            messages: [
                Message(role: "system", content: systemPrompt),
                Message(role: "user", content: userPrompt)
            ],
            temperature: 0.1,
            max_tokens: 2048
        )

        var request = URLRequest(url: try makeEndpointURL(baseURL: baseURL))
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
            throw OpenAIError.rateLimited(Self.rateLimitMessage(from: data, response: httpResponse))

        case 500...599:
            throw OpenAIError.serverError

        default:
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw OpenAIError.apiError(errorResponse.error.message)
            }
            throw OpenAIError.unknownError(httpResponse.statusCode)
        }
    }

    private static func rateLimitMessage(from data: Data, response: HTTPURLResponse) -> String {
        let fallback = "Rate limited by OpenAI - please wait"
        let providerMessage = (try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data))?.error.message ?? fallback

        guard let retryAfter = response.value(forHTTPHeaderField: "Retry-After"),
              !retryAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return providerMessage
        }

        return "\(providerMessage) Try again in \(retryAfter)s."
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
    case rateLimited(String)
    case serverError
    case apiError(String)
    case unknownError(Int)
    case invalidEndpointURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from OpenAI"
        case .emptyResponse:
            return "Empty response from OpenAI"
        case .invalidAPIKey:
            return "Invalid API key"
        case .rateLimited(let message):
            return message
        case .serverError:
            return "OpenAI server error"
        case .apiError(let message):
            return message
        case .unknownError(let code):
            return "Error: HTTP \(code)"
        case .invalidEndpointURL:
            return "Invalid endpoint URL"
        }
    }
}
