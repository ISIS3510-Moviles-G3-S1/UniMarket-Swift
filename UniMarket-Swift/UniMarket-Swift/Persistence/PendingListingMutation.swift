import Foundation

// Seller-side update/delete on the seller's own listing, queued while
// offline. Coalesced per productID — see EvCon.md §4 for the merge rules.
struct PendingListingMutation: Codable, Equatable, Identifiable {
    var id: String { pendingID }

    enum Kind: String, Codable {
        case update
        case delete
    }

    /// Mutable fields needed to replay updateProduct/deleteProduct.
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
