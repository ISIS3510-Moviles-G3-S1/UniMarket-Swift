//
//  AnalysisError.swift
//  UniMarket-Swift
//
//  Created by Joseph Linares on 05/04/26.
//

import SwiftUI

/// STRATEGY PATTERN - Concrete Strategy (Night)
/// Active from 7:00 PM to 5:59 AM — applies dark color scheme.
/// Wraps across midnight: 19:00–23:59 OR 00:00–05:59.
struct NightThemeStrategy: ThemeStrategy {
    let name = "Night Theme"

    private static let nightStartHour  = 19 // 7:00 PM
    private static let morningEndHour  = 6  // 6:00 AM

    func getColorScheme() -> ColorScheme { .dark }

    func isActive(for date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= Self.nightStartHour || hour < Self.morningEndHour
    }
}
