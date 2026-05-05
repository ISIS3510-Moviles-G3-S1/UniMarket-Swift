import Foundation

@MainActor
final class RecommendationsLRUCache {
    static let shared = RecommendationsLRUCache(capacity: 10)

    private let capacity: Int
    private var entriesByUser: [String: [CacheEntry]] = [:]

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    func products(for userID: String?) -> [Product] {
        entriesByUser[cacheNamespace(for: userID), default: []].map(\.product)
    }

    func store(_ products: [Product], for userID: String?) {
        let key = cacheNamespace(for: userID)
        var entries = entriesByUser[key, default: []]

        for product in products.prefix(capacity) {
            entries.removeAll { $0.product.id == product.id }
            entries.insert(CacheEntry(product: product, lastAccessedAt: .now), at: 0)
        }

        if entries.count > capacity {
            entries = Array(entries.prefix(capacity))
        }

        entriesByUser[key] = entries
    }

    func touch(_ product: Product, for userID: String?) {
        let key = cacheNamespace(for: userID)
        var entries = entriesByUser[key, default: []]

        entries.removeAll { $0.product.id == product.id }
        entries.insert(CacheEntry(product: product, lastAccessedAt: .now), at: 0)

        if entries.count > capacity {
            entries = Array(entries.prefix(capacity))
        }

        entriesByUser[key] = entries
    }

    private func cacheNamespace(for userID: String?) -> String {
        guard let userID, !userID.isEmpty else { return "guest" }
        return userID
    }
}

private struct CacheEntry {
    let product: Product
    let lastAccessedAt: Date
}
