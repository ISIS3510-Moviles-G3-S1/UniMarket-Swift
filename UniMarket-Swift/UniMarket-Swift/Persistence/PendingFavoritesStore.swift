import Foundation

// File-backed queue of favorite-toggle operations that haven't been written to
// the user's Firestore document yet. All operations are synchronous; callers
// should invoke from a background Task.
//
// Layout:
//  ~/Library/Application Support/UniMarket-Swift/PendingFavorites/{userID}/
//      └─ index.json   ← [PendingFavoriteOp] (one per productID, last-write-wins)
//
// Why no per-record sidecar JSON like PendingListingsStore? Each op is a tiny
// fixed-size struct — losing the index is recoverable by simply discarding the
// queue. Image-bearing queues (listings, message images) need sidecars because
// the JSON is large and the on-disk image bytes are irreplaceable.
final class PendingFavoritesStore {
    static let shared = PendingFavoritesStore()

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

    /// Records a save/unsave for a product. If a record for the same product
    /// already exists, the policy is:
    ///   - existing.kind == new.kind: refresh queuedAt (idempotent)
    ///   - opposite kinds: remove the record entirely (the two cancel out)
    /// This keeps the queue sized to "products with a net change," not "raw
    /// taps," which matters for users who toggle a heart repeatedly while
    /// offline.
    func enqueue(productID: String, userID: String, kind: PendingFavoriteOp.Kind) throws {
        let dir = try userDirectory(for: userID)
        var index = (try? readIndex(in: dir)) ?? []

        if let existingIdx = index.firstIndex(where: { $0.productID == productID }) {
            if index[existingIdx].kind == kind {
                index[existingIdx].queuedAt = Date()
            } else {
                index.remove(at: existingIdx)
            }
        } else {
            index.append(PendingFavoriteOp(
                productID: productID,
                userID: userID,
                kind: kind,
                queuedAt: Date(),
                lastTriedAt: nil,
                retryCount: 0,
                lastError: nil
            ))
        }
        try writeIndex(index, in: dir)
    }

    func allPending(for userID: String) throws -> [PendingFavoriteOp] {
        let dir = try userDirectory(for: userID)
        return (try? readIndex(in: dir)) ?? []
    }

    func count(for userID: String) -> Int {
        guard let dir = try? userDirectory(for: userID) else { return 0 }
        return ((try? readIndex(in: dir)) ?? []).count
    }

    func remove(productID: String, userID: String) throws {
        let dir = try userDirectory(for: userID)
        var index = (try? readIndex(in: dir)) ?? []
        index.removeAll { $0.productID == productID }
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
            .appendingPathComponent("PendingFavorites", isDirectory: true)
            .appendingPathComponent(sanitizedFilename(userID), isDirectory: true)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    func bumpRetry(productID: String, userID: String, error: Error) throws {
        let dir = try userDirectory(for: userID)
        var index = (try? readIndex(in: dir)) ?? []
        guard let idx = index.firstIndex(where: { $0.productID == productID }) else { return }
        index[idx].retryCount += 1
        index[idx].lastTriedAt = Date()
        index[idx].lastError = error.localizedDescription
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
            .appendingPathComponent("PendingFavorites", isDirectory: true)
            .appendingPathComponent(sanitizedFilename(userID), isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func readIndex(in directory: URL) throws -> [PendingFavoriteOp] {
        let url = directory.appendingPathComponent(indexFilename)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([PendingFavoriteOp].self, from: data)
    }

    private func writeIndex(_ items: [PendingFavoriteOp], in directory: URL) throws {
        let url = directory.appendingPathComponent(indexFilename)
        let data = try encoder.encode(items.sorted { $0.queuedAt < $1.queuedAt })
        try data.write(to: url, options: .atomic)
    }

    private func sanitizedFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
