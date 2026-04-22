import Foundation
import UIKit

struct AIStylistMessage: Identifiable, Hashable, Codable {
    enum Role: String, Codable {
        case assistant
        case user
    }

    let id: UUID
    let role: Role
    let text: String
    let suggestedProducts: [Product]
    let sentAt: Date
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
        attachedImage: UIImage?,
        sentAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.suggestedProducts = suggestedProducts
        self.sentAt = sentAt
        self.attachedImageData = attachedImage?.jpegData(compressionQuality: 0.8)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case suggestedProducts
        case sentAt
        case attachedImageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(Role.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        suggestedProducts = try container.decodeIfPresent([Product].self, forKey: .suggestedProducts) ?? []
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt) ?? .now
        attachedImageData = try container.decodeIfPresent(Data.self, forKey: .attachedImageData)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(text, forKey: .text)
        try container.encode(suggestedProducts, forKey: .suggestedProducts)
        try container.encode(sentAt, forKey: .sentAt)
        try container.encodeIfPresent(attachedImageData, forKey: .attachedImageData)
    }
}

struct AIStylistConversationSummary: Identifiable, Hashable, Codable {
    let id: String
    let createdAt: Date
    var title: String
    var updatedAt: Date
    var lastMessagePreview: String
    var messageCount: Int
}

struct AIStylistConversation: Identifiable, Hashable, Codable {
    let id: String
    let createdAt: Date
    var title: String
    var updatedAt: Date
    var messages: [AIStylistMessage]

    var summary: AIStylistConversationSummary {
        AIStylistConversationSummary(
            id: id,
            createdAt: createdAt,
            title: title,
            updatedAt: updatedAt,
            lastMessagePreview: messages.last?.text.nonEmptyValue ?? "Photo shared",
            messageCount: messages.count
        )
    }
}

private extension String {
    var nonEmptyValue: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
