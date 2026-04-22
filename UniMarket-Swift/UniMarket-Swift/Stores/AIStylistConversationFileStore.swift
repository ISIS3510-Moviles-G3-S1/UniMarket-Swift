import Foundation

actor AIStylistConversationFileStore {
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func loadConversation(for key: String) throws -> [AIStylistMessage] {
        let fileURL = try conversationFileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([AIStylistMessage].self, from: data)
    }

    func saveConversation(_ messages: [AIStylistMessage], for key: String) throws {
        let fileURL = try conversationFileURL(for: key)
        let data = try encoder.encode(messages)
        try data.write(to: fileURL, options: .atomic)
    }

    func deleteConversation(for key: String) throws {
        let fileURL = try conversationFileURL(for: key)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        try fileManager.removeItem(at: fileURL)
    }

    private func conversationFileURL(for key: String) throws -> URL {
        let directoryURL = try conversationsDirectoryURL()
        let filename = sanitizedFilename(for: key) + ".json"
        return directoryURL.appendingPathComponent(filename, isDirectory: false)
    }

    private func conversationsDirectoryURL() throws -> URL {
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
