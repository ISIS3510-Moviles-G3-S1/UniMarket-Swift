import Foundation

// Listing the user submitted but hasn't reached Firestore yet.
// See EvCon.md §1 for the on-disk layout and image-sidecar rationale.
struct PendingListing: Codable, Equatable, Identifiable {
    var id: String { pendingID }

    let pendingID: String
    let userID: String
    var title: String
    var price: Int
    var conditionTag: String
    var listingDescription: String
    var tags: [String]
    var imageCount: Int
    let queuedAt: Date
    var lastTriedAt: Date?
    var retryCount: Int
    var lastError: String?
}
