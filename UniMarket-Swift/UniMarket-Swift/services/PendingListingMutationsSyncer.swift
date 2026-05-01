import Foundation
import Combine
import FirebaseAuth

// Eventual-connectivity coordinator for PendingListingMutationsStore. Replays
// each queued update / delete through ProductService on every offline → online
// transition.
//
// Observability
// ─────────────
// `pendingProductIDs` lets list cells in O(1) decide whether to render the
// "Pending sync" pill. `pendingCount` drives the aggregate banner.
@MainActor
final class PendingListingMutationsSyncer: ObservableObject {
    static let shared = PendingListingMutationsSyncer()

    @Published private(set) var pendingProductIDs: Set<String> = []
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isDraining: Bool = false

    private var connectivityCancellable: AnyCancellable?
    private var sessionCancellable: AnyCancellable?

    private init() {}

    func bind(to monitor: NetworkMonitor) {
        connectivityCancellable = monitor.$isConnected
            .removeDuplicates()
            .sink { [weak self] connected in
                guard let self else { return }
                if connected {
                    Task { await self.drain() }
                }
            }
        sessionCancellable = SessionManager.shared.$user
            .map { $0?.uid }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshSnapshot() }
            }
        Task { await refreshSnapshot() }
    }

    func resumeIfNeeded() async {
        await refreshSnapshot()
        if NetworkMonitor.shared.isConnected {
            await drain()
        }
    }

    func enqueueUpdate(product: Product) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let work = Task.detached(priority: .utility) {
            try await PendingListingMutationsStore.shared.enqueueUpdate(product: product, userID: userID)
        }
        _ = try? await work.value
        await refreshSnapshot()
    }

    func enqueueDelete(product: Product) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let work = Task.detached(priority: .utility) {
            try await PendingListingMutationsStore.shared.enqueueDelete(product: product, userID: userID)
        }
        _ = try? await work.value
        await refreshSnapshot()
    }

    func isPending(_ productID: String) -> Bool {
        pendingProductIDs.contains(productID)
    }

    func drain() async {
        guard !isDraining else { return }
        guard let userID = Auth.auth().currentUser?.uid else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        isDraining = true
        defer {
            isDraining = false
            Task { await refreshSnapshot() }
        }

        let listTask = Task.detached(priority: .utility) {
            (try? await PendingListingMutationsStore.shared.allPending(for: userID)) ?? []
        }
        let pending = await listTask.value
        guard !pending.isEmpty else { return }

        for record in pending {
            do {
                try await replay(record: record, userID: userID)
                let removeTask = Task.detached(priority: .utility) {
                    try await PendingListingMutationsStore.shared.remove(
                        productID: record.productID,
                        userID: userID
                    )
                }
                _ = try await removeTask.value
            } catch {
                let bumpTask = Task.detached(priority: .utility) {
                    try await PendingListingMutationsStore.shared.bumpRetry(
                        productID: record.productID,
                        userID: userID,
                        error: error
                    )
                }
                _ = try? await bumpTask.value
                break
            }
        }
    }

    // MARK: - Replay

    private func replay(record: PendingListingMutation, userID: String) async throws {
        switch record.kind {
        case .update:
            let product = Product(
                id: record.productID,
                sellerId: userID,
                title: record.snapshot.title,
                price: record.snapshot.price,
                description: "",
                soldAt: record.snapshot.soldAt,
                imageURLs: record.snapshot.imageURLs,
                status: ProductStatus(rawValue: record.snapshot.statusRaw) ?? .active
            )
            try await ProductService.shared.updateProduct(product)
        case .delete:
            let product = Product(
                id: record.productID,
                sellerId: userID,
                title: record.snapshot.title,
                price: record.snapshot.price,
                imageURLs: record.snapshot.imageURLs,
                status: ProductStatus(rawValue: record.snapshot.statusRaw) ?? .active
            )
            try await ProductService.shared.deleteProduct(product)
        }
    }

    private func refreshSnapshot() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            pendingCount = 0
            pendingProductIDs = []
            return
        }
        let task = Task.detached(priority: .utility) {
            (try? await PendingListingMutationsStore.shared.allPending(for: userID)) ?? []
        }
        let all = await task.value
        pendingCount = all.count
        pendingProductIDs = Set(all.map(\.productID))
    }
}
