//
//  GenerateQRView.swift
//  UniMarket-Swift
//
//  Created by Joseph Linares on 17/03/26.
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import FirebaseFirestore

struct GenerateQRView: View {
    let listingId: String
    let sellerId: String
    let listingStatus: ProductStatus

    @Environment(\.dismiss) private var dismiss
    @State private var buyerUID = ""
    @State private var viewState: ViewState = .idle

    enum ViewState {
        case idle
        case loading
        case generated(transactionId: String)
        case error(String)
    }

    private var isListingActive: Bool { listingStatus == .active }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            switch viewState {
            case .idle, .error:
                inputView
            case .loading:
                loadingView
            case .generated(let transactionId):
                generatedView(transactionId: transactionId)
            }
        }
        .navigationTitle("Generate Meetup QR")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Input view

    private var inputView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Status warning if listing is not active
                if !isListingActive {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Only active listings can generate a QR. This listing is currently \(listingStatus.rawValue.lowercased()).")
                            .font(.poppinsRegular(13))
                            .foregroundStyle(AppTheme.primaryText)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.orange.opacity(0.1))
                    )
                }

                Text("Create a pending meetup transaction and show this QR to the buyer at pickup.")
                    .font(.poppinsRegular(13))
                    .foregroundStyle(AppTheme.secondaryText)

                // Buyer UID field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Buyer User ID")
                        .font(.poppinsSemiBold(13))
                        .foregroundStyle(AppTheme.secondaryText)

                    TextField("e.g. SzYQPjOGb5Vcz...", text: $buyerUID)
                        .font(.poppinsRegular(14))
                        .foregroundStyle(AppTheme.primaryText)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppTheme.cardBackground)
                                .shadow(color: .black.opacity(0.06), radius: 4)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Text("Use the buyer's Firebase UID so only that buyer can confirm.")
                        .font(.poppinsRegular(11))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                // Error message
                if case .error(let message) = viewState {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.poppinsRegular(13))
                            .foregroundStyle(.red)
                    }
                }

                // Generate button
                Button {
                    Task { await generateQR() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode")
                        Text("Generate QR Code")
                    }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(isListingActive ? AppTheme.accent : AppTheme.secondaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!isListingActive)
            }
            .padding(20)
        }
    }

    // MARK: - Loading view

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(AppTheme.accent)
            Text("Validating and creating transaction...")
                .font(.poppinsRegular(13))
                .foregroundStyle(AppTheme.secondaryText)
        }
    }

    // MARK: - Generated view

    private func generatedView(transactionId: String) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.accent)
                    Text("Transaction created")
                        .font(.poppinsSemiBold(14))
                        .foregroundStyle(AppTheme.primaryText)
                }

                qrImage(for: transactionId)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 240, height: 240)
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(AppTheme.cardBackground)
                            .shadow(color: .black.opacity(0.08), radius: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    Text("Transaction ID")
                        .font(.poppinsRegular(11))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(transactionId)
                        .font(.poppinsSemiBold(12))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("Show this QR to the buyer at pickup. They will scan it to confirm the transaction.")
                    .font(.poppinsRegular(12))
                    .foregroundStyle(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)

                Button("Done") { dismiss() }
                    .font(.poppinsSemiBold(16))
                    .foregroundStyle(AppTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(AppTheme.accentAlt)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(24)
        }
    }

    // MARK: - QR generation

    private func qrImage(for transactionId: String) -> Image {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(transactionId.utf8)
        filter.correctionLevel = "M"
        guard
            let output = filter.outputImage,
            let cgImage = context.createCGImage(
                output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
                from: output.transformed(by: CGAffineTransform(scaleX: 10, y: 10)).extent
            )
        else { return Image(systemName: "xmark.circle") }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    // MARK: - Firestore logic

    private func generateQR() async {
        let trimmedUID = buyerUID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUID.isEmpty else {
            viewState = .error("Please enter the buyer's User ID.")
            return
        }
        guard isListingActive else {
            viewState = .error("This listing is not active and cannot generate a QR.")
            return
        }

        await MainActor.run { viewState = .loading }

        do {
            let db = Firestore.firestore()

            // Validate buyer exists in Firestore
            let buyerDoc = try await db.collection("users").document(trimmedUID).getDocument()
            guard buyerDoc.exists else {
                await MainActor.run {
                    viewState = .error("No user found with that ID. Please verify the buyer's UID.")
                }
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

            await MainActor.run { viewState = .generated(transactionId: ref.documentID) }
        } catch {
            await MainActor.run { viewState = .error(error.localizedDescription) }
        }
    }
}
