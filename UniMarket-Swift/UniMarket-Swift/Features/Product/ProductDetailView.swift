//
//  ProductDetailView.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

struct ProductDetailView: View {
    private let analytics = AnalyticsService.shared
    @EnvironmentObject private var chatStore: ChatStore
    @EnvironmentObject private var productStore: ProductStore

    @StateObject private var vm: ProductDetailViewModel
    @State private var editingProduct: Product?
    @State private var chatConversationID: String?
    @State private var isStartingChat = false

    private let onProductUpdated: ((Product) -> Void)?

    init(product: Product, isOwnListing: Bool = false, onProductUpdated: ((Product) -> Void)? = nil) {
        _vm = StateObject(wrappedValue: ProductDetailViewModel(product: product, isOwnListing: isOwnListing))
        self.onProductUpdated = onProductUpdated
    }

    var body: some View {
        ZStack {
            AppTheme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    imageHeader

                    Text(vm.title)
                        .font(.poppinsBold(28))
                        .foregroundStyle(AppTheme.primaryText)

                    HStack {
                        Text("$\(vm.price)")
                            .font(.poppinsBold(24))
                            .foregroundStyle(AppTheme.accent)

                        Spacer()

                        Text(vm.conditionText)
                            .font(.poppinsSemiBold(12))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(AppTheme.accentAlt.opacity(0.45))
                            .clipShape(Capsule())
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seller")
                            .font(.poppinsSemiBold(14))
                            .foregroundStyle(AppTheme.secondaryText)

                        HStack(spacing: 8) {
                            Text(vm.sellerName)
                                .font(.poppinsSemiBold(16))
                                .foregroundStyle(AppTheme.primaryText)

                            if let rating = vm.rating {
                                Text("•")
                                    .foregroundStyle(AppTheme.secondaryText)
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                                Text(String(format: "%.1f", rating))
                                    .font(.poppinsRegular(14))
                                    .foregroundStyle(AppTheme.secondaryText)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.poppinsSemiBold(16))
                            .foregroundStyle(AppTheme.primaryText)

                        Text(vm.description)
                            .font(.poppinsRegular(15))
                            .foregroundStyle(AppTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !vm.tags.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Tags")
                                .font(.poppinsSemiBold(16))
                                .foregroundStyle(AppTheme.primaryText)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(vm.tags, id: \.self) { tag in
                                    Text(tag.capitalized)
                                        .font(.poppinsSemiBold(12))
                                        .foregroundStyle(AppTheme.primaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(AppTheme.accentAlt.opacity(0.35))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    actionButtons
                }
                .padding(16)
                .padding(.bottom, 110)
            }
        }
        .navigationTitle("Product Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            analytics.track(.productDetailViewed(
                productID: vm.id,
                price: vm.price,
                condition: vm.conditionText,
                isOwnListing: vm.isOwnListing
            ))
        }
        .onReceive(productStore.$products) { products in
            guard let updatedProduct = products.first(where: { $0.id == vm.id }) else { return }
            vm.sync(with: updatedProduct)
        }
        .sheet(item: $editingProduct) { product in
            EditListingView(
                product: product,
                onCancel: { editingProduct = nil },
                onSave: { updated in
                    Task {
                        try? await productStore.updateProduct(updated)
                        await MainActor.run {
                            vm.applyProductUpdate(updated)
                            onProductUpdated?(updated)
                            editingProduct = nil
                        }
                    }
                }
            )
        }
        .sheet(item: chatRouteBinding) { route in
            NavigationStack {
                ChatThreadView(conversationID: route.id)
                    .environmentObject(chatStore)
            }
        }
    }

    // MARK: - Image header

    private var imageHeader: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.cardBackground)
                .frame(height: 280)

            if vm.imageURLs.isEmpty {
                Image(systemName: "photo")
                    .font(.poppinsSemiBold(72))
                    .foregroundStyle(AppTheme.secondaryText)
                    .scaledToFit()
                    .frame(height: 280)
                    .frame(width: 300)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                TabView {
                    ForEach(vm.imageURLs, id: \.self) { imageURL in
                        CachedRemoteImageView(urlString: imageURL, cacheKey: imageURL)
                            .frame(height: 280)
                            .frame(width: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(height: 280)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private var actionButtons: some View {
        if vm.isOwnListing {
            Button("Edit Listing") {
                editingProduct = vm.editableProduct()
            }
            .font(.poppinsSemiBold(16))
            .foregroundStyle(AppTheme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.accentAlt)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            HStack(spacing: 12) {
                // MARK: Favorite button
                Button {
                    let nextFavoriteState = !vm.isFavorite
                    if let product = productStore.products.first(where: { $0.id == vm.id }) {
                        productStore.toggleFavorite(for: product)
                    } else {
                        vm.toggleFavorite()
                    }
                    analytics.track(.favoriteToggled(
                        productID: vm.id,
                        isFavorite: nextFavoriteState,
                        source: "product_detail"
                    ))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: vm.isFavorite ? "heart.fill" : "heart")
                        Text(vm.isFavorite ? "Saved" : "Save")
                    }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                // MARK: Message button
                Button {
                    guard !isStartingChat else { return }
                    isStartingChat = true
                    Task {
                        do {
                            let listing = ChatMessage.ListingSnapshot(
                                listingId: vm.id,
                                title: vm.title,
                                price: vm.price,
                                imagePath: vm.imageURLs.first ?? ""
                            )
                            let conversationID = try await chatStore.startOrGetConversation(
                                sellerID: vm.sellerId,
                                listing: listing
                            )
                            await MainActor.run {
                                chatConversationID = conversationID
                                isStartingChat = false
                            }
                        } catch {
                            print("DEBUG: failed to start conversation \(error.localizedDescription)")
                            await MainActor.run { isStartingChat = false }
                        }
                    }
                } label: {
                    Group {
                        if isStartingChat {
                            ProgressView().tint(AppTheme.primaryText)
                        } else {
                            Text("Message")
                        }
                    }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    // MARK: - Chat sheet routing

    private struct ChatRoute: Identifiable {
        let id: String
    }

    private var chatRouteBinding: Binding<ChatRoute?> {
        Binding<ChatRoute?>(
            get: {
                guard let id = chatConversationID else { return nil }
                return ChatRoute(id: id)
            },
            set: { newValue in
                chatConversationID = newValue?.id
            }
        )
    }
}
