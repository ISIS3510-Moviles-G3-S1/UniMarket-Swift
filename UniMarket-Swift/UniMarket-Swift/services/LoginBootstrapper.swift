import Foundation
import FirebaseFirestore

// Post-login warmup that runs three independent Firestore reads in parallel and
// returns their results combined as a tuple. Demonstrates the "task results"
// pattern: each async let launches an independent child coroutine, all run
// concurrently, and the parent awaits their typed return values together.
//
// Without this, the same data is fetched lazily and serially across multiple
// stores — currentUser is fetched by SessionManager.fetchUser, savedItems by
// ProductStore.loadSavedItems (which re-reads the same user document!), and
// the last-listing date is computed only after products stream in. Bootstrapping
// in parallel cuts the post-login warmup from ~3 sequential round-trips to one
// concurrent fan-out.
enum LoginBootstrapper {

    struct Result {
        let user: User?
        let savedItemIDs: [String]
        let lastListingDate: Date?
    }

    static func bootstrap(uid: String) async -> Result {
        async let user: User?            = fetchUserProfile(uid: uid)
        async let savedIDs: [String]     = fetchSavedItemIDs(uid: uid)
        async let lastListing: Date?     = fetchLastListingDate(uid: uid)

        let (resolvedUser, ids, date) = await (user, savedIDs, lastListing)
        return Result(user: resolvedUser, savedItemIDs: ids, lastListingDate: date)
    }

    private static func fetchUserProfile(uid: String) async -> User? {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            return try snap.data(as: User.self)
        } catch {
            return nil
        }
    }

    private static func fetchSavedItemIDs(uid: String) async -> [String] {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            return snap.data()?["savedItems"] as? [String] ?? []
        } catch {
            return []
        }
    }

    private static func fetchLastListingDate(uid: String) async -> Date? {
        let db = Firestore.firestore()
        do {
            let snap = try await db.collection("listings")
                .whereField("sellerId", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            return (snap.documents.first?.data()["createdAt"] as? Timestamp)?.dateValue()
        } catch {
            return nil
        }
    }
}
