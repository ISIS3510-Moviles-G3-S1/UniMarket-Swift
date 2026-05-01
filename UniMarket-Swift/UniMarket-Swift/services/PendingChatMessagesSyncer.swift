import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// Eventual-connectivity coordinator for the file-backed PendingChatMessagesStore.
// Mirrors the lifecycle of PendingListingsSyncer: subscribes to NetworkMonitor,
// drains on every offline → online transition, replays records by writing
// directly to Firestore (the messages subcollection of each conversation).
//
// Observability
// ─────────────
// `pendingCount` is @Published so banners/UI can react. `pendingByConversation`
// is published so ChatThreadView can render in-flight bubbles for the
// conversation it's showing without polling the disk.
@MainActor
final class PendingChatMessagesSyncer: ObservableObject {
    static let shared = PendingChatMessagesSyncer()

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isDraining: Bool = false
    /// Snapshot of queued messages keyed by conversation ID, refreshed after
    /// every enqueue / drain step. ChatThreadView observes this to render
    /// pending bubbles.
    @Published private(set) var pendingByConversation: [String: [PendingChatMessage]] = [:]

    private let db = Firestore.firestore()
    private var connectivityCancellable: AnyCancellable?
    private var sessionCancellable: AnyCancellable?

    private init() {}

    func bind(to monitor: NetworkMonitor) {
        connectivityCancellable = monitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                if connected {
                    Task { await self.drain() }
                }
            }
        sessionCancellable = SessionManager.shared.$user
            .map { $0?.uid }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshSnapshot() }
            }
        Task { await refreshSnapshot() }
    }

    func resumeIfNeeded() async {
        await refreshSnapshot()
        if NetworkMonitor.shared.isConnected {
            await drain()
        }
    }

    /// Reserve a Firestore message ID up-front and queue the text. The caller
    /// passes the same `messageID` into the optimistic ChatMessage so the
    /// listener-driven replacement and the queued record share an identity.
    func enqueue(
        userID: String,
        conversationID: String,
        messageID: String,
        text: String,
        replyTo: ChatMessage.ReplySnapshot?
    ) async {
        let work = Task.detached(priority: .utility) {
            try await PendingChatMessagesStore.shared.enqueue(
                userID: userID,
                conversationID: conversationID,
                messageID: messageID,
                text: text,
                replyTo: replyTo
            )
        }
        _ = try? await work.value
        await refreshSnapshot()
    }

    func drain() async {
        guard !isDraining else { return }
        guard let userID = Auth.auth().currentUser?.uid else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        isDraining = true
        defer {
            isDraining = false
            Task { await refreshSnapshot() }
        }

        let listTask = Task.detached(priority: .utility) {
            try await PendingChatMessagesStore.shared.allPending(for: userID)
        }
        let pending: [PendingChatMessage]
        do {
            pending = try await listTask.value
        } catch { return }

        for record in pending {
            do {
                try await write(record: record, userID: userID)
                let removeTask = Task.detached(priority: .utility) {
                    try await PendingChatMessagesStore.shared.remove(
                        pendingID: record.pendingID,
                        userID: userID
                    )
                }
                _ = try await removeTask.value
            } catch {
                let bumpTask = Task.detached(priority: .utility) {
                    try await PendingChatMessagesStore.shared.bumpRetry(
                        pendingID: record.pendingID,
                        userID: userID,
                        error: error
                    )
                }
                _ = try? await bumpTask.value
                // Stop on first failure — most failures are network-shaped and
                // will affect every remaining record. The next connectivity
                // flip retries from where we left off.
                break
            }
        }
    }

    // MARK: - Firestore write

    private func write(record: PendingChatMessage, userID: String) async throws {
        let convRef = db.collection("conversations").document(record.conversationID)
        let msgRef = convRef.collection("messages").document(record.messageID)

        var msgData: [String: Any] = [
            "senderId": userID,
            "text": record.text,
            "imageURLs": [String](),
            "type": "text",
            "sentAt": FieldValue.serverTimestamp(),
            "readAt": NSNull()
        ]
        if let mid = record.replyToMessageID {
            msgData["replyTo"] = [
                "messageId": mid,
                "senderId": record.replyToSenderID ?? "",
                "textPreview": record.replyToTextPreview ?? ""
            ]
        }

        try await msgRef.setData(msgData)
        try await convRef.updateData([
            "lastMessageText": record.text,
            "lastMessageAt": FieldValue.serverTimestamp()
        ])
    }

    // MARK: - Snapshot refresh

    private func refreshSnapshot() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            pendingCount = 0
            pendingByConversation = [:]
            return
        }
        let task = Task.detached(priority: .utility) {
            (try? await PendingChatMessagesStore.shared.allPending(for: userID)) ?? []
        }
        let all = await task.value
        pendingCount = all.count
        pendingByConversation = Dictionary(grouping: all, by: \.conversationID)
    }
}
