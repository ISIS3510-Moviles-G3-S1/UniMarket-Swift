//
//  AppTheme.swift
//  UniMarket-Swift
//

import SwiftUI

enum AppTheme {
    // MARK: - Brand Colors (Light Mode — unchanged)
    static let accent        = Color(hex: "72A08A")
    static let accentAlt     = Color(hex: "B1B87D")
    static let background    = Color(hex: "F2F2F2")
    static let primaryText   = Color.black
    static let secondaryText = Color.black.opacity(0.6)

    // MARK: - Adaptive Colors (Strategy Pattern support)
    // Use these in views that must respond to theme changes.

    /// Primary text — white in dark mode, black in light mode.
    static func adaptivePrimaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : primaryText
    }

    /// Secondary text — slightly dimmed white in dark mode.
    static func adaptiveSecondaryText(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.7) : secondaryText
    }

    /// Card / surface background — system dark gray in dark mode, white in light.
    static func adaptiveCardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : .white
    }

    /// Page background — system dark in dark mode, brand light gray in light.
    static func adaptiveBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(UIColor.systemBackground) : background
    }
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
