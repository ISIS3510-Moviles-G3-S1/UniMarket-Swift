import UIKit

// In-memory image cache backed by NSCache.
//
// NSCache automatically evicts the least-recently-used entries under memory pressure
// or when either limit is exceeded — no manual eviction code is needed.
//
// Limits chosen for a typical campus-marketplace browsing session:
//   countLimit  = 100 images  → a user can browse ~5 pages of the grid (20 cards × 5 pages)
//                               without any re-downloads.
//   totalCostLimit = 50 MB   → well within iOS's ~150–200 MB foreground budget for a
//                               shopping app. At ~130 KB per 400×400 product thumbnail,
//                               100 images cost ~13 MB; the 50 MB ceiling handles larger
//                               photos (e.g., 1080×1440 detail shots at ~6 MB each) while
//                               still leaving headroom for the rest of the app.
final class ProductImageCache {
    static let shared = ProductImageCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024  // 50 MB
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: estimatedCost(for: image))
    }

    func remove(for url: URL) {
        cache.removeObject(forKey: url.absoluteString as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    // Uncompressed RGBA pixel buffer: width × height × 4 bytes.
    // This is what UIImage occupies in memory once decoded, regardless of the
    // compressed size on disk or over the network.
    private func estimatedCost(for image: UIImage) -> Int {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        return w * h * 4
    }
}
