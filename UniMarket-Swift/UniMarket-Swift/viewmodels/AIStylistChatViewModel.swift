import Foundation
import UIKit
import Combine

struct AIStylistMessage: Identifiable {
    enum Role {
        case assistant
        case user
    }

    let id = UUID()
    let role: Role
    let text: String
    let suggestedProducts: [Product]
    let attachedImage: UIImage?
}

@MainActor
final class AIStylistChatViewModel: ObservableObject {
    @Published private(set) var messages: [AIStylistMessage] = [
        AIStylistMessage(
            role: .assistant,
            text: "Ask for a full outfit, a vibe, or a budget. Example: \"Give me a casual campus outfit under $60.\"",
            suggestedProducts: [],
            attachedImage: nil
        )
    ]
    @Published var isSending = false
    @Published var errorMessage: String?

    private let chatbot: StylistChatbot
    private let fallbackChatbot: StylistChatbot = MockStylistChatbotCreator().makeChatbot()

    init(creator: StylistChatbotCreator? = nil) {
        self.chatbot = (creator ?? StylistChatbotFactory.makeCreator()).makeChatbot()
    }

    func send(prompt: String, catalog: [Product], referenceImage: UIImage?) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || referenceImage != nil else { return }

        let userMessage = trimmed.isEmpty ? "Help me build an outfit that complements this photo." : trimmed

        messages.append(AIStylistMessage(
            role: .user,
            text: userMessage,
            suggestedProducts: [],
            attachedImage: referenceImage
        ))
        isSending = true
        errorMessage = nil

        let request = StylistChatRequest(prompt: userMessage, catalog: catalog, referenceImage: referenceImage)

        do {
            let response = try await chatbot.respond(to: request)
            messages.append(AIStylistMessage(
                role: .assistant,
                text: response.message,
                suggestedProducts: response.suggestedProducts,
                attachedImage: nil
            ))
        } catch {
            if let response = try? await fallbackChatbot.respond(to: request) {
                messages.append(AIStylistMessage(
                    role: .assistant,
                    text: response.message,
                    suggestedProducts: response.suggestedProducts,
                    attachedImage: nil
                ))
            }
            errorMessage = "Live AI was unavailable, so the stylist used demo mode."
        }

        isSending = false
    }
}
