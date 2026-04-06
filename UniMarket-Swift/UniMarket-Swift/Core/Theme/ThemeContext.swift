//
//  AnalysisError.swift
//  UniMarket-Swift
//
//  Created by Joseph Linares on 05/04/26.
//

import SwiftUI
import Combine

/// STRATEGY PATTERN - Context
/// Holds a reference to the active ThemeStrategy and delegates
/// all theme decisions to it. Automatically polls every 60 seconds
/// to switch strategies when the time boundary is crossed.
final class ThemeContext: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var currentColorScheme: ColorScheme = .light
    @Published private(set) var isManualOverride: Bool = false

    // MARK: - Private Properties

    private var autoStrategies: [ThemeStrategy]
    private var currentStrategy: ThemeStrategy
    private var pollingTimer: Timer?

    // MARK: - Initialization

    init(strategies: [ThemeStrategy]? = nil) {
        self.autoStrategies = strategies ?? [
            DayThemeStrategy(),
            NightThemeStrategy()
        ]
        self.currentStrategy = Self.resolveStrategy(
            from: self.autoStrategies,
            at: Date()
        )
        self.currentColorScheme = currentStrategy.getColorScheme()
        startPolling()
    }

    deinit { stopPolling() }

    // MARK: - Public API

    /// Manually pin a specific strategy, disabling automatic switching.
    func setStrategy(_ strategy: ThemeStrategy) {
        isManualOverride = true
        stopPolling()
        applyStrategy(strategy)
    }

    /// Return to automatic time-based switching.
    func clearManualOverride() {
        isManualOverride = false
        autoSwitch()
        startPolling()
    }

    // MARK: - Private Helpers

    /// Returns the first strategy that matches the given date, or the last as fallback.
    private static func resolveStrategy(
        from strategies: [ThemeStrategy],
        at date: Date
    ) -> ThemeStrategy {
        strategies.first { $0.isActive(for: date) } ?? strategies.last!
    }

    private func startPolling() {
        stopPolling()
        pollingTimer = Timer.scheduledTimer(
            withTimeInterval: 60.0,
            repeats: true
        ) { [weak self] _ in
            guard let self, !self.isManualOverride else { return }
            self.autoSwitch()
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func autoSwitch() {
        let newStrategy = Self.resolveStrategy(from: autoStrategies, at: Date())
        // Only publish a change when the strategy type actually differs
        if type(of: newStrategy) != type(of: currentStrategy) {
            applyStrategy(newStrategy)
        }
    }

    private func applyStrategy(_ strategy: ThemeStrategy) {
        currentStrategy = strategy
        DispatchQueue.main.async {
            self.currentColorScheme = strategy.getColorScheme()
        }
    }
}
