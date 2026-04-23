import Foundation

@MainActor
final class AIStylistConversationFileStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func listConversations(for userKey: String) throws -> [AIStylistConversationSummary] {
        try migrateLegacyConversationIfNeeded(for: userKey)
        return try loadIndex(for: userKey)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func loadConversation(id: String, for userKey: String) throws -> AIStylistConversation? {
        try migrateLegacyConversationIfNeeded(for: userKey)
        let fileURL = try conversationFileURL(for: id, userKey: userKey)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(AIStylistConversation.self, from: data)
    }

    func saveConversation(_ conversation: AIStylistConversation, for userKey: String) throws {
        try migrateLegacyConversationIfNeeded(for: userKey)
        try persistConversation(conversation, for: userKey)
    }

    private func persistConversation(_ conversation: AIStylistConversation, for userKey: String) throws {
        let summaries = try upsertConversation(conversation, for: userKey)
        try saveIndex(summaries, for: userKey)
    }

    func deleteConversation(id: String, for userKey: String) throws {
        try migrateLegacyConversationIfNeeded(for: userKey)

        let fileURL = try conversationFileURL(for: id, userKey: userKey)
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }

        let summaries = try loadIndex(for: userKey).filter { $0.id != id }
        try saveIndex(summaries, for: userKey)
    }

    func searchConversations(matching query: String, for userKey: String) throws -> [AIStylistConversationSummary] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try listConversations(for: userKey)
        }

        let needle = trimmedQuery.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let summaries = try listConversations(for: userKey)

        return try summaries.filter { summary in
            if summary.title.localizedCaseInsensitiveContains(needle) ||
                summary.lastMessagePreview.localizedCaseInsensitiveContains(needle) {
                return true
            }

            guard let conversation = try loadConversation(id: summary.id, for: userKey) else {
                return false
            }

            return conversation.messages.contains { message in
                message.text.localizedCaseInsensitiveContains(needle)
            }
        }
    }

    private func loadIndex(for userKey: String) throws -> [AIStylistConversationSummary] {
        let fileURL = try indexFileURL(for: userKey)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([AIStylistConversationSummary].self, from: data)
    }

    private func saveIndex(_ summaries: [AIStylistConversationSummary], for userKey: String) throws {
        let fileURL = try indexFileURL(for: userKey)
        let data = try encoder.encode(summaries.sorted { $0.updatedAt > $1.updatedAt })
        try data.write(to: fileURL, options: .atomic)
    }

    private func migrateLegacyConversationIfNeeded(for userKey: String) throws {
        let legacyURL = try legacyConversationFileURL(for: userKey)
        let indexURL = try indexFileURL(for: userKey)

        guard fileManager.fileExists(atPath: legacyURL.path),
              !fileManager.fileExists(atPath: indexURL.path) else {
            return
        }

        let data = try Data(contentsOf: legacyURL)
        let legacyMessages = try decoder.decode([AIStylistMessage].self, from: data)
        guard !legacyMessages.isEmpty else {
            try? fileManager.removeItem(at: legacyURL)
            return
        }

        let conversation = AIStylistConversation(
            id: UUID().uuidString,
            createdAt: legacyMessages.first?.sentAt ?? .now,
            title: makeConversationTitle(from: legacyMessages),
            updatedAt: legacyMessages.last?.sentAt ?? .now,
            messages: legacyMessages
        )

        try persistConversation(conversation, for: userKey)
        try? fileManager.removeItem(at: legacyURL)
    }

    private func upsertConversation(_ conversation: AIStylistConversation, for userKey: String) throws -> [AIStylistConversationSummary] {
        let fileURL = try conversationFileURL(for: conversation.id, userKey: userKey)
        let data = try encoder.encode(conversation)
        try data.write(to: fileURL, options: .atomic)

        var summaries = try loadIndex(for: userKey)
        if let existingIndex = summaries.firstIndex(where: { $0.id == conversation.id }) {
            summaries[existingIndex] = conversation.summary
        } else {
            summaries.append(conversation.summary)
        }
        return summaries
    }

    private func makeConversationTitle(from messages: [AIStylistMessage]) -> String {
        if let firstUserMessage = messages.first(where: { $0.role == .user })?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !firstUserMessage.isEmpty {
            return String(firstUserMessage.prefix(36))
        }

        if messages.contains(where: { $0.attachedImage != nil }) {
            return "Photo Outfit Match"
        }

        return "Saved Stylist Chat"
    }

    private func indexFileURL(for userKey: String) throws -> URL {
        try userDirectoryURL(for: userKey).appendingPathComponent("index.json", isDirectory: false)
    }

    private func conversationFileURL(for id: String, userKey: String) throws -> URL {
        let filename = sanitizedFilename(for: id) + ".json"
        return try userDirectoryURL(for: userKey)
            .appendingPathComponent(filename, isDirectory: false)
    }

    private func legacyConversationFileURL(for userKey: String) throws -> URL {
        let rootDirectory = try rootDirectoryURL()
        let filename = sanitizedFilename(for: userKey) + ".json"
        return rootDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private func userDirectoryURL(for userKey: String) throws -> URL {
        let directoryURL = try rootDirectoryURL()
            .appendingPathComponent(sanitizedFilename(for: userKey), isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func rootDirectoryURL() throws -> URL {
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directoryURL = applicationSupportURL
            .appendingPathComponent("UniMarket-Swift", isDirectory: true)
            .appendingPathComponent("AIStylistConversations", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL
    }

    private func sanitizedFilename(for key: String) -> String {
        let allowedScalars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = key.unicodeScalars.map { allowedScalars.contains($0) ? Character($0) : "_" }
        let filename = String(sanitized)
        return filename.isEmpty ? "guest" : filename
    }
}
