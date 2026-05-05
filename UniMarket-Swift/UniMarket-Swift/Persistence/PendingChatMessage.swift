import Foundation

// Outgoing chat message persisted while offline. Text-only — image messages
// aren't queued (Storage has no offline layer). See EvCon.md §2.
struct PendingChatMessage: Codable, Equatable, Identifiable {
    var id: String { pendingID }

    let pendingID: String
    let userID: String
    let conversationID: String
    /// Pre-reserved Firestore document ID; shared with the optimistic
    /// ChatMessage so the snapshot listener replaces the bubble in place.
    let messageID: String
    var text: String
    var replyToMessageID: String?
    var replyToSenderID: String?
    var replyToTextPreview: String?
    let queuedAt: Date
    var lastTriedAt: Date?
    var retryCount: Int
    var lastError: String?
}
