import Foundation
import Combine
import FirebaseAuth

@MainActor
final class SearchRecommendationsViewModel: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var recommendedProducts: [Product] = []
    @Published private(set) var isLoadingRecommendations = false

    private let defaults = UserDefaults.standard
    private let recentSearchesKey = "search.recent-queries"
    private let maxRecentSearches = 8

    init() {
        recentSearches = defaults.stringArray(forKey: recentSearchesKey) ?? []
    }

    func updateProducts(_ products: [Product]) {
        let uid = Auth.auth().currentUser?.uid
        self.products = products.filter { $0.sellerId != uid }
        scheduleRecommendationRefresh()
    }

    func toggleFavorite(for product: Product) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        products[idx].isFavorite.toggle()
        scheduleRecommendationRefresh()
    }

    func saveSearch(_ rawQuery: String) {
        let normalized = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        recentSearches.removeAll { $0.caseInsensitiveCompare(normalized) == .orderedSame }
        recentSearches.insert(normalized, at: 0)

        if recentSearches.count > maxRecentSearches {
            recentSearches = Array(recentSearches.prefix(maxRecentSearches))
        }

        defaults.set(recentSearches, forKey: recentSearchesKey)
        scheduleRecommendationRefresh()
    }

    func refreshRecommendations() async {
        let products = self.products
        let recentSearches = self.recentSearches

        isLoadingRecommendations = true

        let recommendations = await Task.detached(priority: .userInitiated) {
            await SearchRecommendationEngine.buildRecommendations(from: products, recentSearches: recentSearches)
        }.value

        self.recommendedProducts = recommendations
        isLoadingRecommendations = false
    }

    private func scheduleRecommendationRefresh() {
        Task { [weak self] in
            await self?.refreshRecommendations()
        }
    }
}
