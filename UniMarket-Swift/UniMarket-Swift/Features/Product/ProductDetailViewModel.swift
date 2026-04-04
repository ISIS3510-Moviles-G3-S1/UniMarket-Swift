//
//  ProductDetailViewModel.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import Foundation
import Combine

final class ProductDetailViewModel: ObservableObject {
    let id: String
    let sellerName: String
    let rating: Double?
    let isOwnListing: Bool

    @Published var title: String
    @Published var price: Int
    @Published var conditionText: String
    @Published var isFavorite: Bool
    @Published var imageURLs: [String]
    @Published var description: String
    @Published var tags: [String]

    private var sourceProduct: Product?

    init(product: Product, isOwnListing: Bool = false) {
        self.id = product.id
        self.title = product.title
        self.price = product.price
        self.imageURLs = Self.normalizedImageURLs(for: product)
        self.sellerName = product.sellerName
        self.conditionText = isOwnListing ? product.status.rawValue : product.conditionTag
        self.rating = isOwnListing ? nil : product.rating
        self.isFavorite = product.isFavorite
        self.tags = product.tags
        self.isOwnListing = isOwnListing
        self.description = product.description.isEmpty
            ? "Pre-loved item in \(product.conditionTag.lowercased()) condition. Perfect for campus life and sustainable fashion."
            : product.description
        self.sourceProduct = isOwnListing ? product : nil
    }

    func toggleFavorite() {
        guard !isOwnListing else { return }
        isFavorite.toggle()
    }

    func sync(with product: Product) {
        title = product.title
        price = product.price
        imageURLs = Self.normalizedImageURLs(for: product)
        conditionText = isOwnListing ? product.status.rawValue : product.conditionTag
        isFavorite = product.isFavorite
        tags = product.tags
        description = product.description.isEmpty
            ? "Pre-loved item in \(product.conditionTag.lowercased()) condition. Perfect for campus life and sustainable fashion."
            : product.description

        if isOwnListing {
            sourceProduct = product
        }
    }

    func editableProduct() -> Product? {
        sourceProduct
    }

    func applyProductUpdate(_ updated: Product) {
        sync(with: updated)
    }

    private static func normalizedImageURLs(for product: Product) -> [String] {
        let urls = product.imageURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !urls.isEmpty {
            return urls
        }

        if let fallback = product.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
            return [fallback]
        }

        return []
    }
}
