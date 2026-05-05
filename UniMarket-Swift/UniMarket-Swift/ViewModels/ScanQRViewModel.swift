//
//  ScanQRViewModel.swift
//  UniMarket-Swift
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class ScanQRViewModel: ObservableObject {
    private let analytics = AnalyticsService.shared
    private let productID: String?
    private let source: AnalyticsSurface

    enum ScanState {
        case scanning
        case confirming(transactionId: String)
        case loading
        case confirmed
        case error(String)
    }

    @Published var scanState: ScanState = .scanning

    init(productID: String? = nil, source: AnalyticsSurface = .unknown) {
        self.productID = productID
        self.source = source
    }

    // MARK: - Scanner logic

    func handleScannedCode(_ code: String) {
        let transactionId = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transactionId.isEmpty else {
            scanState = .error("Invalid QR code. Please scan a valid UniMarket QR.")
            return
        }
        scanState = .confirming(transactionId: transactionId)
    }

    func resetScanning() {
        scanState = .scanning
    }

    // MARK: - Firestore confirmation

    func confirmPickup(transactionId: String) async {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            scanState = .error("You must be logged in to confirm a pickup.")
            return
        }

        scanState = .loading

        do {
            let db = Firestore.firestore()
            let ref = db.collection("meetup_transactions").document(transactionId)
            let doc = try await ref.getDocument()

            guard doc.exists, let data = doc.data() else {
                scanState = .error("Transaction not found. Please scan a valid QR.")
                return
            }
            guard let buyerId = data["buyerId"] as? String, buyerId == currentUID else {
                scanState = .error("This QR was not generated for your account.")
                return
            }
            guard let status = data["status"] as? String, status == "pending" else {
                scanState = .error("This transaction has already been confirmed or is no longer valid.")
                return
            }

            try await ref.updateData([
                "status": "confirmed",
                "confirmedAt": FieldValue.serverTimestamp()
            ])

            let resolvedProductID = (data["listingId"] as? String) ?? productID ?? "unknown"
            analytics.track(.purchaseConfirmed(
                productID: resolvedProductID,
                transactionID: transactionId,
                source: source.rawValue
            ))
            scanState = .confirmed
        } catch {
            scanState = .error(error.localizedDescription)
        }
    }
}
