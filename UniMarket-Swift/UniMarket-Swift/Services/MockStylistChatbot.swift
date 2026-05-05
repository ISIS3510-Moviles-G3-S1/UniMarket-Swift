import Foundation

struct MockStylistChatbot: StylistChatbot {
    func respond(to request: StylistChatRequest) async throws -> StylistChatResponse {
        let searchPrompt = StylistPromptBuilder.makeSearchPrompt(
            prompt: request.prompt,
            photoContext: request.referenceImage == nil ? nil : "uploaded clothing photo"
        )
        let suggestions = Array(StylistCatalogMatcher.suggestedProducts(for: searchPrompt, in: request.catalog).prefix(3))
        let message: String

        if suggestions.isEmpty {
            if request.referenceImage != nil {
                message = "I would complement your photo with a balanced outfit: one clean matching piece, relaxed bottoms, and simple sneakers. Add a style or occasion if you want a sharper suggestion."
            } else {
                message = "Try a balanced campus outfit: one clean top, relaxed bottoms, and simple sneakers. Ask for a vibe like casual, streetwear, or formal and I can refine it."
            }
        } else {
            let names = suggestions.map(\.title)
            let joined = ListFormatter.localizedString(byJoining: names)
            if request.referenceImage != nil {
                message = "To complement the uploaded piece, I would pair it with \(joined). This keeps the outfit cohesive and realistic with items already in UniMarket."
            } else {
                message = "I would build your outfit with \(joined). This keeps the look cohesive, easy to wear on campus, and realistic with items already in UniMarket."
            }
        }

        return StylistChatResponse(message: message, suggestedProducts: suggestions)
    }
}

struct MockStylistChatbotCreator: StylistChatbotCreator {
    func makeChatbot() -> StylistChatbot {
        MockStylistChatbot()
    }
}
