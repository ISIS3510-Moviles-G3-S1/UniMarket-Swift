import Foundation

// Save/unsave op queued while offline. Coalesced per productID — see
// EvCon.md §3 for the merge rules.
struct PendingFavoriteOp: Codable, Equatable, Identifiable {
    var id: String { productID }

    enum Kind: String, Codable {
        case save
        case unsave
    }

    let productID: String
    let userID: String
    var kind: Kind
    var queuedAt: Date
    var lastTriedAt: Date?
    var retryCount: Int
    var lastError: String?
}
