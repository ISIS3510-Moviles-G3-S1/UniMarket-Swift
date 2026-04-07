//
//  ProfileHeaderCard.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import SwiftUI

struct ProfileHeaderCard: View {
    let displayName: String
    let memberSince: String
    let rating: Double
    let transactions: Int
    let xp: Int
    let profilePicURL: String
    let onEditImage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                CachedRemoteImageView(urlString: profilePicURL, cacheKey: profilePicURL, placeholderStyle: .profile)
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.borderColor, lineWidth: 1))

                Button(action: onEditImage) {
                    Image(systemName: "pencil.circle.fill")
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(AppTheme.accent)
                        .background(AppTheme.cardBackground.clipShape(Circle()))
                        .font(.system(size: 18))
                }
                .offset(x: 4, y: 4)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(displayName)
                    .font(.poppinsSemiBold(20))
                    .foregroundStyle(AppTheme.primaryText)

                Text("Member since \(memberSince)")
                    .font(.poppinsRegular(12))
                    .foregroundStyle(AppTheme.secondaryText)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                        Text(String(format: "%.1f", rating))
                    }
                    .font(.poppinsRegular(12))
                    .foregroundStyle(AppTheme.secondaryText)

                    Text("• \(transactions) transactions")
                        .font(.poppinsRegular(12))
                        .foregroundStyle(AppTheme.secondaryText)
                }

                Text("\(xp) XP Points")
                    .font(.poppinsSemiBold(15))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.top, 2)
            }

            Spacer()
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
}
