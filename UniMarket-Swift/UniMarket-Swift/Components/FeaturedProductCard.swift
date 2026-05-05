//
//  FeaturedProductCard.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

struct FeaturedProductCard: View {
    let product: Product?

    private var carouselImageURLs: [String] {
        guard let product else { return [] }

        let urls = product.imageURLs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !urls.isEmpty { return urls }

        if let fallback = product.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines), !fallback.isEmpty {
            return [fallback]
        }

        return []
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cardBackground)
                .frame(height: 320)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.background)
                        .padding(2)
                )

            featuredImage

            if let product {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(product.price)")
                        .font(.poppinsBold(34))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("\(product.conditionTag) ✓")
                        .font(.poppinsSemiBold(14))
                        .foregroundStyle(AppTheme.primaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(AppTheme.accentAlt)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private var featuredImage: some View {
        if product != nil{
            if carouselImageURLs.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.poppinsSemiBold(36))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text("No image available")
                        .font(.poppinsRegular(13))
                        .foregroundStyle(AppTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TabView {
                    ForEach(carouselImageURLs, id: \.self) { imageURL in
                        CachedRemoteImageView(urlString: imageURL, cacheKey: imageURL)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(AppTheme.secondaryText)
                Text("Your newest listing will appear here.")
                    .font(.poppinsRegular(15))
                    .foregroundStyle(AppTheme.secondaryText)
            }
        }
    }
}
