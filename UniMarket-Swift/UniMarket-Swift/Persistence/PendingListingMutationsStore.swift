import Foundation

// File-backed queue of pending update/delete mutations for the seller's own
// listings. All operations are synchronous; callers should invoke from a
// background Task.
//
// Layout:
//  ~/Library/Application Support/UniMarket-Swift/PendingMutations/{userID}/
//      └─ index.json   ← [PendingListingMutation], coalesced per productID
//
// Coalescing rules (applied at enqueue time):
//   existing       new          result
//   ─────────────  ──────────   ────────────────────────────────────────
//   none           any          append
//   update         update       overwrite snapshot, refresh queuedAt
//   update         delete       overwrite as delete (the update is moot)
//   delete         update       keep the delete (a later update is invalid;
//                                the listing is gone)
//   delete         delete       refresh queuedAt
final class PendingListingMutationsStore {
    static let shared = PendingListingMutationsStore()

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

    func enqueueUpdate(product: Product, userID: String) throws {
        let snapshot = PendingListingMutation.Snapshot(
            title: product.title,
            price: product.price,
            statusRaw: product.status.rawValue,
            soldAt: product.soldAt,
            imageURLs: product.imageURLs
        )
        try upsert(productID: product.id, userID: userID, kind: .update, snapshot: snapshot)
    }

    func enqueueDelete(product: Product, userID: String) throws {
        let snapshot = PendingListingMutation.Snapshot(
            title: product.title,
            price: product.price,
            statusRaw: product.status.rawValue,
            soldAt: product.soldAt,
            imageURLs: product.imageURLs
        )
        try upsert(productID: product.id, userID: userID, kind: .delete, snapshot: snapshot)
    }

    private func upsert(
        productID: String,
        userID: String,
        kind: PendingListingMutation.Kind,
        snapshot: PendingListingMutation.Snapshot
    ) throws {
        let dir = try userDirectory(for: userID)
        var index = (try? readIndex(in: dir)) ?? []

        if let existingIdx = index.firstIndex(where: { $0.productID == productID }) {
            let existing = index[existingIdx]
            switch (existing.kind, kind) {
            case (.delete, .update):
                // Keep the delete — a later update against a doc we're about
                // to delete is meaningless. Refresh the timestamp so we drain
                // sooner rather than later.
                index[existingIdx].queuedAt = Date()
            default:
                index[existingIdx].kind = kind
                index[existingIdx].snapshot = snapshot
                index[existingIdx].queuedAt = Date()
            }
        } else {
            index.append(PendingListingMutation(
                pendingID: UUID().uuidString,
                userID: userID,
                productID: productID,
                kind: kind,
                snapshot: snapshot,
                queuedAt: Date(),
                lastTriedAt: nil,
                retryCount: 0,
                lastError: nil
            ))
        }
        try writeIndex(index, in: dir)
    }

    func allPending(for userID: String) throws -> [PendingListingMutation] {
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
            .appendingPathComponent("PendingMutations", isDirectory: true)
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
            .appendingPathComponent("PendingMutations", isDirectory: true)
            .appendingPathComponent(sanitizedFilename(userID), isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func readIndex(in directory: URL) throws -> [PendingListingMutation] {
        let url = directory.appendingPathComponent(indexFilename)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([PendingListingMutation].self, from: data)
    }

    private func writeIndex(_ items: [PendingListingMutation], in directory: URL) throws {
        let url = directory.appendingPathComponent(indexFilename)
        let data = try encoder.encode(items.sorted { $0.queuedAt < $1.queuedAt })
        try data.write(to: url, options: .atomic)
    }

    private func sanitizedFilename(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
