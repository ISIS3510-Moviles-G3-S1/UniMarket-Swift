import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore
import Kingfisher

@MainActor
final class ProductStore: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let service: ProductService
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var imagePrefetcher: ImagePrefetcher?
    private var savedProductIDs: Set<String> = []

    init(service: ProductService? = nil) {
        self.service = service ?? ProductService.shared
        Task { await loadSavedItems() }
        startListening()
    }

    deinit {
        listener?.remove()
        imagePrefetcher?.stop()
    }

    var activeProducts: [Product] {
        products
            .filter { $0.status == .active }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func myListings(for userID: String?) -> [Product] {
        guard let userID else { return [] }
        return products
            .filter { $0.sellerId == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func browseProducts(excludingUserID userID: String?) -> [Product] {
        guard let userID, !userID.isEmpty else { return activeProducts }
        return activeProducts.filter { $0.sellerId != userID }
    }

    func prefetchImages(for products: [Product]) {
        let urls = products
            .flatMap { $0.imageURLs }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(12)
            .compactMap { URL(string: $0) }

        guard !urls.isEmpty else { return }

        imagePrefetcher?.stop()
        imagePrefetcher = ImagePrefetcher(urls: Array(urls))
        imagePrefetcher?.start()
    }

    func toggleFavorite(for product: Product) {
        guard let index = products.firstIndex(where: { $0.id == product.id }) else { return }
        products[index].isFavorite.toggle()

        let isSaved = products[index].isFavorite
        if isSaved {
            savedProductIDs.insert(product.id)
        } else {
            savedProductIDs.remove(product.id)
        }

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("users").document(uid)
        Task {
            do {
                if isSaved {
                    try await ref.updateData(["savedItems": FieldValue.arrayUnion([product.id])])
                } else {
                    try await ref.updateData(["savedItems": FieldValue.arrayRemove([product.id])])
                }
            } catch { }
        }
    }

    func createProduct(input: CreateProductInput) async throws -> Product {
        try await service.createProduct(input: input)
    }

    func updateProduct(_ product: Product) async throws {
        try await service.updateProduct(product)
    }

    func deleteProduct(_ product: Product) async throws {
        try await service.deleteProduct(product)
    }

    func loadSavedItems() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            let ids = doc.data()?["savedItems"] as? [String] ?? []
            savedProductIDs = Set(ids)
            applySavedState()
        } catch { }
    }

    /// Applies pre-fetched saved item IDs (typically from LoginBootstrapper) so
    /// the favorites state lights up without a second Firestore round-trip.
    func applySavedItemIDs(_ ids: [String]) {
        savedProductIDs = Set(ids)
        applySavedState()
    }

    private func applySavedState() {
        for index in products.indices {
            products[index].isFavorite = savedProductIDs.contains(products[index].id)
        }
    }

    private func startListening() {
        isLoading = true
        listener?.remove()
        listener = service.observeProducts { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let products):
                    self.products = products
                    self.applySavedState()
                    self.errorMessage = nil
                    self.prefetchImages(for: products)
                case .failure(let error):
                    self.errorMessage = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }
}
