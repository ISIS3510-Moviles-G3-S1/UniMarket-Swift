import Foundation
import Combine
import FirebaseAuth

// Eventual-connectivity coordinator for the file-backed PendingListingsStore.
//
// Lifecycle
// ─────────
// 1. UniMarket_SwiftApp calls `bind(to:)` once at launch with the shared
//    NetworkMonitor. The syncer subscribes to `isConnected` and refreshes
//    its observable count.
// 2. UploadProductViewModel.postProduct enqueues a record when the device is
//    offline, or when the live publish path fails with a network-shaped error.
// 3. Whenever connectivity transitions offline → online, `drain()` fires:
//    each pending record is materialized and replayed through
//    ProductService.createProduct (which itself uploads images in parallel).
// 4. On launch, `resumeIfNeeded()` runs the same drain so anything queued in
//    a previous session goes through as soon as the user is online.
//
// Observability
// ─────────────
// `pendingCount` is @Published so MainTabView can show a banner. `isDraining`
// is published so the banner can show a "syncing now…" state.
@MainActor
final class PendingListingsSyncer: ObservableObject {
    static let shared = PendingListingsSyncer()

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
        // Refresh count whenever the signed-in user changes so the banner stays
        // accurate after sign-out or account switching without a connectivity flip.
        sessionCancellable = SessionManager.shared.$user
            .map { $0?.uid }
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshCount() }
            }
        Task { await refreshCount() }
    }

    func resumeIfNeeded() async {
        await refreshCount()
        if NetworkMonitor.shared.isConnected {
            await drain()
        }
    }

    func enqueue(input: CreateProductInput, userID: String) async {
        let work = Task.detached(priority: .utility) {
            try await PendingListingsStore.shared.enqueue(input: input, userID: userID)
        }
        do {
            _ = try await work.value
        } catch {
            // If enqueue itself fails (no disk space, sandbox issue) we drop the
            // record rather than crashing — caller already showed an error UI.
            return
        }
        await refreshCount()
    }

    func drain() async {
        guard !isDraining else { return }
        guard let userID = Auth.auth().currentUser?.uid else { return }
        guard NetworkMonitor.shared.isConnected else { return }

        isDraining = true
        defer {
            isDraining = false
            Task { await refreshCount() }
        }

        let listTask = Task.detached(priority: .utility) {
            try await PendingListingsStore.shared.allPending(for: userID)
        }
        let pending: [PendingListing]
        do {
            pending = try await listTask.value
        } catch {
            return
        }

        for record in pending {
            do {
                let materializeTask = Task.detached(priority: .utility) {
                    try await PendingListingsStore.shared.materialize(record)
                }
                let input = try await materializeTask.value
                _ = try await ProductService.shared.createProduct(input: input)
                let removeTask = Task.detached(priority: .utility) {
                    try await PendingListingsStore.shared.remove(pendingID: record.pendingID, userID: userID)
                }
                _ = try await removeTask.value
            } catch {
                let bumpTask = Task.detached(priority: .utility) {
                    try await PendingListingsStore.shared.bumpRetry(
                        pendingID: record.pendingID,
                        userID: userID,
                        error: error
                    )
                }
                _ = try? await bumpTask.value
                // Stop draining on first failure — most failures are network or
                // auth issues that will affect every remaining record. The next
                // connectivity flip will retry.
                break
            }
        }
    }

    private func refreshCount() async {
        guard let userID = Auth.auth().currentUser?.uid else {
            pendingCount = 0
            return
        }
        let countTask = Task.detached(priority: .utility) {
            await PendingListingsStore.shared.count(for: userID)
        }
        pendingCount = await countTask.value
    }
}
