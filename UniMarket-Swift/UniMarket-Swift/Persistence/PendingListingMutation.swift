import Foundation

// Persistent record of a seller-side mutation to one of their own listings
// (price/title/status edit, mark-as-sold toggle, or full delete) that
// happened while offline. Stored on disk under
//   ~/Library/Application Support/UniMarket-Swift/PendingMutations/{userID}/
// as one JSON file plus an index.json with the ordered list.
//
// Mutations are coalesced per-listing — only the most recent .update for a
// given listing is retained, since a sequence of edits is functionally
// equivalent to the last one. A .delete subsumes any earlier .update for the
// same listing.
struct PendingListingMutation: Codable, Equatable, Identifiable {
    var id: String { pendingID }

    enum Kind: String, Codable {
        case update
        case delete
    }

    /// Snapshot of the mutated fields. For .update we replay updateProduct
    /// with this snapshot; for .delete we just need productID + imageURLs so
    /// the syncer can clean up the Storage blobs.
    struct Snapshot: Codable, Equatable {
        var title: String
        var price: Int
        var statusRaw: String
        var soldAt: Date?
        var imageURLs: [String]
    }

    let pendingID: String
    let userID: String
    let productID: String
    var kind: Kind
    var snapshot: Snapshot
    var queuedAt: Date
    var lastTriedAt: Date?
    var retryCount: Int
    var lastError: String?
}
