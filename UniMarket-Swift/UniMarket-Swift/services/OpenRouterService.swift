import Foundation

final class OpenRouterService {
    static let shared = OpenRouterService()

    private init() {}

    func generateEcoRecommendation(prompt: String) async throws -> String {
        print("DEBUG[OpenRouter] generateEcoRecommendation called")

        guard APIConfig.isOpenRouterConfigured() else {
            print("DEBUG[OpenRouter] Missing API key configuration")
            throw OpenRouterError.missingAPIKey
        }

        guard let url = URL(string: APIConfig.openRouterBaseURL) else {
            print("DEBUG[OpenRouter] Invalid URL: \(APIConfig.openRouterBaseURL)")
            throw OpenRouterError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: APIConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APIConfig.openRouterAPIKey)", forHTTPHeaderField: "Authorization")

        if !APIConfig.openRouterReferer.isEmpty {
            request.setValue(APIConfig.openRouterReferer, forHTTPHeaderField: "HTTP-Referer")
        }
        if !APIConfig.openRouterTitle.isEmpty {
            request.setValue(APIConfig.openRouterTitle, forHTTPHeaderField: "X-OpenRouter-Title")
        }

        let body = ORChatRequest(
            model: APIConfig.openRouterModel,
            messages: [
                ORChatMessage(role: "system", content: "You are Eco, a friendly and motivational sustainability companion inside UniMarket, a student marketplace app for clothing only. Your job is to celebrate the user's progress and give them one specific, encouraging nudge based on their stats. Tone: warm, upbeat, like a supportive friend — never preachy or generic. Always address the user by name. Reference their actual numbers (XP, transactions, listings sold) to make it feel personal. Max 240 characters total."),
                ORChatMessage(role: "user", content: prompt)
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)
        print("DEBUG[OpenRouter] Sending request model=\(APIConfig.openRouterModel) promptChars=\(prompt.count)")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("DEBUG[OpenRouter] Invalid non-HTTP response")
            throw OpenRouterError.invalidResponse
        }

        print("DEBUG[OpenRouter] Response status=\(http.statusCode)")

        guard (200...299).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(ORErrorResponse.self, from: data)
            print("DEBUG[OpenRouter] Request failed message=\(apiError?.error.message ?? "<none>")")
            throw OpenRouterError.server(statusCode: http.statusCode, message: apiError?.error.message)
        }

        let decoded = try JSONDecoder().decode(ORChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("DEBUG[OpenRouter] Empty content in successful response")
            throw OpenRouterError.emptyContent
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG[OpenRouter] Success contentChars=\(trimmed.count)")
        return trimmed
    }

    func generateImpactInsight(prompt: String) async throws -> ImpactInsight {
        guard APIConfig.isOpenRouterConfigured() else {
            throw OpenRouterError.missingAPIKey
        }

        guard let url = URL(string: APIConfig.openRouterBaseURL) else {
            throw OpenRouterError.invalidURL
        }

        var request = URLRequest(url: url, timeoutInterval: APIConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APIConfig.openRouterAPIKey)", forHTTPHeaderField: "Authorization")

        if !APIConfig.openRouterReferer.isEmpty {
            request.setValue(APIConfig.openRouterReferer, forHTTPHeaderField: "HTTP-Referer")
        }
        if !APIConfig.openRouterTitle.isEmpty {
            request.setValue(APIConfig.openRouterTitle, forHTTPHeaderField: "X-OpenRouter-Title")
        }

        let system = """
        You are Eco, UniMarket's sustainability analyst. You turn a student's real reuse numbers into one sharp, data-grounded insight \
        that feels personal. Follow these rules strictly:
        1. Open with ONE vivid, concrete comparison tied to the biggest number (showers of water, km of driving avoided, or tree-years of CO2).
        2. Call out the user's STRONGEST category by name and why it over-indexes (e.g., "your jackets alone carry most of that water saving").
        3. End with ONE specific, non-generic next action tied to what they already do well.
        Rules: warm, direct tone. No emojis. No hashtags. No preachy climate platitudes. No round-number invention — use only the numbers \
        provided. Maximum 3 short sentences, 320 characters total.
        """

        let body = ORChatRequest(
            model: APIConfig.openRouterModel,
            messages: [
                ORChatMessage(role: "system", content: system),
                ORChatMessage(role: "user", content: prompt)
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(ORErrorResponse.self, from: data)
            throw OpenRouterError.server(statusCode: http.statusCode, message: apiError?.error.message)
        }

        let decoded = try JSONDecoder().decode(ORChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.emptyContent
        }

        return ImpactInsight(
            message: content.trimmingCharacters(in: .whitespacesAndNewlines),
            promptTokens: decoded.usage?.prompt_tokens ?? 0,
            completionTokens: decoded.usage?.completion_tokens ?? 0,
            totalTokens: decoded.usage?.total_tokens ?? 0
        )
    }

    func generateStylistReply(prompt: String, catalog: [Product], photoContext: String? = nil) async throws -> String {
        guard APIConfig.isOpenRouterConfigured() else {
            throw OpenRouterError.missingAPIKey
        }

        guard let url = URL(string: APIConfig.openRouterBaseURL) else {
            throw OpenRouterError.invalidURL
        }

        let catalogSummary = catalog.prefix(8).enumerated().map { index, product in
            let tags = product.tags.prefix(3).joined(separator: ", ")
            return "\(index + 1). \(product.title) - $\(product.price). Tags: \(tags). Condition: \(product.conditionTag)."
        }.joined(separator: "\n")

        var request = URLRequest(url: url, timeoutInterval: APIConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APIConfig.openRouterAPIKey)", forHTTPHeaderField: "Authorization")

        if !APIConfig.openRouterReferer.isEmpty {
            request.setValue(APIConfig.openRouterReferer, forHTTPHeaderField: "HTTP-Referer")
        }
        if !APIConfig.openRouterTitle.isEmpty {
            request.setValue(APIConfig.openRouterTitle, forHTTPHeaderField: "X-OpenRouter-Title")
        }

        let body = ORChatRequest(
            model: APIConfig.openRouterModel,
            messages: [
                ORChatMessage(
                    role: "system",
                    content: """
                    You are UniMarket's AI Stylist. Build simple, practical outfit suggestions for a student marketplace app focused on clothing.
                    Keep the tone friendly and concise.
                    When possible, use only items from the provided catalog.
                    Give one complete outfit, mention 2-4 specific pieces, and end with one short styling note.
                    Keep the response under 120 words.
                    """
                ),
                ORChatMessage(
                    role: "user",
                    content: """
                    User request: \(prompt)

                    \(photoContext.map { "Photo context: \($0)\n" } ?? "")
                    Available catalog items:
                    \(catalogSummary)
                    """
                )
            ]
        )

        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(ORErrorResponse.self, from: data)
            throw OpenRouterError.server(statusCode: http.statusCode, message: apiError?.error.message)
        }

        let decoded = try JSONDecoder().decode(ORChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenRouterError.emptyContent
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ORChatRequest: Encodable {
    let model: String
    let messages: [ORChatMessage]
}

private struct ORChatMessage: Codable {
    let role: String
    let content: String
}

private struct ORChatResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: ORChatMessage
    }

    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
        let total_tokens: Int?
    }
}

struct ImpactInsight {
    let message: String
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

private struct ORErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String
    }
    let error: APIError
}

enum OpenRouterError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case emptyContent
    case server(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenRouter API key is missing."
        case .invalidURL:
            return "OpenRouter URL is invalid."
        case .invalidResponse:
            return "Invalid response from OpenRouter."
        case .emptyContent:
            return "OpenRouter returned an empty recommendation."
        case .server(let statusCode, let message):
            if let message, !message.isEmpty {
                return "OpenRouter error \(statusCode): \(message)"
            }
            return "OpenRouter error \(statusCode)."
        }
    }
}
