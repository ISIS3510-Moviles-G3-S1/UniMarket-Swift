import Foundation

// Warms the eco-message and sustainability-impact caches in the background after
// login, before the user ever opens the Profile tab. The work is launched on
// Task.detached(priority: .background) so it lives outside the calling actor's
// hierarchy and runs on the background-QoS global executor — explicitly pinning
// the coroutine to a non-main, non-user-initiated dispatcher.
//
// On a successful preload, ProfileViewModel.hydrateFromCache() reads the warmed
// values on the next Profile tab open and the user sees the full text instantly
// (skipping the staleness check inside refresh*).
enum ProfileInsightsPreloader {

    private enum CacheKey {
        static let ecoMessageText = "profile.eco.message.text"
        static let ecoMessageListingsCount = "profile.eco.message.listingsCount"
        static let ecoMessageSoldCount = "profile.eco.message.soldCount"
        static let impactMessageText = "profile.impact.message.text"
        static let impactMessageSoldCount = "profile.impact.message.soldCount"
    }

    static func preloadAfterLogin(session: SessionManager, productStore: ProductStore) {
        Task.detached(priority: .background) {
            // Wait up to ~5s for currentUser + listings to populate after auth.
            // We poll because both are driven by Firestore listeners that resolve
            // asynchronously after isLoggedIn flips.
            for _ in 0..<20 {
                let ready = await MainActor.run { session.currentUser != nil && !productStore.products.isEmpty }
                if ready { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }

            guard let snapshot = await MainActor.run(body: { () -> Snapshot? in
                guard let user = session.currentUser else { return nil }
                return Snapshot(user: user, listings: productStore.myListings(for: user.id))
            }) else { return }

            await preloadEco(snapshot: snapshot)
            await preloadImpact(snapshot: snapshot)
        }
    }

    private struct Snapshot {
        let user: User
        let listings: [Product]
    }

    private static func preloadEco(snapshot: Snapshot) async {
        guard APIConfig.isOpenRouterConfigured() else { return }

        let listingsCount = snapshot.listings.count
        let soldCount = snapshot.listings.filter { $0.soldAt != nil }.count

        let defaults = UserDefaults.standard
        let lastListings = defaults.integer(forKey: CacheKey.ecoMessageListingsCount)
        let lastSold = defaults.integer(forKey: CacheKey.ecoMessageSoldCount)
        let cached = defaults.string(forKey: CacheKey.ecoMessageText) ?? ""

        // Skip preload if cache is already warm and stats haven't changed.
        if !cached.isEmpty && lastListings == listingsCount && lastSold == soldCount {
            return
        }

        let xp = snapshot.user.xpPoints
        let levelTitle = levelTitle(forXP: xp)
        let xpToNext = xpToNext(forXP: xp)

        let prompt = """
        Create one personalized sustainability recommendation for this user.
        Name: \(snapshot.user.displayName)
        Rating: \(String(format: "%.2f", snapshot.user.ratingStars))/5
        XP: \(xp)
        Sustainability level: \(levelTitle)
        XP to next level: \(max(0, xpToNext))
        Total listings created: \(listingsCount)
        Number of listings sold: \(soldCount)
        Total transactions: \(snapshot.user.numTransactions)
        """

        var buffer = ""
        do {
            for try await chunk in OpenRouterService.shared.streamEcoRecommendation(prompt: prompt) {
                buffer += chunk
            }
            guard !buffer.isEmpty else { return }
            defaults.set(buffer, forKey: CacheKey.ecoMessageText)
            defaults.set(listingsCount, forKey: CacheKey.ecoMessageListingsCount)
            defaults.set(soldCount, forKey: CacheKey.ecoMessageSoldCount)
        } catch { }
    }

    private static func preloadImpact(snapshot: Snapshot) async {
        let soldListings = snapshot.listings.filter { $0.soldAt != nil }
        let summary = SustainabilityImpact.calculate(from: soldListings)
        guard summary.itemsReused > 0 else { return }

        let defaults = UserDefaults.standard
        let cachedSold = defaults.integer(forKey: CacheKey.impactMessageSoldCount)
        let cachedText = defaults.string(forKey: CacheKey.impactMessageText) ?? ""
        if !cachedText.isEmpty && cachedSold == summary.itemsReused { return }

        guard APIConfig.isOpenRouterConfigured() else { return }

        let breakdown = summary.topCategories
            .map { "\($0.count)× \($0.category.displayName.lowercased())" }
            .joined(separator: ", ")
        let breakdownLine = breakdown.isEmpty ? "mixed garments" : breakdown
        let firstName = snapshot.user.displayName.split(separator: " ").first.map(String.init) ?? snapshot.user.displayName

        let prompt = """
        Turn these real reuse numbers into one sharp, personal insight for \(firstName).
        Items given a second life: \(summary.itemsReused)
        Water kept out of production: \(summary.waterLiters) liters (≈ \(summary.showerEquivalents) showers)
        CO2 emissions avoided: \(String(format: "%.1f", summary.co2Kg)) kg (≈ \(summary.drivingKilometersAvoided) km of driving, \(String(format: "%.1f", summary.treeYearsEquivalent)) tree-years)
        Textile waste diverted: \(String(format: "%.1f", summary.wasteKg)) kg
        Strongest categories: \(breakdownLine)
        Total transactions on platform: \(snapshot.user.numTransactions)
        """

        var buffer = ""
        do {
            for try await chunk in OpenRouterService.shared.streamImpactInsight(prompt: prompt) {
                buffer += chunk
            }
            guard !buffer.isEmpty else { return }
            defaults.set(buffer, forKey: CacheKey.impactMessageText)
            defaults.set(summary.itemsReused, forKey: CacheKey.impactMessageSoldCount)
        } catch { }
    }

    private static func levelTitle(forXP xp: Int) -> String {
        switch xp {
        case 0..<100: return "Level 1 - Newcomer"
        case 100..<300: return "Level 2 - Eco Learner"
        case 300..<600: return "Level 3 - Eco Enthusiast"
        case 600..<1000: return "Level 4 - Eco Explorer"
        default: return "Level 5 - Sustainability Star"
        }
    }

    private static func xpToNext(forXP xp: Int) -> Int {
        switch xp {
        case 0..<100: return 100 - xp
        case 100..<300: return 300 - xp
        case 300..<600: return 600 - xp
        case 600..<1000: return 1000 - xp
        default: return 0
        }
    }
}
