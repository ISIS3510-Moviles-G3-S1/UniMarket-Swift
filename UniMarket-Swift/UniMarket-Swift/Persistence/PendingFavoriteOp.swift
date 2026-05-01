import Foundation

// Persistent record of a save / unsave action the user took while offline.
// One record per (productID, userID); a new toggle for the same product
// collapses or removes the existing record (last-write-wins) so the queue
// never grows past the number of distinct products the user touched.
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
