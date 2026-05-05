import Foundation

protocol StylistChatbot {
    func respond(to request: StylistChatRequest) async throws -> StylistChatResponse
}
