//
//  ProductGridCard.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

struct ProductGridCard: View {
    let product: Product
    let onTapFavorite: () -> Void
    let onTapCard: () -> Void

    private var carouselImageURLs: [String] {
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
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.background)
                    .frame(height: 180)
                    .overlay(productImage)

                Text(product.conditionTag)
                    .font(.poppinsSemiBold(10))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppTheme.cardBackground.opacity(0.92))
                    .clipShape(Capsule())
                    .padding(10)

                HStack {
                    Spacer()
                    Button(action: onTapFavorite) {
                        Image(systemName: product.isFavorite ? "heart.fill" : "heart")
                            .font(.poppinsSemiBold(16))
                            .foregroundStyle(product.isFavorite ? AppTheme.accent : AppTheme.primaryText)
                            .padding(10)
                            .background(AppTheme.cardBackground.opacity(0.92))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }

            Text(product.title)
                .font(.poppinsSemiBold(14))
                .foregroundStyle(AppTheme.primaryText)
                .lineLimit(1)

            HStack {
                Text("$\(product.price)")
                    .font(.poppinsBold(15))
                    .foregroundStyle(AppTheme.primaryText)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                    Text(String(format: "%.1f", product.rating))
                        .font(.poppinsRegular(12))
                }
                .foregroundStyle(AppTheme.secondaryText)
            }

            Text(product.sellerName)
                .font(.poppinsRegular(12))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .padding(10)
        .background(AppTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTapCard()
        }
    }

    @ViewBuilder
    private var productImage: some View {
        if carouselImageURLs.isEmpty {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(AppTheme.background)
                Image(systemName: "photo")
                    .font(.poppinsSemiBold(30))
                    .foregroundStyle(AppTheme.secondaryText)
            }
            .frame(height: 180)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            TabView {
                ForEach(carouselImageURLs, id: \.self) { imageURL in
                    CachedRemoteImageView(urlString: imageURL, cacheKey: imageURL)
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .clipped()
                }
            }
            .frame(height: 180)
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }
}
