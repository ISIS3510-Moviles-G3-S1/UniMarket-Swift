//
//  SustainabilityImpactCard.swift
//  UniMarket-Swift
//

import SwiftUI

struct SustainabilityImpactCard: View {
    let impact: SustainabilityImpact
    let message: String
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            HStack(spacing: 10) {
                ImpactStatTile(
                    value: formattedWater,
                    unit: waterUnit,
                    label: "water spared",
                    systemImage: "drop.fill",
                    tint: .blue
                )
                ImpactStatTile(
                    value: formattedCO2,
                    unit: "kg CO2",
                    label: "emissions avoided",
                    systemImage: "leaf.fill",
                    tint: .green
                )
                ImpactStatTile(
                    value: formattedWaste,
                    unit: "kg",
                    label: "waste diverted",
                    systemImage: "arrow.3.trianglepath",
                    tint: AppTheme.accent
                )
            }

            Divider()

            insightBlock
        }
        .padding(14)
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

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Your sustainability impact")
                    .font(.poppinsSemiBold(14))
                    .foregroundStyle(AppTheme.primaryText)

                Text("\(impact.itemsReused) items given a second life")
                    .font(.poppinsRegular(11))
                    .foregroundStyle(AppTheme.secondaryText)
            }

            Spacer()
        }
    }

    private var insightBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                Text("Eco insight")
                    .font(.poppinsSemiBold(12))
                    .foregroundStyle(AppTheme.accent)
            }

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Reading your numbers...")
                        .font(.poppinsRegular(12))
                        .foregroundStyle(AppTheme.secondaryText)
                }
            } else {
                Text(message.isEmpty
                     ? "Sell your first item to unlock a personalized insight."
                     : message)
                    .font(.poppinsRegular(12))
                    .foregroundStyle(AppTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Formatting

    private var formattedWater: String {
        let liters = impact.waterLiters
        if liters >= 1000 {
            return String(format: "%.1f", Double(liters) / 1000)
        }
        return "\(liters)"
    }

    private var waterUnit: String {
        impact.waterLiters >= 1000 ? "kL water" : "L water"
    }

    private var formattedCO2: String {
        impact.co2Kg >= 10 ? "\(Int(impact.co2Kg.rounded()))" : String(format: "%.1f", impact.co2Kg)
    }

    private var formattedWaste: String {
        impact.wasteKg >= 10 ? "\(Int(impact.wasteKg.rounded()))" : String(format: "%.1f", impact.wasteKg)
    }
}

private struct ImpactStatTile: View {
    let value: String
    let unit: String
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)

            Text(value)
                .font(.poppinsBold(20))
                .foregroundStyle(AppTheme.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(unit)
                .font(.poppinsSemiBold(10))
                .foregroundStyle(AppTheme.secondaryText)

            Text(label)
                .font(.poppinsRegular(9))
                .foregroundStyle(AppTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.background)
        )
    }
}
