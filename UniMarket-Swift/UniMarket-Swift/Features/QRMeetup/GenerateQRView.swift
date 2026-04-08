//
//  GenerateQRView.swift
//  UniMarket-Swift
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct GenerateQRView: View {
    let listingId: String
    let sellerId: String

    @Environment(\.dismiss) private var dismiss

    private var qrImage: Image {
        let payload = "{\"listingId\":\"\(listingId)\",\"sellerId\":\"\(sellerId)\"}"
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"

        guard
            let output = filter.outputImage
        else { return Image(systemName: "xmark.circle") }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return Image(systemName: "xmark.circle")
        }
        return Image(uiImage: UIImage(cgImage: cgImage))
    }

    var body: some View {
        ZStack {
            AppTheme.background.ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Pickup QR Code")
                        .font(.poppinsBold(22))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Show this to the buyer to confirm the meetup.")
                        .font(.poppinsRegular(13))
                        .foregroundStyle(AppTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }

                qrImage
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
                    Text("Listing ID")
                        .font(.poppinsRegular(11))
                        .foregroundStyle(AppTheme.secondaryText)
                    Text(listingId)
                        .font(.poppinsSemiBold(13))
                        .foregroundStyle(AppTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

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
}
