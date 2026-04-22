import Foundation
import UIKit
import Combine
import FirebaseAuth

struct AIStylistMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable {
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let text: String
    let suggestedProducts: [Product]
    private let attachedImageData: Data?

    var attachedImage: UIImage? {
        guard let attachedImageData else { return nil }
        return UIImage(data: attachedImageData)
    }

    init(
        id: UUID = UUID(),
        role: Role,
        text: String,
        suggestedProducts: [Product],
        attachedImage: UIImage?
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.suggestedProducts = suggestedProducts
        self.attachedImageData = attachedImage?.jpegData(compressionQuality: 0.8)
    }
}

@MainActor
final class AIStylistChatViewModel: ObservableObject {
    @Published private(set) var messages: [AIStylistMessage]
    @Published var isSending = false
    @Published var errorMessage: String?

    private static let defaultMessages = [
        AIStylistMessage(
            role: .assistant,
            text: "Ask for a full outfit, a vibe, or a budget. Example: \"Give me a casual campus outfit under $60.\"",
            suggestedProducts: [],
            attachedImage: nil
        )
    ]

    private let chatbot: StylistChatbot
    private let fallbackChatbot: StylistChatbot = MockStylistChatbotCreator().makeChatbot()
    private let conversationStore = AIStylistConversationFileStore()

    init(creator: StylistChatbotCreator? = nil) {
        self.messages = Self.defaultMessages
        self.chatbot = (creator ?? StylistChatbotFactory.makeCreator()).makeChatbot()
        Task {
            await loadPersistedMessages()
        }
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
        persistMessages()
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
            persistMessages()
        } catch {
            if let response = try? await fallbackChatbot.respond(to: request) {
                messages.append(AIStylistMessage(
                    role: .assistant,
                    text: response.message,
                    suggestedProducts: response.suggestedProducts,
                    attachedImage: nil
                ))
                persistMessages()
            }
            errorMessage = "Live AI was unavailable, so the stylist used demo mode."
        }

        isSending = false
    }

    private func loadPersistedMessages() async {
        do {
            let persistedMessages = try await conversationStore.loadConversation(for: storageKey)
            if persistedMessages.isEmpty {
                messages = Self.defaultMessages
            } else {
                messages = persistedMessages
            }
        } catch {
            messages = Self.defaultMessages
        }
    }

    private func persistMessages() {
        let snapshot = messages
        let storageKey = self.storageKey

        Task {
            try? await conversationStore.saveConversation(snapshot, for: storageKey)
        }
    }

    private var storageKey: String {
        Auth.auth().currentUser?.uid ?? "guest"
    }
}
