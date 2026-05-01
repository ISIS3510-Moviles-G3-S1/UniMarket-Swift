import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// Eventual-connectivity coordinator for PendingFavoritesStore. Replays each
// queued op against the current user's Firestore `savedItems` array on every
// offline → online transition.
//
// Observability
// ─────────────
// `pendingProductIDs` is a Set so views can in O(1) decide whether to render
// the "syncing" affordance on a heart icon. `pendingCount` drives the inbox
// banner aggregation. `lastSyncedAt` lets the UI distinguish "never synced"
// from "synced a moment ago" without leaking timer state.
@MainActor
final class PendingFavoritesSyncer: ObservableObject {
    static let shared = PendingFavoritesSyncer()

    @Published private(set) var pendingProductIDs: Set<String> = []
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var isDraining: Bool = false

    private let db = Firestore.firestore()
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

    func enqueue(productID: String, kind: PendingFavoriteOp.Kind) async {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        let work = Task.detached(priority: .utility) {
            try await PendingFavoritesStore.shared.enqueue(
                productID: productID,
                userID: userID,
                kind: kind
            )
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
            (try? await PendingFavoritesStore.shared.allPending(for: userID)) ?? []
        }
        let pending = await listTask.value
        guard !pending.isEmpty else { return }

        let userRef = db.collection("users").document(userID)
        for op in pending {
            do {
                switch op.kind {
                case .save:
                    try await userRef.updateData([
                        "savedItems": FieldValue.arrayUnion([op.productID])
                    ])
                case .unsave:
                    try await userRef.updateData([
                        "savedItems": FieldValue.arrayRemove([op.productID])
                    ])
                }
                let removeTask = Task.detached(priority: .utility) {
                    try await PendingFavoritesStore.shared.remove(
                        productID: op.productID,
                        userID: userID
                    )
                }
                _ = try await removeTask.value
            } catch {
                let bumpTask = Task.detached(priority: .utility) {
                    try await PendingFavoritesStore.shared.bumpRetry(
                        productID: op.productID,
                        userID: userID,
                        error: error
                    )
                }
                _ = try? await bumpTask.value
                break
            }
        }
    }

    // MARK: - Snapshot refresh

    private func refreshSnapshot() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            pendingCount = 0
            pendingProductIDs = []
            return
        }
        let task = Task.detached(priority: .utility) {
            (try? await PendingFavoritesStore.shared.allPending(for: userID)) ?? []
        }
        let all = await task.value
        pendingCount = all.count
        pendingProductIDs = Set(all.map(\.productID))
    }
}
