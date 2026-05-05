import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// Connectivity-driven coordinator for PendingChatMessagesStore.
// See EvCon.md §2 for the lifecycle and replay semantics.
@MainActor
final class PendingChatMessagesSyncer: ObservableObject {
    static let shared = PendingChatMessagesSyncer()

    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isDraining: Bool = false
    /// Queued messages grouped by conversation; ChatThreadView reads this to
    /// render pending bubbles after a cold launch.
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

    /// Caller passes the same `messageID` into the optimistic ChatMessage so
    /// the listener-driven replacement de-dupes by id.
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
                // Stop on first failure — next connectivity flip retries.
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
