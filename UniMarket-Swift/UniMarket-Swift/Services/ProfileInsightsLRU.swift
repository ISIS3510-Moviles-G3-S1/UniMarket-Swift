import Foundation

// Custom array-LRU memoizing SustainabilityImpact.calculate per user,
// keyed by a fingerprint of the sold-listings set. Mirrors the
// RecommendationsLRUCache shape. See Caching.md §2.
@MainActor
final class ProfileInsightsLRU {
    static let shared = ProfileInsightsLRU(capacity: 8)

    private let capacity: Int
    private var entries: [Entry] = []

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    // MARK: - Public API

    /// Hit only when both userID and fingerprint match; mismatch == miss.
    func lookup(userID: String, fingerprint: String) -> SustainabilityImpact? {
        guard let idx = entries.firstIndex(where: { $0.userID == userID }) else { return nil }
        let entry = entries[idx]
        guard entry.fingerprint == fingerprint else { return nil }

        // Promote to MRU.
        entries.remove(at: idx)
        entries.insert(entry, at: 0)
        return entry.summary
    }

    func store(userID: String, fingerprint: String, summary: SustainabilityImpact) {
        entries.removeAll { $0.userID == userID }
        entries.insert(
            Entry(
                userID: userID,
                fingerprint: fingerprint,
                summary: summary,
                computedAt: Date()
            ),
            at: 0
        )
        if entries.count > capacity {
            entries = Array(entries.prefix(capacity))
        }
    }

    func invalidate(userID: String) {
        entries.removeAll { $0.userID == userID }
    }

    func clear() {
        entries.removeAll()
    }

    // MARK: - Fingerprint helper

    /// Sorted IDs + count — invariant under reorder, sensitive to set changes.
    static func fingerprint(soldProducts: [Product]) -> String {
        guard !soldProducts.isEmpty else { return "empty" }
        let ids = soldProducts.map(\.id).sorted().joined(separator: ",")
        return "\(soldProducts.count)|\(ids)"
    }

    // MARK: - Storage

    private struct Entry {
        let userID: String
        let fingerprint: String
        let summary: SustainabilityImpact
        let computedAt: Date
    }
}
