import Foundation

// Persistent envelope for an outgoing chat message the user has tapped Send on
// but the network hasn't accepted yet. Stored on disk under
//   ~/Library/Application Support/UniMarket-Swift/PendingMessages/{userID}/
// as one JSON file per record plus an index.json with the ordered list.
//
// Image messages are deliberately *not* included in the outbox: they require a
// blocking Firebase Storage upload before the message document can reference
// the resulting URLs, and Storage has no offline persistence layer to lean on.
// Only text replies are queued offline.
struct PendingChatMessage: Codable, Equatable, Identifiable {
    var id: String { pendingID }

    let pendingID: String
    let userID: String
    let conversationID: String
    /// Pre-reserved Firestore document ID, also used as the optimistic message
    /// ID inside ChatStore so the local bubble and the eventual server-side
    /// message resolve to the same identity.
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
