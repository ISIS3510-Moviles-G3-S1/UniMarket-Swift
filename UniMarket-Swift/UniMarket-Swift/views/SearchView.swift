//
//  SearchView.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

struct SearchView: View {
    private let analytics = AnalyticsService.shared
    @EnvironmentObject private var productStore: ProductStore
    @StateObject private var browseViewModel = BrowseSearchViewModel()
    @StateObject private var recommendationsViewModel = SearchRecommendationsViewModel()
    @State private var selectedSection: SearchSection = .browse
    @State private var selectedProduct: Product?
    @State private var hasTrackedSearchView = false
    @State private var showFilters = false

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack {
                    Text("Browse")
                        .font(.poppinsBold(30))
                        .foregroundStyle(AppTheme.accent)
                    Spacer()
                    Text("UniMarket")
                        .font(.poppinsRegular(12))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .padding(.horizontal)

                Picker("", selection: $selectedSection) {
                    ForEach(SearchSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if selectedSection == .browse {
                    BrowseSearchView(
                        isStoreLoading: productStore.isLoading,
                        viewModel: browseViewModel,
                        onSubmitSearch: {
                            recommendationsViewModel.saveSearch(browseViewModel.query)
                        },
                        onToggleFavorite: { product in
                            toggleFavorite(for: product)
                        },
                        onSelectProduct: { product in
                            if !browseViewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                recommendationsViewModel.saveSearch(browseViewModel.query)
                            }
                            selectedProduct = product
                        },
                        onResetFilters: {
                            browseViewModel.resetFilters()
                            analytics.track(.searchReset())
                        },
                        onApplyFilters: {
                            analytics.track(.searchFiltersApplied(
                                activeFilterCount: browseViewModel.activeFilterCount,
                                selectedTag: browseViewModel.selectedTag,
                                selectedConditionCount: browseViewModel.selectedConditions.count,
                                onlyFavorites: browseViewModel.onlyFavorites,
                                minRating: browseViewModel.minRating,
                                sortOption: browseViewModel.sortOption.rawValue
                            ))
                            withAnimation(.easeInOut(duration: 0.22)) {
                                showFilters = false
                            }
                        },
                        showFilters: $showFilters
                    )
                } else {
                    SearchRecommendationsView(
                        viewModel: recommendationsViewModel,
                        onSelectRecentSearch: { search in
                            browseViewModel.applyRecentSearch(search)
                            recommendationsViewModel.saveSearch(search)
                            selectedSection = .browse
                        },
                        onToggleFavorite: { product in
                            toggleFavorite(for: product)
                        },
                        onSelectProduct: { product in
                            selectedProduct = product
                        }
                    )
                }
            }
        }
        .task {
            browseViewModel.updateProducts(productStore.activeProducts)
            recommendationsViewModel.updateProducts(productStore.activeProducts)
            guard !hasTrackedSearchView else { return }
            analytics.track(.searchViewed())
            analytics.track(.productListViewed(source: "search", resultCount: browseViewModel.filteredProducts.count))
            hasTrackedSearchView = true
        }
        .onReceive(productStore.$products) { products in
            let activeProducts = products.filter { $0.status == .active }.sorted { $0.createdAt > $1.createdAt }
            browseViewModel.updateProducts(activeProducts)
            recommendationsViewModel.updateProducts(activeProducts)
        }
        .onChange(of: browseViewModel.query) { _, newValue in
            let trimmedQuery = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            analytics.track(.searchQueryChanged(length: trimmedQuery.count, hasQuery: !trimmedQuery.isEmpty))
        }
        .onChange(of: browseViewModel.filteredProducts.map(\.id)) { _, _ in
            analytics.track(.productListViewed(source: "search", resultCount: browseViewModel.filteredProducts.count))
        }
        .navigationDestination(item: $selectedProduct) { product in
            ProductDetailView(product: product)
        }
    }
    private func toggleFavorite(for product: Product) {
        productStore.toggleFavorite(for: product)
        browseViewModel.toggleFavorite(for: product)
        recommendationsViewModel.toggleFavorite(for: product)
        analytics.track(.favoriteToggled(
            productID: product.id,
            isFavorite: !product.isFavorite,
            source: "search"
        ))
    }
}
