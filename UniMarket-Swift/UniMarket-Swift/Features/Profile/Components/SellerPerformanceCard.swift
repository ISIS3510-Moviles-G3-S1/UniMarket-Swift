//
//  SellerPerformanceCard.swift
//  UniMarket-Swift
//

import SwiftUI

struct SellerPerformanceCard: View {
    let soldCount: Int
    let feedbackMessage: String
    let selectedPeriod: ProfileViewModel.SalesPeriod
    let onPeriodChange: (ProfileViewModel.SalesPeriod) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Seller performance feedback")
                        .font(.poppinsSemiBold(14))
                        .foregroundStyle(AppTheme.primaryText)

                    Text("Real-time feedback based on sold listings.")
                        .font(.poppinsRegular(11))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Spacer()
            }

            Divider()

            // Period picker
            Menu {
                ForEach(ProfileViewModel.SalesPeriod.allCases, id: \.self) { period in
                    Button {
                        onPeriodChange(period)
                    } label: {
                        if period == selectedPeriod {
                            Label(period.rawValue, systemImage: "checkmark")
                        } else {
                            Text(period.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(selectedPeriod.rawValue)
                        .font(.poppinsSemiBold(13))
                        .foregroundStyle(AppTheme.accent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.accent.opacity(0.1))
                )
            }

            // Sold count + label
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text("\(soldCount)")
                    .font(.poppinsBold(44))
                    .foregroundStyle(AppTheme.primaryText)

                Text("items sold")
                    .font(.poppinsRegular(13))
                    .foregroundStyle(AppTheme.secondaryText)
                    .padding(.bottom, 4)
            }

            // Period label
            Text("Period: \(selectedPeriod.rawValue)")
                .font(.poppinsRegular(11))
                .foregroundStyle(AppTheme.secondaryText)

            Divider()

            // Feedback message
            Text(feedbackMessage)
                .font(.poppinsRegular(12))
                .foregroundStyle(AppTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppTheme.cardBackground)
                .shadow(color: .black.opacity(0.08), radius: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}
