import Foundation

// Persistent envelope for a listing the user has submitted but the network
// hasn't accepted yet. Stored on disk under
//   ~/Library/Application Support/UniMarket-Swift/PendingListings/{userID}/
// as one JSON file plus N JPEG sidecar files (one per attached photo).
//
// Image bytes are kept in sidecar files (not base64 inline) to keep JSON
// payloads small, debuggable, and editable, and to avoid the ~33% encoding
// overhead of base64 for what could be several megabytes of image data.
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
