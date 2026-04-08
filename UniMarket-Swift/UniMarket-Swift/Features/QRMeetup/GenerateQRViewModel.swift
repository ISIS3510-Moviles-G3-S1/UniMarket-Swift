//
//  GenerateQRViewModel.swift
//  UniMarket-Swift
//

import Foundation
import FirebaseFirestore

@MainActor
final class GenerateQRViewModel: ObservableObject {

    enum ViewState {
        case idle
        case loading
        case generated(transactionId: String)
        case error(String)
    }

    @Published var buyerUID = ""
    @Published var viewState: ViewState = .idle

    let listingId: String
    let sellerId: String
    let listingStatus: ProductStatus

    init(listingId: String, sellerId: String, listingStatus: ProductStatus) {
        self.listingId = listingId
        self.sellerId = sellerId
        self.listingStatus = listingStatus
    }

    var isListingActive: Bool { listingStatus == .active }

    // MARK: - QR generation

    func generateQR() async {
        let trimmedUID = buyerUID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUID.isEmpty else {
            viewState = .error("Please enter the buyer's User ID.")
            return
        }
        guard isListingActive else {
            viewState = .error("This listing is not active and cannot generate a QR.")
            return
        }

        viewState = .loading

        do {
            let db = Firestore.firestore()

            // Validate buyer exists in Firestore
            let buyerDoc = try await db.collection("users").document(trimmedUID).getDocument()
            guard buyerDoc.exists else {
                viewState = .error("No user found with that ID. Please verify the buyer's UID.")
                return
            }

            // Create pending meetup_transaction
            let ref = db.collection("meetup_transactions").document()
            try await ref.setData([
                "listingId": listingId,
                "sellerId": sellerId,
                "buyerId": trimmedUID,
                "status": "pending",
                "createdAt": FieldValue.serverTimestamp(),
                "confirmedAt": NSNull()
            ])

            viewState = .generated(transactionId: ref.documentID)
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }
}
