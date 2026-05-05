import Foundation
import SwiftData

// Wraps the SwiftData ModelContainer for the chat domain. All access happens
// through the main-actor context because ChatStore is itself main-isolated
// and the upsert volume is small (one row per Firestore message). For higher
// write volume we would switch to a background ModelContext per call.
//
// Storage location: SwiftData's default container (Application Support/default.store).
// On a clean install this file does not exist; the first ModelContainer init
// creates it.
@MainActor
final class ChatLocalStore {
    static let shared = ChatLocalStore()

    private let container: ModelContainer?

    private var context: ModelContext? { container?.mainContext }

    private init() {
        do {
            self.container = try ModelContainer(
                for: ChatConversationEntity.self,
                ChatMessageEntity.self
            )
        } catch {
            // If SwiftData fails to open the store we degrade silently — chats
            // still work via Firestore, just without offline cache.
            self.container = nil
        }
    }

    // MARK: - Reads

    func loadAllConversations() -> [ChatConversation] {
        guard let context else { return [] }
        let descriptor = FetchDescriptor<ChatConversationEntity>(
            sortBy: [SortDescriptor(\.lastMessageAt, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map(Self.makeRuntime(from:))
    }

    func loadMessages(for conversationID: String) -> [ChatMessage] {
        guard let context else { return [] }
        var descriptor = FetchDescriptor<ChatMessageEntity>(
            predicate: #Predicate { msg in
                msg.conversation?.id == conversationID
            },
            sortBy: [SortDescriptor(\.sentAt, order: .forward)]
        )
        descriptor.fetchLimit = 500
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.map(Self.makeRuntimeMessage(from:))
    }

    // MARK: - Writes

    func upsertConversation(_ conv: ChatConversation) {
        guard let context else { return }
        let id = conv.id
        let descriptor = FetchDescriptor<ChatConversationEntity>(
            predicate: #Predicate { $0.id == id }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.participants = conv.participants
            existing.initiatedBy = conv.initiatedBy
            existing.otherParticipantName = conv.otherParticipantName
            existing.otherParticipantAvatar = conv.otherParticipantAvatar
            existing.lastMessageText = conv.lastMessageText
            existing.lastMessageAt = conv.lastMessageAt
            existing.listingID = conv.listingSnapshot?.listingId
            existing.listingTitle = conv.listingSnapshot?.title
            existing.listingPrice = conv.listingSnapshot?.price
            existing.listingImagePath = conv.listingSnapshot?.imagePath
            existing.lastSyncedAt = .now
        } else {
            let entity = ChatConversationEntity(
                id: conv.id,
                participants: conv.participants,
                initiatedBy: conv.initiatedBy,
                otherParticipantName: conv.otherParticipantName,
                otherParticipantAvatar: conv.otherParticipantAvatar,
                lastMessageText: conv.lastMessageText,
                lastMessageAt: conv.lastMessageAt,
                listingID: conv.listingSnapshot?.listingId,
                listingTitle: conv.listingSnapshot?.title,
                listingPrice: conv.listingSnapshot?.price,
                listingImagePath: conv.listingSnapshot?.imagePath
            )
            context.insert(entity)
        }
        try? context.save()
    }

    func replaceMessages(_ messages: [ChatMessage], for conversationID: String) {
        guard let context else { return }
        let convDescriptor = FetchDescriptor<ChatConversationEntity>(
            predicate: #Predicate { $0.id == conversationID }
        )
        guard let conversation = try? context.fetch(convDescriptor).first else { return }

        // Index existing messages by id, then upsert. Messages no longer present
        // in the snapshot are deleted (Firestore is the source of truth).
        let existingByID = Dictionary(
            uniqueKeysWithValues: (conversation.messages).map { ($0.id, $0) }
        )
        let incomingIDs = Set(messages.map(\.id))

        for message in messages {
            if let existing = existingByID[message.id] {
                Self.apply(message, to: existing)
            } else {
                let entity = Self.makeEntity(from: message)
                entity.conversation = conversation
                context.insert(entity)
            }
        }
        for (id, entity) in existingByID where !incomingIDs.contains(id) {
            context.delete(entity)
        }
        try? context.save()
    }

    func removeConversations(notIn ids: Set<String>) {
        guard let context else { return }
        let descriptor = FetchDescriptor<ChatConversationEntity>()
        guard let all = try? context.fetch(descriptor) else { return }
        for entity in all where !ids.contains(entity.id) {
            context.delete(entity)
        }
        try? context.save()
    }

    // MARK: - Mapping

    private static func makeRuntime(from entity: ChatConversationEntity) -> ChatConversation {
        var listing: ChatMessage.ListingSnapshot? = nil
        if let id = entity.listingID {
            listing = ChatMessage.ListingSnapshot(
                listingId: id,
                title: entity.listingTitle ?? "",
                price: entity.listingPrice ?? 0,
                imagePath: entity.listingImagePath ?? ""
            )
        }
        let unread = entity.messages.filter { msg in
            msg.readAt == nil && msg.senderId != entity.participants.first(where: { $0 != entity.initiatedBy })
        }.count
        return ChatConversation(
            id: entity.id,
            participants: entity.participants,
            initiatedBy: entity.initiatedBy,
            otherParticipantName: entity.otherParticipantName,
            otherParticipantAvatar: entity.otherParticipantAvatar,
            lastMessageText: entity.lastMessageText,
            lastMessageAt: entity.lastMessageAt,
            unreadCount: unread,
            listingSnapshot: listing
        )
    }

    private static func makeRuntimeMessage(from entity: ChatMessageEntity) -> ChatMessage {
        var reply: ChatMessage.ReplySnapshot? = nil
        if let mid = entity.replyToMessageId {
            reply = ChatMessage.ReplySnapshot(
                messageId: mid,
                senderId: entity.replyToSenderId ?? "",
                textPreview: entity.replyToTextPreview ?? ""
            )
        }
        var listing: ChatMessage.ListingSnapshot? = nil
        if let id = entity.listingSnapshotID {
            listing = ChatMessage.ListingSnapshot(
                listingId: id,
                title: entity.listingSnapshotTitle ?? "",
                price: entity.listingSnapshotPrice ?? 0,
                imagePath: entity.listingSnapshotImagePath ?? ""
            )
        }
        return ChatMessage(
            id: entity.id,
            senderId: entity.senderId,
            text: entity.text,
            imageURLs: entity.imageURLs,
            type: ChatMessage.MessageType(rawValue: entity.typeRaw) ?? .text,
            sentAt: entity.sentAt,
            readAt: entity.readAt,
            replyTo: reply,
            listingSnapshot: listing
        )
    }

    private static func makeEntity(from message: ChatMessage) -> ChatMessageEntity {
        ChatMessageEntity(
            id: message.id,
            senderId: message.senderId,
            text: message.text,
            imageURLs: message.imageURLs,
            typeRaw: message.type.rawValue,
            sentAt: message.sentAt,
            readAt: message.readAt,
            replyToMessageId: message.replyTo?.messageId,
            replyToSenderId: message.replyTo?.senderId,
            replyToTextPreview: message.replyTo?.textPreview,
            listingSnapshotID: message.listingSnapshot?.listingId,
            listingSnapshotTitle: message.listingSnapshot?.title,
            listingSnapshotPrice: message.listingSnapshot?.price,
            listingSnapshotImagePath: message.listingSnapshot?.imagePath
        )
    }

    private static func apply(_ message: ChatMessage, to entity: ChatMessageEntity) {
        entity.senderId = message.senderId
        entity.text = message.text
        entity.imageURLs = message.imageURLs
        entity.typeRaw = message.type.rawValue
        entity.sentAt = message.sentAt
        entity.readAt = message.readAt
        entity.replyToMessageId = message.replyTo?.messageId
        entity.replyToSenderId = message.replyTo?.senderId
        entity.replyToTextPreview = message.replyTo?.textPreview
        entity.listingSnapshotID = message.listingSnapshot?.listingId
        entity.listingSnapshotTitle = message.listingSnapshot?.title
        entity.listingSnapshotPrice = message.listingSnapshot?.price
        entity.listingSnapshotImagePath = message.listingSnapshot?.imagePath
    }
}
