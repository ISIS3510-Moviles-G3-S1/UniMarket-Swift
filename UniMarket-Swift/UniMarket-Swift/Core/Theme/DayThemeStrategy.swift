//
//  AnalysisError.swift
//  UniMarket-Swift
//
//  Created by Joseph Linares on 05/04/26.
//

import SwiftUI

/// STRATEGY PATTERN - Concrete Strategy (Day)
/// Active from 6:00 AM to 6:59 PM — applies light color scheme.
struct DayThemeStrategy: ThemeStrategy {
    let name = "Day Theme"

    private static let startHour = 6   // 6:00 AM
    private static let endHour   = 19  // 7:00 PM (exclusive)

    func getColorScheme() -> ColorScheme { .light }

    func isActive(for date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= Self.startHour && hour < Self.endHour
    }
}
