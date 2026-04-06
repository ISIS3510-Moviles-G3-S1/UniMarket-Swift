//
//  AppTheme.swift
//  UniMarket-Swift
//

import SwiftUI

enum AppTheme {
    // MARK: - Brand Colors (fixed, intentionally not adaptive)
    static let accent    = Color(hex: "72A08A")
    static let accentAlt = Color(hex: "B1B87D")

    // MARK: - Semantic Adaptive Colors
    // Resolved at render time by SwiftUI using the active color scheme,
    // including the one set by ThemeContext via .preferredColorScheme().
    // No @Environment(\.colorScheme) required in individual views.

    /// Page / screen background — brand light gray in light, primary system dark in dark.
    static let background    = Color(UIColor.systemGroupedBackground)

    /// Card / surface background — white in light, elevated dark gray in dark.
    static let cardBackground = Color(UIColor.secondarySystemBackground)

    /// Primary text — black in light, white in dark.
    static let primaryText   = Color(UIColor.label)

    /// Secondary text — dark gray in light, light gray in dark.
    static let secondaryText = Color(UIColor.secondaryLabel)
}

extension Font {
    static func poppinsRegular(_ size: CGFloat) -> Font {
        .custom("Poppins-Regular", size: size)
    }

    static func poppinsSemiBold(_ size: CGFloat) -> Font {
        .custom("Poppins-SemiBold", size: size)
    }

    static func poppinsBold(_ size: CGFloat) -> Font {
        .custom("Poppins-Bold", size: size)
    }
}


extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6 else {
            self.init(red: 0, green: 0, blue: 0)
            return
        }
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let red   = Double((int >> 16) & 0xFF) / 255.0
        let green = Double((int >> 8)  & 0xFF) / 255.0
        let blue  = Double( int        & 0xFF) / 255.0

        self.init(red: red, green: green, blue: blue)
    }
}
