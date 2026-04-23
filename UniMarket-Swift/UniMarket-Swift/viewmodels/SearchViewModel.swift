//
//  SearchViewModel.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI
import Combine
import FirebaseAuth

@MainActor
final class SearchViewModel: ObservableObject {
    enum SearchSection: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case forYou = "For You"

        var id: String { rawValue }
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case relevance = "Relevance"
        case priceLowHigh = "Price: Low to High"
        case priceHighLow = "Price: High to Low"
        case ratingHighLow = "Rating: High to Low"

        var id: String { rawValue }
    }

    @Published var selectedSection: SearchSection = .browse
    @Published var query: String = ""
    @Published var selectedTag: String? = nil
    @Published var selectedConditions: Set<String> = []
    @Published var onlyFavorites: Bool = false
    @Published var minRating: Double = 0
    @Published var sortOption: SortOption = .relevance

    @Published var minPrice: Int = 0
    @Published var maxPrice: Int = 0
    @Published private(set) var recentSearches: [String] = []
    @Published private(set) var recommendedProducts: [Product] = []
    @Published private(set) var isLoadingRecommendations = false

    @Published var products: [Product] = [] {
        didSet {
            if oldValue.map(\ .id) != products.map(\ .id) {
                resetPriceRange()
            }
        }
    }

    private let defaults = UserDefaults.standard
    private let recentSearchesKey = "search.recent-queries"
    private let maxRecentSearches = 8

    init() {
        recentSearches = defaults.stringArray(forKey: recentSearchesKey) ?? []
        resetPriceRange()
    }

    var availableTags: [String] {
        Array(Set(products.flatMap { $0.tags })).sorted()
    }

    var availableConditions: [String] {
        Array(Set(products.map { $0.conditionTag })).sorted()
    }

    var priceBounds: ClosedRange<Int> {
        let prices = products.map { $0.price }
        let min = prices.min() ?? 0
        let max = prices.max() ?? 100
        return min...max
    }

    var activeFilterCount: Int {
        var count = 0
        if selectedTag != nil { count += 1 }
        if !selectedConditions.isEmpty { count += 1 }
        if onlyFavorites { count += 1 }
        if minRating > 0 { count += 1 }
        if minPrice != priceBounds.lowerBound || maxPrice != priceBounds.upperBound { count += 1 }
        if sortOption != .relevance { count += 1 }
        return count
    }

    var filteredProducts: [Product] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered = products.filter { product in
            let matchesQuery: Bool
            if q.isEmpty {
                matchesQuery = true
            } else {
                matchesQuery =
                    product.title.localizedCaseInsensitiveContains(q) ||
                    product.tags.contains(where: { $0.localizedCaseInsensitiveContains(q) })
            }

            let matchesTag = selectedTag == nil || product.tags.contains(where: {
                $0.caseInsensitiveCompare(selectedTag ?? "") == .orderedSame
            })

            let matchesCondition = selectedConditions.isEmpty || selectedConditions.contains(product.conditionTag)
            let matchesPrice = product.price >= minPrice && product.price <= maxPrice
            let matchesFavorite = !onlyFavorites || product.isFavorite
            let matchesRating = product.rating >= minRating

            return matchesQuery && matchesTag && matchesCondition && matchesPrice && matchesFavorite && matchesRating
        }

        switch sortOption {
        case .relevance:
            return filtered
        case .priceLowHigh:
            return filtered.sorted { $0.price < $1.price }
        case .priceHighLow:
            return filtered.sorted { $0.price > $1.price }
        case .ratingHighLow:
            return filtered.sorted { $0.rating > $1.rating }
        }
    }

    func toggleFavorite(for product: Product) {
        guard let idx = products.firstIndex(where: { $0.id == product.id }) else { return }
        products[idx].isFavorite.toggle()
        scheduleRecommendationRefresh()
    }

    func updateProducts(_ products: [Product]) {
        let uid = Auth.auth().currentUser?.uid
        self.products = products.filter { $0.sellerId != uid }
        scheduleRecommendationRefresh()
    }

    func selectTag(_ tag: String?) {
        selectedTag = tag
    }

    func selectRecentSearch(_ search: String) {
        query = search
        selectedSection = .browse
        saveRecentSearch(search)
    }

    func saveCurrentQueryIfNeeded() {
        saveRecentSearch(query)
    }

    func toggleCondition(_ condition: String) {
        if selectedConditions.contains(condition) {
            selectedConditions.remove(condition)
        } else {
            selectedConditions.insert(condition)
        }
    }

    func resetFilters() {
        selectedTag = nil
        selectedConditions.removeAll()
        onlyFavorites = false
        minRating = 0
        sortOption = .relevance
        resetPriceRange()
    }

    private func resetPriceRange() {
        minPrice = priceBounds.lowerBound
        maxPrice = priceBounds.upperBound
    }

    private func saveRecentSearch(_ rawQuery: String) {
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

private enum SearchRecommendationEngine {
    struct RecommendationSignals {
        let favoriteTagWeights: [String: Int]
        let recentSearchTerms: [String]
        let preferredConditions: Set<String>
        let averageFavoritePrice: Double?
    }

    nonisolated static func buildRecommendations(from products: [Product], recentSearches: [String]) async -> [Product] {
        guard !products.isEmpty else { return [] }

        async let favoriteTagWeights = computeFavoriteTagWeights(from: products)
        async let recentSearchTerms = computeRecentSearchTerms(from: recentSearches)
        async let preferredConditions = computePreferredConditions(from: products)
        async let averageFavoritePrice = computeAverageFavoritePrice(from: products)

        let signals = await RecommendationSignals(
            favoriteTagWeights: favoriteTagWeights,
            recentSearchTerms: recentSearchTerms,
            preferredConditions: preferredConditions,
            averageFavoritePrice: averageFavoritePrice
        )

        guard !signals.favoriteTagWeights.isEmpty || !signals.recentSearchTerms.isEmpty else {
            return []
        }

        return await withTaskGroup(of: (Product, Int)?.self, returning: [Product].self) { group in
            for product in products where !product.isFavorite {
                group.addTask {
                    let score = await recommendationScore(for: product, signals: signals)
                    guard score > 0 else { return nil }
                    return (product, score)
                }
            }

            var rankedProducts: [(product: Product, score: Int)] = []
            for await candidate in group {
                guard let candidate else { continue }
                rankedProducts.append(candidate)
            }

            return rankedProducts
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        return lhs.product.createdAt > rhs.product.createdAt
                    }
                    return lhs.score > rhs.score
                }
                .map(\.product)
        }
    }

    nonisolated static func computeFavoriteTagWeights(from products: [Product]) -> [String: Int] {
        let favoriteProducts = products.filter(\.isFavorite)
        var weights: [String: Int] = [:]

        for product in favoriteProducts {
            for tag in product.tags {
                let normalized = normalize(tag)
                guard !normalized.isEmpty else { continue }
                weights[normalized, default: 0] += 3
            }
        }

        return weights
    }

    nonisolated static func computeRecentSearchTerms(from recentSearches: [String]) -> [String] {
        recentSearches
            .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }
            .map(normalize)
            .filter { $0.count >= 2 }
    }

    nonisolated static func computePreferredConditions(from products: [Product]) -> Set<String> {
        Set(
            products
                .filter(\.isFavorite)
                .map { normalize($0.conditionTag) }
                .filter { !$0.isEmpty }
        )
    }

    nonisolated static func computeAverageFavoritePrice(from products: [Product]) -> Double? {
        let favoritePrices = products
            .filter(\.isFavorite)
            .map(\.price)

        guard !favoritePrices.isEmpty else { return nil }
        let total = favoritePrices.reduce(0, +)
        return Double(total) / Double(favoritePrices.count)
    }

    nonisolated static func recommendationScore(for product: Product, signals: RecommendationSignals) async -> Int {
        await withTaskGroup(of: Int.self, returning: Int.self) { group in
            group.addTask {
                scoreFavoriteTags(for: product, weights: signals.favoriteTagWeights)
            }
            group.addTask {
                scoreRecentSearches(for: product, recentTerms: signals.recentSearchTerms)
            }
            group.addTask {
                scoreConditionAndPriceFit(
                    for: product,
                    preferredConditions: signals.preferredConditions,
                    averageFavoritePrice: signals.averageFavoritePrice
                )
            }
            group.addTask {
                scoreFreshnessAndQuality(for: product)
            }

            var total = 0
            for await partialScore in group {
                total += partialScore
            }
            return total
        }
    }

    nonisolated static func scoreFavoriteTags(for product: Product, weights: [String: Int]) -> Int {
        let normalizedTags = product.tags.map(normalize)
        var score = 0

        for tag in normalizedTags {
            score += weights[tag, default: 0]
        }

        return score
    }

    nonisolated static func scoreRecentSearches(for product: Product, recentTerms: [String]) -> Int {
        let normalizedTags = product.tags.map(normalize)
        let title = normalize(product.title)
        let description = normalize(product.description)

        var score = 0

        for term in recentTerms {
            if normalizedTags.contains(where: { $0.contains(term) || term.contains($0) }) {
                score += 2
            }

            if title.contains(term) {
                score += 2
            } else if description.contains(term) {
                score += 1
            }
        }

        return score
    }

    nonisolated static func scoreConditionAndPriceFit(
        for product: Product,
        preferredConditions: Set<String>,
        averageFavoritePrice: Double?
    ) -> Int {
        var score = 0
        let normalizedCondition = normalize(product.conditionTag)

        if preferredConditions.contains(normalizedCondition) {
            score += 2
        }

        if let averageFavoritePrice {
            let distance = abs(Double(product.price) - averageFavoritePrice)
            if distance <= 20000 {
                score += 3
            } else if distance <= 40000 {
                score += 1
            }
        }

        return score
    }

    nonisolated static func scoreFreshnessAndQuality(for product: Product) -> Int {
        var score = min(product.tags.count, 3)

        if product.rating >= 4.5 {
            score += 2
        } else if product.rating >= 4.0 {
            score += 1
        }

        let ageInDays = Calendar.current.dateComponents([.day], from: product.createdAt, to: .now).day ?? 0
        if ageInDays <= 7 {
            score += 2
        } else if ageInDays <= 21 {
            score += 1
        }

        return score
    }

    nonisolated static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
