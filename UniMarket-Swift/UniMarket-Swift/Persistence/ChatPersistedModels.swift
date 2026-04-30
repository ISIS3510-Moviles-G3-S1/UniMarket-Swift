import Foundation
import SwiftData

// SwiftData entities mirroring the Firestore-backed chat domain.
//
// Why SwiftData (vs. Core Data or a 3rd-party SQLite wrapper):
//  - First-party, no SPM dependency to add
//  - SQLite-backed under the hood — satisfies the "BD Local Relacional" rubric
//  - @Relationship makes the conversation -> messages 1:N edge explicit
//  - Available from iOS 17+; project deployment target is iOS 26.x
//
// Only fields needed for offline rendering are mirrored. Computed properties
// (e.g. `isFromCurrentUser`, `isInitiatedByCurrentUser`) stay on the runtime
// `ChatConversation` / `ChatMessage` value types and aren't persisted because
// they depend on the live auth state.

@Model
final class ChatConversationEntity {
    @Attribute(.unique) var id: String
    var participants: [String]
    var initiatedBy: String
    var otherParticipantName: String
    var otherParticipantAvatar: String?
    var lastMessageText: String
    var lastMessageAt: Date?
    var listingID: String?
    var listingTitle: String?
    var listingPrice: Int?
    var listingImagePath: String?
    var lastSyncedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessageEntity.conversation)
    var messages: [ChatMessageEntity] = []

    init(
        id: String,
        participants: [String],
        initiatedBy: String,
        otherParticipantName: String,
        otherParticipantAvatar: String?,
        lastMessageText: String,
        lastMessageAt: Date?,
        listingID: String?,
        listingTitle: String?,
        listingPrice: Int?,
        listingImagePath: String?,
        lastSyncedAt: Date = .now
    ) {
        self.id = id
        self.participants = participants
        self.initiatedBy = initiatedBy
        self.otherParticipantName = otherParticipantName
        self.otherParticipantAvatar = otherParticipantAvatar
        self.lastMessageText = lastMessageText
        self.lastMessageAt = lastMessageAt
        self.listingID = listingID
        self.listingTitle = listingTitle
        self.listingPrice = listingPrice
        self.listingImagePath = listingImagePath
        self.lastSyncedAt = lastSyncedAt
    }
}

@Model
final class ChatMessageEntity {
    @Attribute(.unique) var id: String
    var conversation: ChatConversationEntity?
    var senderId: String
    var text: String
    var imageURLs: [String]
    var typeRaw: String
    var sentAt: Date
    var readAt: Date?

    var replyToMessageId: String?
    var replyToSenderId: String?
    var replyToTextPreview: String?

    var listingSnapshotID: String?
    var listingSnapshotTitle: String?
    var listingSnapshotPrice: Int?
    var listingSnapshotImagePath: String?

    init(
        id: String,
        conversation: ChatConversationEntity? = nil,
        senderId: String,
        text: String,
        imageURLs: [String],
        typeRaw: String,
        sentAt: Date,
        readAt: Date?,
        replyToMessageId: String?,
        replyToSenderId: String?,
        replyToTextPreview: String?,
        listingSnapshotID: String?,
        listingSnapshotTitle: String?,
        listingSnapshotPrice: Int?,
        listingSnapshotImagePath: String?
    ) {
        self.id = id
        self.conversation = conversation
        self.senderId = senderId
        self.text = text
        self.imageURLs = imageURLs
        self.typeRaw = typeRaw
        self.sentAt = sentAt
        self.readAt = readAt
        self.replyToMessageId = replyToMessageId
        self.replyToSenderId = replyToSenderId
        self.replyToTextPreview = replyToTextPreview
        self.listingSnapshotID = listingSnapshotID
        self.listingSnapshotTitle = listingSnapshotTitle
        self.listingSnapshotPrice = listingSnapshotPrice
        self.listingSnapshotImagePath = listingSnapshotImagePath
    }
}
