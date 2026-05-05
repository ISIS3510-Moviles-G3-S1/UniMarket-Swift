import Foundation

// Codable enables encoding/decoding to JSON for structured UserDefaults storage
struct FavoriteItem: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let price: Int
    let imageURL: String?
    let sellerName: String
}
