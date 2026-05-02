import Foundation

// NSCache for users/{uid} display-name + avatar lookups, hit by
// ChatStore.parseConversation. See Caching.md §1 for parameter rationale.
final class UserProfileCache {
    static let shared = UserProfileCache()

    /// Soft TTL applied at lookup time.
    private let timeToLive: TimeInterval = 600  // 10 min

    private let cache = NSCache<NSString, CachedEntry>()

    private init() {
        cache.countLimit = 200
        cache.totalCostLimit = 256 * 1024  // ~256 entries at ~1 KB each
    }

    // MARK: - Public API

    func lookup(uid: String) -> Snapshot? {
        guard let entry = cache.object(forKey: uid as NSString) else { return nil }
        guard Date().timeIntervalSince(entry.cachedAt) < timeToLive else {
            cache.removeObject(forKey: uid as NSString)
            return nil
        }
        return entry.snapshot
    }

    func store(uid: String, displayName: String, profilePic: String?) {
        let entry = CachedEntry(
            snapshot: Snapshot(displayName: displayName, profilePic: profilePic),
            cachedAt: Date()
        )
        let cost = displayName.utf8.count + (profilePic?.utf8.count ?? 0) + 32
        cache.setObject(entry, forKey: uid as NSString, cost: cost)
    }

    func invalidate(uid: String) {
        cache.removeObject(forKey: uid as NSString)
    }

    func clear() {
        cache.removeAllObjects()
    }

    // MARK: - Types

    struct Snapshot {
        let displayName: String
        let profilePic: String?
    }

    /// Reference wrapper required by NSCache; carries cachedAt for the TTL.
    private final class CachedEntry {
        let snapshot: Snapshot
        let cachedAt: Date

        init(snapshot: Snapshot, cachedAt: Date) {
            self.snapshot = snapshot
            self.cachedAt = cachedAt
        }
    }
}
