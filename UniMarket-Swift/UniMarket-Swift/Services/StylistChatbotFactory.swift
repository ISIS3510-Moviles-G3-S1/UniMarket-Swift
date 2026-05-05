import Foundation

enum StylistChatbotFactory {
    static func makeCreator() -> StylistChatbotCreator {
        APIConfig.isOpenRouterConfigured()
            ? OpenRouterStylistChatbotCreator()
            : MockStylistChatbotCreator()
    }
}
