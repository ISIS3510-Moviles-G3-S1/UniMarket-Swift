//
//  ProfileViewModel.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI
import Combine

final class ProfileViewModel: ObservableObject {
    struct MonthlyProductStats {
        let listingsCreated: Int
        let itemsSold: Int
    }
    
    enum Tab: String, CaseIterable {
        case activity = "Activity Feed"
        case listings = "My Listings"
    }

    enum TimeRange: String, CaseIterable {
        case week = "Last Week"
        case month = "Last 30 Days"
        case allTime = "All Time"
    }

    enum SalesPeriod: String, CaseIterable {
        case fifteenDays = "15 Days"
        case thisMonth = "This Month"
    }

    @Published var selectedTab: Tab = .activity
    @Published var currentUser: User?
    @Published var selectedTimeRange: TimeRange = .month
    @Published var selectedSalesPeriod: SalesPeriod = .thisMonth
    
    @Published var displayName: String = "Loading..."
    @Published var memberSince: String = "..."
    @Published var rating: Double = 0
    @Published var transactions: Int = 0
    @Published var xp: Int = 0
    @Published var xpToNext: Int = 100
    @Published var profilePicURL: String = ""
    
    @Published var ecoMessage = "Welcome! Start selling items to earn XP and unlock new levels."
    @Published var isGeneratingEcoMessage = false
    @Published var listings: [Product] = []
    @Published var editingListing: Product? = nil
    
    private var cancellables = Set<AnyCancellable>()
    private let productStore = ProductStore()
    
    private enum CacheKey {
        static let dynamicTransactions = "profile.dynamic.transactions"
        static let dynamicRating = "profile.dynamic.rating"
        static let dynamicXP = "profile.dynamic.xp"
        static let cachedName = "profile.cached.name"
        static let cachedProfilePic = "profile.cached.profilePic"
        static let cachedMemberSince = "profile.cached.memberSince"
        static let staticSeedUID = "profile.static.seed.uid"
        static let ecoMessageText = "profile.eco.message.text"
        static let ecoMessageListingsCount = "profile.eco.message.listingsCount"
        static let ecoMessageSoldCount = "profile.eco.message.soldCount"
    }
    
    init() {
        hydrateFromCache()
        setupSubscribers()
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Listen for when user creates a new listing
        NotificationCenter.default.addObserver(
            forName: .userDidCreateListing,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onListingEvent()
        }
        
        // Listen for when user sells a listing
        NotificationCenter.default.addObserver(
            forName: .userDidSellListing,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onListingEvent()
        }
    }
    
    private func onListingEvent() {
        Task {
            await fetchMyListings()
            await refreshPersonalizedEcoMessage(reason: "listing_event")
        }
    }
    
    func setupSubscribers() {
        SessionManager.shared.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                guard let self else { return }
                self.currentUser = user
                guard let user else { return }
                
                self.seedImmutableFieldsOnLoginIfNeeded(user)
                self.updateDisplayIdentityIfChanged(user)
                self.applyDynamicFields(user)
            }
            .store(in: &cancellables)
    }
    
    @MainActor
    func onProfileTabSelected() async {
        await SessionManager.shared.fetchUser()
        guard let user = SessionManager.shared.currentUser else { return }
        
        let levelInfo = calculateLevelInfo(xp: user.xpPoints)
        var didChange = false
        
        if rating != user.ratingStars {
            rating = user.ratingStars
            didChange = true
        }
        if transactions != user.numTransactions {
            transactions = user.numTransactions
            didChange = true
        }
        if xp != user.xpPoints {
            xp = user.xpPoints
            xpToNext = levelInfo.xpToNext
            didChange = true
        }
        
        let defaults = UserDefaults.standard
        if didChange {
            defaults.set(user.ratingStars, forKey: CacheKey.dynamicRating)
            defaults.set(user.numTransactions, forKey: CacheKey.dynamicTransactions)
            defaults.set(user.xpPoints, forKey: CacheKey.dynamicXP)
        }
        
        if defaults.string(forKey: CacheKey.cachedName) != user.displayName {
            displayName = user.displayName
            defaults.set(user.displayName, forKey: CacheKey.cachedName)
        }
        
        if defaults.string(forKey: CacheKey.cachedProfilePic) != user.profilePic {
            profilePicURL = user.profilePic
            defaults.set(user.profilePic, forKey: CacheKey.cachedProfilePic)
        }
        
        await fetchMyListings()
        
        // Always refresh on profile tab launch (will use cache if appropriate)
        await refreshPersonalizedEcoMessage(reason: "app_launch")
    }
    
    func fetchMyListings() async {
        guard let uid = SessionManager.shared.currentUser?.id else {
            await MainActor.run { listings = [] }
            return
        }
        
        let mine = productStore.myListings(for: uid)
        await MainActor.run {
            listings = mine
        }
    }
    
    private func hydrateFromCache() {
        let defaults = UserDefaults.standard
        
        displayName = defaults.string(forKey: CacheKey.cachedName) ?? "Loading..."
        memberSince = defaults.string(forKey: CacheKey.cachedMemberSince) ?? "..."
        profilePicURL = defaults.string(forKey: CacheKey.cachedProfilePic) ?? ""
        
        rating = defaults.double(forKey: CacheKey.dynamicRating)
        transactions = defaults.integer(forKey: CacheKey.dynamicTransactions)
        xp = defaults.integer(forKey: CacheKey.dynamicXP)
        
        let levelInfo = calculateLevelInfo(xp: xp)
        xpToNext = levelInfo.xpToNext
        
        // Load cached eco message if available
        if let cachedMessage = defaults.string(forKey: CacheKey.ecoMessageText), !cachedMessage.isEmpty {
            ecoMessage = cachedMessage
        } else {
            updateEcoMessage(xp: xp)
        }
    }
    
    private func applyDynamicFields(_ user: User) {
        let levelInfo = calculateLevelInfo(xp: user.xpPoints)
        
        var dataChanged = false
        if rating != user.ratingStars {
            rating = user.ratingStars
            dataChanged = true
        }
        if transactions != user.numTransactions {
            transactions = user.numTransactions
            dataChanged = true
        }
        if xp != user.xpPoints {
            xp = user.xpPoints
            xpToNext = levelInfo.xpToNext
            dataChanged = true
        }
        
        let defaults = UserDefaults.standard
        if dataChanged {
            defaults.set(user.ratingStars, forKey: CacheKey.dynamicRating)
            defaults.set(user.numTransactions, forKey: CacheKey.dynamicTransactions)
            defaults.set(user.xpPoints, forKey: CacheKey.dynamicXP)
        }
        
        // Don't call updateEcoMessage here - let the cached AI message persist
    }
    
    private func updateDisplayIdentityIfChanged(_ user: User) {
        let defaults = UserDefaults.standard
        
        if defaults.string(forKey: CacheKey.cachedName) != user.displayName {
            displayName = user.displayName
            defaults.set(user.displayName, forKey: CacheKey.cachedName)
        }
        
        if defaults.string(forKey: CacheKey.cachedProfilePic) != user.profilePic {
            profilePicURL = user.profilePic
            defaults.set(user.profilePic, forKey: CacheKey.cachedProfilePic)
        }
    }
    
    private func seedImmutableFieldsOnLoginIfNeeded(_ user: User) {
        let defaults = UserDefaults.standard
        let lastSeedUID = defaults.string(forKey: CacheKey.staticSeedUID)
        
        guard lastSeedUID != user.id else {
            if let cachedMemberSince = defaults.string(forKey: CacheKey.cachedMemberSince) {
                memberSince = cachedMemberSince
            }
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        let formattedMemberSince = dateFormatter.string(from: user.createdAt)
        
        memberSince = formattedMemberSince
        
        defaults.set(formattedMemberSince, forKey: CacheKey.cachedMemberSince)
        defaults.set(user.id, forKey: CacheKey.staticSeedUID)
    }
    
    func calculateLevelInfo(xp: Int) -> (title: String, nextTitle: String, xpToNext: Int, minXP: Int, maxXP: Int) {
        switch xp {
        case 0..<100:
            return ("Level 1 - Newcomer", "Level 2 - Eco Learner", 100 - xp, 0, 100)
        case 100..<300:
            return ("Level 2 - Eco Learner", "Level 3 - Eco Enthusiast", 300 - xp, 100, 300)
        case 300..<600:
            return ("Level 3 - Eco Enthusiast", "Level 4 - Eco Explorer", 600 - xp, 300, 600)
        case 600..<1000:
            return ("Level 4 - Eco Explorer", "Level 5 - Sustainability Star", 1000 - xp, 600, 1000)
        default:
            return ("Level 5 - Sustainability Star", "Max Level", 0, 1000, 10000)
        }
    }
    
    func updateEcoMessage(xp: Int) {
        // Don't overwrite AI-generated messages with the generic fallback
        let defaults = UserDefaults.standard
        if let cachedMessage = defaults.string(forKey: CacheKey.ecoMessageText), !cachedMessage.isEmpty {
            // We have an AI-generated message cached, don't replace it
            return
        }
        
        // Only use generic message if no AI message exists
        let levelInfo = calculateLevelInfo(xp: xp)
        if xp >= 1000 {
            ecoMessage = "You're a Sustainability Star! You've reached the top level. Keep leading the way!"
        } else {
            ecoMessage = "You're just \(levelInfo.xpToNext) XP away from \(levelInfo.nextTitle). Keep it up to unlock new badges and rewards!"
        }
    }

    @MainActor
    private func refreshPersonalizedEcoMessage(reason: String) async {
        guard APIConfig.isOpenRouterConfigured() else { return }
        guard !isGeneratingEcoMessage else { return }

        let levelInfo = calculateLevelInfo(xp: xp)
        let listingsCount = listings.count
        let soldCount = listings.filter { $0.soldAt != nil }.count

        let defaults = UserDefaults.standard
        let lastListingsCount = defaults.integer(forKey: CacheKey.ecoMessageListingsCount)
        let lastSoldCount = defaults.integer(forKey: CacheKey.ecoMessageSoldCount)

        if reason == "app_launch" && listingsCount == lastListingsCount && soldCount == lastSoldCount {
            return
        }

        isGeneratingEcoMessage = true
        defer { isGeneratingEcoMessage = false }

        let prompt = """
        Create one personalized sustainability recommendation for this user.
        Name: \(displayName)
        Rating: \(String(format: "%.2f", rating))/5
        XP: \(xp)
        Sustainability level: \(levelInfo.title)
        XP to next level: \(max(0, levelInfo.xpToNext))
        Total listings created: \(listingsCount)
        Number of listings sold: \(soldCount)
        Total transactions: \(transactions)
        """

        do {
            let response = try await OpenRouterService.shared.generateEcoRecommendation(prompt: prompt)
            ecoMessage = response
            defaults.set(response, forKey: CacheKey.ecoMessageText)
            defaults.set(listingsCount, forKey: CacheKey.ecoMessageListingsCount)
            defaults.set(soldCount, forKey: CacheKey.ecoMessageSoldCount)
        } catch { }
    }
    
    private func versionedProfileImageKey(from urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let separator = trimmed.contains("?") ? "&" : "?"
        return "\(trimmed)\(separator)v=\(Int(Date().timeIntervalSince1970))"
    }
    
    func uploadProfileImage(_ image: UIImage) async {
        do {
            let uploadedURL = try await ImageUploadService.uploadProfilePic(image)
            let previousCacheKey = profilePicURL
            
            try await SessionManager.shared.updateProfileImage(withImageUrl: uploadedURL)
            
            if !previousCacheKey.isEmpty {
                CachedRemoteImageView.invalidateCache(for: previousCacheKey)
            }
            CachedRemoteImageView.invalidateCache(for: uploadedURL)
            
            let versionedURL = versionedProfileImageKey(from: uploadedURL)
            profilePicURL = versionedURL
            UserDefaults.standard.set(versionedURL, forKey: CacheKey.cachedProfilePic)
        } catch { }
    }
    
    func deleteProfileImage() async {
        do {
            let previousCacheKey = profilePicURL
            try await SessionManager.shared.updateProfileImage(withImageUrl: "")
            
            if !previousCacheKey.isEmpty {
                CachedRemoteImageView.invalidateCache(for: previousCacheKey)
            }
            
            profilePicURL = ""
            UserDefaults.standard.set("", forKey: CacheKey.cachedProfilePic)
        } catch { }
    }
    
    var monthlyProductStats: MonthlyProductStats {
        let calendar = Calendar.current
        let cutoffDate: Date
        
        switch selectedTimeRange {
        case .week:
            cutoffDate = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        case .month:
            cutoffDate = calendar.date(byAdding: .month, value: -1, to: .now) ?? .now
        case .allTime:
            cutoffDate = Date.distantPast
        }
        
        let listingsCreated = listings.filter { $0.createdAt >= cutoffDate }.count
        let itemsSold = listings.filter { product in
            guard let soldAt = product.soldAt else { return false }
            return soldAt >= cutoffDate
        }.count
        
        return MonthlyProductStats(
            listingsCreated: listingsCreated,
            itemsSold: itemsSold
        )
    }
    
    var soldCountForPeriod: Int {
        let calendar = Calendar.current
        let now = Date()
        let cutoff: Date
        switch selectedSalesPeriod {
        case .fifteenDays:
            cutoff = calendar.date(byAdding: .day, value: -15, to: now) ?? now
        case .thisMonth:
            cutoff = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        }
        return listings.filter { $0.soldAt.map { $0 >= cutoff } ?? false }.count
    }

    var sellerFeedbackMessage: String {
        switch soldCountForPeriod {
        case 0:
            return "No items sold yet in this period. Try improving your photos or adjusting your price."
        case 1...2:
            return "Nice start! You've already sold some items this period."
        case 3...5:
            return "Good progress! Your listings are getting attention."
        case 6...10:
            return "Great job! You're selling consistently."
        default:
            return "Excellent work! Your closet is performing really well."
        }
    }

    func deleteListing(_ product: Product) {
        listings.removeAll { $0.id == product.id }
    }
    
    func openEdit(_ product: Product) {
        editingListing = product
    }
    
    func saveEdits(_ updated: Product) {
        guard let idx = listings.firstIndex(where: { $0.id == updated.id }) else { return }
        listings[idx] = updated
        editingListing = nil
    }
}
