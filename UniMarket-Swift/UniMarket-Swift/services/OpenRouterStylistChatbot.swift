import Foundation
import UIKit

struct OpenRouterStylistChatbot: StylistChatbot {
    private let service = OpenRouterService.shared
    private let imageAnalyzer = CoreMLAnalysisFacade()

    func respond(to request: StylistChatRequest) async throws -> StylistChatResponse {
        let photoContext = await makePhotoContext(for: request.referenceImage)
        let searchPrompt = StylistPromptBuilder.makeSearchPrompt(prompt: request.prompt, photoContext: photoContext)
        let suggestions = StylistCatalogMatcher.suggestedProducts(for: searchPrompt, in: request.catalog)
        let response = try await service.generateStylistReply(
            prompt: request.prompt,
            catalog: suggestions.isEmpty ? request.catalog : suggestions,
            photoContext: photoContext
        )

        return StylistChatResponse(
            message: response,
            suggestedProducts: Array(suggestions.prefix(3))
        )
    }

    private func makePhotoContext(for image: UIImage?) async -> String? {
        guard let image else { return nil }

        guard let result = try? await imageAnalyzer.analyzeImage(image) else {
            return "The user uploaded a clothing photo and wants an outfit that complements it."
        }

        var parts: [String] = ["Main item: \(result.category)"]
        if !result.colors.isEmpty {
            parts.append("Colors: \(result.colors.joined(separator: ", "))")
        }
        if let style = result.style {
            parts.append("Style: \(style)")
        }
        if let season = result.season {
            parts.append("Season: \(season)")
        }

        return parts.joined(separator: ". ")
    }
}

struct OpenRouterStylistChatbotCreator: StylistChatbotCreator {
    func makeChatbot() -> StylistChatbot {
        OpenRouterStylistChatbot()
    }
}
