import CryptoKit
import Foundation
import UIKit

final class ChatPhotoAnalysisCache {
    static let shared = ChatPhotoAnalysisCache()

    private let cache = NSCache<NSString, AnalysisResultBox>()

    private init() {
        cache.countLimit = 24
    }

    func cachedAnalysis(for image: UIImage) -> AnalysisResult? {
        guard let key = cacheKey(for: image) else { return nil }
        return cache.object(forKey: key)?.result
    }

    func store(_ result: AnalysisResult, for image: UIImage) {
        guard let key = cacheKey(for: image) else { return }
        cache.setObject(AnalysisResultBox(result: result), forKey: key)
    }

    func analyze(_ image: UIImage, using service: ImageAnalysisService) async throws -> AnalysisResult {
        if let cached = cachedAnalysis(for: image) {
            return cached
        }

        let result = try await service.analyzeImage(image)
        store(result, for: image)
        return result
    }

    private func cacheKey(for image: UIImage) -> NSString? {
        guard let imageData = image.jpegData(compressionQuality: 0.7) else { return nil }
        let digest = SHA256.hash(data: imageData)
        let hash = digest.map { String(format: "%02x", $0) }.joined()
        return NSString(string: hash)
    }
}

private final class AnalysisResultBox: NSObject {
    let result: AnalysisResult

    init(result: AnalysisResult) {
        self.result = result
    }
}
