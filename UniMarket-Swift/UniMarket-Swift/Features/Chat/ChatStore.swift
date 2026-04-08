import Foundation
import SwiftUI
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Models

struct ChatMessage: Identifiable, Hashable {
    let id: String
    let senderId: String
    let text: String
    let imageURLs: [String]
    let type: MessageType
    let sentAt: Date
    var readAt: Date?
    let replyTo: ReplySnapshot?
    let listingSnapshot: ListingSnapshot?

    var isFromCurrentUser: Bool {
        senderId == Auth.auth().currentUser?.uid
    }

    enum MessageType: String {
        case text, image, listing
    }

    struct ReplySnapshot: Hashable {
        let messageId: String
        let senderId: String
        let textPreview: String
    }

    struct ListingSnapshot: Hashable {
        let listingId: String
        let title: String
        let price: Int
        let imagePath: String
    }
}

struct ChatConversation: Identifiable, Hashable {
    let id: String                  // Firestore document ID
    let participants: [String]      // array of UIDs
    let initiatedBy: String         // UID of the user who started the conversation (the buyer)
    var otherParticipantName: String
    var otherParticipantAvatar: String?
    var lastMessageText: String
    var lastMessageAt: Date?
    var unreadCount: Int            // computed locally from unread messages
    var listingSnapshot: ChatMessage.ListingSnapshot?

    /// True when the current user is the one who initiated this conversation (i.e. the buyer).
    var isInitiatedByCurrentUser: Bool {
        initiatedBy == Auth.auth().currentUser?.uid
    }
}

// MARK: - ChatStore

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var messagesByConversation: [String: [ChatMessage]] = [:]
    @Published var isLoading = false

    private let db = Firestore.firestore()
    private var conversationListener: ListenerRegistration?
    private var messageListeners: [String: ListenerRegistration] = [:]

    var totalUnreadCount: Int {
        conversations.reduce(0) { $0 + $1.unreadCount }
    }

    // MARK: - Start observing inbox

    func startObservingConversations() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true

        conversationListener = db.collection("conversations")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let snapshot else {
                    print("DEBUG ChatStore: conversation listener error \(error?.localizedDescription ?? "")")
                    Task { @MainActor in self?.isLoading = false }
                    return
                }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    var updated: [ChatConversation] = []
                    for doc in snapshot.documents {
                        if let conv = await self.parseConversation(doc: doc, currentUID: uid) {
                            updated.append(conv)
                        }
                    }
                    self.conversations = updated.sorted {
                        ($0.lastMessageAt ?? .distantPast) > ($1.lastMessageAt ?? .distantPast)
                    }
                    self.isLoading = false
                }
            }
    }

    func stopObservingConversations() {
        conversationListener?.remove()
        conversationListener = nil
        messageListeners.values.forEach { $0.remove() }
        messageListeners.removeAll()
    }

    // MARK: - Parse conversation doc (fetches other user's display name)

    private func parseConversation(doc: QueryDocumentSnapshot, currentUID: String) async -> ChatConversation? {
        let data = doc.data()
        guard let participants = data["participants"] as? [String] else { return nil }

        let otherUID = participants.first(where: { $0 != currentUID }) ?? ""
        var otherName = "Unknown"
        var otherAvatar: String? = nil

        // fetch display name from users collection
        if !otherUID.isEmpty,
           let userDoc = try? await db.collection("users").document(otherUID).getDocument(),
           let userData = userDoc.data() {
            otherName = userData["displayName"] as? String ?? "Unknown"
            otherAvatar = userData["profilePic"] as? String
        }

        // unread count: messages where senderId != me and readAt is missing
        let unread = (messagesByConversation[doc.documentID] ?? [])
            .filter { !$0.isFromCurrentUser && $0.readAt == nil }
            .count

        var listingSnap: ChatMessage.ListingSnapshot? = nil
        if let ls = data["listingSnapshot"] as? [String: Any] {
            listingSnap = ChatMessage.ListingSnapshot(
                listingId: ls["listingId"] as? String ?? "",
                title: ls["title"] as? String ?? "",
                price: ls["price"] as? Int ?? 0,
                imagePath: ls["imagePath"] as? String ?? ""
            )
        }

        let lastMessageText = data["lastMessageText"] as? String ?? "No messages yet"
        let lastMessageAt = (data["lastMessageAt"] as? Timestamp)?.dateValue()

        // Fall back to first participant for older conversations that don't have initiatedBy
        let initiatedBy = data["initiatedBy"] as? String ?? participants.first ?? ""

        return ChatConversation(
            id: doc.documentID,
            participants: participants,
            initiatedBy: initiatedBy,
            otherParticipantName: otherName,
            otherParticipantAvatar: otherAvatar,
            lastMessageText: lastMessageText,
            lastMessageAt: lastMessageAt,
            unreadCount: unread,
            listingSnapshot: listingSnap
        )
    }

    // MARK: - Observe messages in a thread

    func startObservingMessages(for conversationID: String) {
        guard messageListeners[conversationID] == nil else { return }

        let listener = db.collection("conversations")
            .document(conversationID)
            .collection("messages")
            .order(by: "sentAt")
            .addSnapshotListener { [weak self] snapshot, error in
                guard let snapshot else {
                    print("DEBUG ChatStore: message listener error \(error?.localizedDescription ?? "")")
                    return
                }

                // Dispatch property mutations through MainActor to ensure
                // @Published changes reliably trigger SwiftUI view updates.
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let messages = snapshot.documents.compactMap { self.parseMessage(doc: $0) }
                    self.messagesByConversation[conversationID] = messages

                    // update unreadCount on the conversation object
                    if let idx = self.conversations.firstIndex(where: { $0.id == conversationID }) {
                        let unread = messages.filter { !$0.isFromCurrentUser && $0.readAt == nil }.count
                        self.conversations[idx].unreadCount = unread
                    }
                }
            }

        messageListeners[conversationID] = listener
    }

    func stopObservingMessages(for conversationID: String) {
        messageListeners[conversationID]?.remove()
        messageListeners.removeValue(forKey: conversationID)
    }

    // MARK: - Parse a message document

    private func parseMessage(doc: QueryDocumentSnapshot) -> ChatMessage? {
        let data = doc.data()
        guard let senderId = data["senderId"] as? String else { return nil }

        // Use .estimate so locally-written messages (with pending server timestamps)
        // resolve to an estimated date instead of nil — this lets sent messages render immediately.
        let sentAt = (doc.get("sentAt", serverTimestampBehavior: .estimate) as? Timestamp)?.dateValue() ?? Date()

        let text = data["text"] as? String ?? ""
        let imageURLs = data["imageURLs"] as? [String] ?? []
        let typeRaw = data["type"] as? String ?? "text"
        let type = ChatMessage.MessageType(rawValue: typeRaw) ?? .text
        let readAt = (data["readAt"] as? Timestamp)?.dateValue()

        var replyTo: ChatMessage.ReplySnapshot? = nil
        if let r = data["replyTo"] as? [String: Any] {
            replyTo = ChatMessage.ReplySnapshot(
                messageId: r["messageId"] as? String ?? "",
                senderId: r["senderId"] as? String ?? "",
                textPreview: r["textPreview"] as? String ?? ""
            )
        }

        var listingSnap: ChatMessage.ListingSnapshot? = nil
        if let ls = data["listingSnapshot"] as? [String: Any] {
            listingSnap = ChatMessage.ListingSnapshot(
                listingId: ls["listingId"] as? String ?? "",
                title: ls["title"] as? String ?? "",
                price: ls["price"] as? Int ?? 0,
                imagePath: ls["imagePath"] as? String ?? ""
            )
        }

        return ChatMessage(
            id: doc.documentID,
            senderId: senderId,
            text: text,
            imageURLs: imageURLs,
            type: type,
            sentAt: sentAt,
            readAt: readAt,
            replyTo: replyTo,
            listingSnapshot: listingSnap
        )
    }

    // MARK: - Start or get a conversation

    /// Creates a conversation document if none exists between currentUser and sellerID for a given listing.
    /// Returns the conversation ID.
    func startOrGetConversation(
        sellerID: String,
        listing: ChatMessage.ListingSnapshot
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChatError.notAuthenticated }
        guard uid != sellerID else { throw ChatError.cannotMessageSelf }

        // check if conversation already exists
        let existing = conversations.first(where: {
            $0.participants.contains(sellerID) && $0.listingSnapshot?.listingId == listing.listingId
        })
        if let existing { return existing.id }

        // create new conversation document
        let ref = db.collection("conversations").document()
        let listingData: [String: Any] = [
            "listingId": listing.listingId,
            "title": listing.title,
            "price": listing.price,
            "imagePath": listing.imagePath
        ]
        let data: [String: Any] = [
            "participants": [uid, sellerID],
            "initiatedBy": uid,
            "lastMessageText": "",
            "lastMessageAt": FieldValue.serverTimestamp(),
            "listingSnapshot": listingData
        ]
        try await ref.setData(data)
        return ref.documentID
    }

    // MARK: - Send a text message

    func sendMessage(
        text: String,
        in conversationID: String,
        replyTo: ChatMessage.ReplySnapshot? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChatError.notAuthenticated }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let msgRef = db.collection("conversations").document(conversationID)
            .collection("messages").document()

        // Optimistic local update — message appears in the UI immediately.
        let optimistic = ChatMessage(
            id: msgRef.documentID,
            senderId: uid,
            text: trimmed,
            imageURLs: [],
            type: .text,
            sentAt: Date(),
            readAt: nil,
            replyTo: replyTo,
            listingSnapshot: nil
        )
        var current = messagesByConversation[conversationID] ?? []
        current.append(optimistic)
        messagesByConversation[conversationID] = current

        var msgData: [String: Any] = [
            "senderId": uid,
            "text": trimmed,
            "imageURLs": [String](),
            "type": "text",
            "sentAt": FieldValue.serverTimestamp(),
            "readAt": NSNull()
        ]

        if let reply = replyTo {
            msgData["replyTo"] = [
                "messageId": reply.messageId,
                "senderId": reply.senderId,
                "textPreview": reply.textPreview
            ]
        }

        // write message, then update conversation summary
        try await msgRef.setData(msgData)
        try await db.collection("conversations").document(conversationID).updateData([
            "lastMessageText": trimmed,
            "lastMessageAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Send an image message

    func sendImageMessage(
        images: [UIImage],
        in conversationID: String
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw ChatError.notAuthenticated }
        guard !images.isEmpty else { return }

        // reserve message doc ID first so we can use it in the storage path
        let msgRef = db.collection("conversations").document(conversationID)
            .collection("messages").document()

        // upload all images concurrently
        var uploadedURLs: [String] = []
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, image) in images.enumerated() {
                group.addTask {
                    let url = try await ImageUploadService.uploadMessageImage(image, messageId: msgRef.documentID, index: index)
                    return (index, url)
                }
            }
            var results: [(Int, String)] = []
            for try await result in group {
                results.append(result)
            }
            uploadedURLs = results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }

        // Optimistic local update — image message appears immediately after upload.
        let optimistic = ChatMessage(
            id: msgRef.documentID,
            senderId: uid,
            text: "",
            imageURLs: uploadedURLs,
            type: .image,
            sentAt: Date(),
            readAt: nil,
            replyTo: nil,
            listingSnapshot: nil
        )
        var current = messagesByConversation[conversationID] ?? []
        current.append(optimistic)
        messagesByConversation[conversationID] = current

        let msgData: [String: Any] = [
            "senderId": uid,
            "text": "",
            "imageURLs": uploadedURLs,
            "type": "image",
            "sentAt": FieldValue.serverTimestamp(),
            "readAt": NSNull()
        ]

        try await msgRef.setData(msgData)
        let label = images.count == 1 ? "📷 Image" : "📷 \(images.count) Images"
        try await db.collection("conversations").document(conversationID).updateData([
            "lastMessageText": label,
            "lastMessageAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Mark conversation as read

    func markConversationAsRead(_ conversationID: String) {
        guard Auth.auth().currentUser != nil else { return }
        let messages = messagesByConversation[conversationID] ?? []
        let unreadMessages = messages.filter { !$0.isFromCurrentUser && $0.readAt == nil }
        guard !unreadMessages.isEmpty else { return }

        let batch = db.batch()
        for message in unreadMessages {
            let ref = db.collection("conversations").document(conversationID)
                .collection("messages").document(message.id)
            batch.updateData(["readAt": FieldValue.serverTimestamp()], forDocument: ref)
        }

        Task {
            do {
                try await batch.commit()
            } catch {
                print("DEBUG ChatStore: failed to mark messages as read \(error.localizedDescription)")
            }
        }

        // optimistic local update
        if let idx = conversations.firstIndex(where: { $0.id == conversationID }) {
            conversations[idx].unreadCount = 0
        }
    }
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case notAuthenticated
    case cannotMessageSelf

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be logged in to send messages."
        case .cannotMessageSelf: return "You can't message yourself."
        }
    }
}
