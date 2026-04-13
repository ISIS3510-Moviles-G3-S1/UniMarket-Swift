import Foundation

struct StylistChatRequest {
    let prompt: String
    let catalog: [Product]
}

struct StylistChatResponse {
    let message: String
    let suggestedProducts: [Product]
}

protocol StylistChatbot {
    func respond(to request: StylistChatRequest) async throws -> StylistChatResponse
}

protocol StylistChatbotCreator {
    func makeChatbot() -> StylistChatbot
}

struct OpenRouterStylistChatbotCreator: StylistChatbotCreator {
    func makeChatbot() -> StylistChatbot {
        OpenRouterStylistChatbot()
    }
}

struct MockStylistChatbotCreator: StylistChatbotCreator {
    func makeChatbot() -> StylistChatbot {
        MockStylistChatbot()
    }
}

enum StylistChatbotFactory {
    static func makeCreator() -> StylistChatbotCreator {
        APIConfig.isOpenRouterConfigured()
            ? OpenRouterStylistChatbotCreator()
            : MockStylistChatbotCreator()
    }
}

struct OpenRouterStylistChatbot: StylistChatbot {
    private let service = OpenRouterService.shared

    func respond(to request: StylistChatRequest) async throws -> StylistChatResponse {
        let suggestions = StylistCatalogMatcher.suggestedProducts(for: request.prompt, in: request.catalog)
        let response = try await service.generateStylistReply(
            prompt: request.prompt,
            catalog: suggestions.isEmpty ? request.catalog : suggestions
        )

        return StylistChatResponse(
            message: response,
            suggestedProducts: Array(suggestions.prefix(3))
        )
    }
}

struct MockStylistChatbot: StylistChatbot {
    func respond(to request: StylistChatRequest) async throws -> StylistChatResponse {
        let suggestions = Array(StylistCatalogMatcher.suggestedProducts(for: request.prompt, in: request.catalog).prefix(3))
        let message: String

        if suggestions.isEmpty {
            message = "Try a balanced campus outfit: one clean top, relaxed bottoms, and simple sneakers. Ask for a vibe like casual, streetwear, or formal and I can refine it."
        } else {
            let names = suggestions.map(\.title)
            let joined = ListFormatter.localizedString(byJoining: names)
            message = "I would build your outfit with \(joined). This keeps the look cohesive, easy to wear on campus, and realistic with items already in UniMarket."
        }

        return StylistChatResponse(message: message, suggestedProducts: suggestions)
    }
}

enum StylistCatalogMatcher {
    static func suggestedProducts(for prompt: String, in catalog: [Product]) -> [Product] {
        guard !catalog.isEmpty else { return [] }

        let tokens = Set(
            prompt
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )

        let ranked = catalog
            .filter { $0.status == .active }
            .map { product in
                let haystack = "\(product.title) \(product.description) \(product.tags.joined(separator: " ")) \(product.conditionTag)".lowercased()
                let score = tokens.reduce(into: 0) { partialResult, token in
                    if haystack.contains(token) {
                        partialResult += 1
                    }
                }
                return (product, score)
            }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.createdAt > $1.0.createdAt
                }
                return $0.1 > $1.1
            }

        let matched = ranked.filter { $0.1 > 0 }.map(\.0)
        if !matched.isEmpty {
            return matched
        }

        return Array(ranked.prefix(3).map(\.0))
    }
}
