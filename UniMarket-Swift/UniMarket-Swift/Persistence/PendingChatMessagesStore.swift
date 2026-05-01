import Foundation

// File-backed queue of outgoing chat messages waiting for connectivity.
// All operations are synchronous; callers should invoke from a background Task.
//
// Layout:
//  ~/Library/Application Support/UniMarket-Swift/PendingMessages/{userID}/
//      ├─ index.json           ← [PendingChatMessage] sorted by queuedAt
//      └─ {pendingID}.json     ← single record (resilience copy)
final class PendingChatMessagesStore {
    static let shared = PendingChatMessagesStore()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let indexFilename = "index.json"

    private init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Public API

    @discardableResult
    func enqueue(
        userID: String,
        conversationID: String,
        messageID: String,
        text: String,
        replyTo: ChatMessage.ReplySnapshot?
    ) throws -> PendingChatMessage {
        let pending = PendingChatMessage(
            pendingID: UUID().uuidString,
            userID: userID,
            conversationID: conversationID,
            messageID: messageID,
            text: text,
            replyToMessageID: replyTo?.messageId,
            replyToSenderID: replyTo?.senderId,
            replyToTextPreview: replyTo?.textPreview,
            queuedAt: Date(),
            lastTriedAt: nil,
            retryCount: 0,
            lastError: nil
        )

        let dir = try userDirectory(for: userID)
        try writeRecord(pending, in: dir)

        var index = (try? readIndex(in: dir)) ?? []
        index.append(pending)
        try writeIndex(index, in: dir)
        return pending
    }

    func allPending(for userID: String) throws -> [PendingChatMessage] {
        let dir = try userDirectory(for: userID)
        return (try? readIndex(in: dir)) ?? []
    }

    func pending(forConversation conversationID: String, userID: String) -> [PendingChatMessage] {
        guard let dir = try? userDirectory(for: userID) else { return [] }
        let all = (try? readIndex(in: dir)) ?? []
        return all.filter { $0.conversationID == conversationID }
    }

    func count(for userID: String) -> Int {
        guard let dir = try? userDirectory(for: userID) else { return 0 }
        return ((try? readIndex(in: dir)) ?? []).count
    }

    func remove(pendingID: String, userID: String) throws {
        let dir = try userDirectory(for: userID)
        let recordURL = dir.appendingPathComponent("\(pendingID).json")
        try? fileManager.removeItem(at: recordURL)

        var index = (try? readIndex(in: dir)) ?? []
        index.removeAll { $0.pendingID == pendingID }
        try writeIndex(index, in: dir)
    }

    func clearUserQueue(for userID: String) throws {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let dir = support
            .appendingPathComponent("UniMarket-Swift", isDirectory: true)
            .appendingPathComponent("PendingMessages", isDirectory: true)
            .appendingPathComponent(sanitizedFilename(userID), isDirectory: true)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    func bumpRetry(pendingID: String, userID: String, error: Error) throws {
        let dir = try userDirectory(for: userID)
        var index = (try? readIndex(in: dir)) ?? []
        guard let idx = index.firstIndex(where: { $0.pendingID == pendingID }) else { return }
        index[idx].retryCount += 1
        index[idx].lastTriedAt = Date()
        index[idx].lastError = error.localizedDescription
        try writeRecord(index[idx], in: dir)
        try writeIndex(index, in: dir)
    }

    // MARK: - Filesystem helpers

    private func userDirectory(for userID: String) throws -> URL {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support
            .appendingPathComponent("UniMarket-Swift", isDirectory: true)
            .appendingPathComponent("PendingMessages", isDirectory: true)
            .appendingPathComponent(sanitizedFilename(userID), isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func readIndex(in directory: URL) throws -> [PendingChatMessage] {
        let url = directory.appendingPathComponent(indexFilename)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([PendingChatMessage].self, from: data)
    }

    private func writeIndex(_ items: [PendingChatMessage], in directory: URL) throws {
        let url = directory.appendingPathComponent(indexFilename)
        let data = try encoder.encode(items.sorted { $0.queuedAt < $1.queuedAt })
        try data.write(to: url, options: .atomic)
    }

    private func writeRecord(_ record: PendingChatMessage, in directory: URL) throws {
        let url = directory.appendingPathComponent("\(record.pendingID).json")
        let data = try encoder.encode(record)
        try data.write(to: url, options: .atomic)
    }

    private func sanitizedFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
