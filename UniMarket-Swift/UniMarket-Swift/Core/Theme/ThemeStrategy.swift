//
//  AnalysisError.swift
//  UniMarket-Swift
//
//  Created by Joseph Linares on 05/04/26.
//

import SwiftUI

/// STRATEGY PATTERN - Abstract Strategy
/// Defines the interface all theme strategies must implement.
/// New strategies (e.g. BatterySaver, AmbientLight) can be added
/// without modifying any existing code.
protocol ThemeStrategy {
    /// The ColorScheme this strategy applies (light or dark)
    func getColorScheme() -> ColorScheme

    /// Whether this strategy should be active at the given moment
    func isActive(for date: Date) -> Bool

    /// Human-readable name for debugging or UI display
    var name: String { get }
}
