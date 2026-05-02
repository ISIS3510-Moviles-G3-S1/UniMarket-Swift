import Foundation
import Combine
import FirebaseAuth

// Connectivity-driven coordinator for PendingListingsStore.
// See EvCon.md §1 for the lifecycle and drain policy.
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
        // Refresh on user change so the banner reacts to sign-out / account switch.
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
        // Drop the record on enqueue failure (e.g. disk full); caller already showed an error UI.
        do { _ = try await work.value } catch { return }
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
                // Stop on first failure — next connectivity flip retries.
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
