//
//  HomeViewModel.swift
//  UniMarket-Swift
//
//  Created by Mariana Pineda on 1/03/26.
//

import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    enum SeasonalMoment: CaseIterable {
        case spring
        case summer
        case fall
        case winter

        var title: String {
            switch self {
            case .spring:
                return "For This Spring"
            case .summer:
                return "For This Summer"
            case .fall:
                return "For This Fall"
            case .winter:
                return "For This Winter"
            }
        }

        var subtitle: String {
            switch self {
            case .spring:
                return "Light layers, fresh tones, and easy campus staples."
            case .summer:
                return "Breathable picks and bright essentials for warm days."
            case .fall:
                return "Cozy textures and transitional pieces for cooler weather."
            case .winter:
                return "Warm layers and heavier pieces for colder weeks."
            }
        }

        var iconName: String {
            switch self {
            case .spring:
                return "camera.macro"
            case .summer:
                return "sun.max.fill"
            case .fall:
                return "leaf.fill"
            case .winter:
                return "snowflake"
            }
        }

        var accentKeyword: String {
            switch self {
            case .spring:
                return "spring"
            case .summer:
                return "summer"
            case .fall:
                return "fall"
            case .winter:
                return "winter"
            }
        }
    }

#if DEBUG
    enum SeasonSelection: String, CaseIterable, Identifiable {
        case automatic
        case spring
        case summer
        case fall
        case winter

        var id: String { rawValue }

        var label: String {
            switch self {
            case .automatic:
                return "Auto"
            case .spring:
                return "Spring"
            case .summer:
                return "Summer"
            case .fall:
                return "Fall"
            case .winter:
                return "Winter"
            }
        }

        var season: SeasonalMoment? {
            switch self {
            case .automatic:
                return nil
            case .spring:
                return .spring
            case .summer:
                return .summer
            case .fall:
                return .fall
            case .winter:
                return .winter
            }
        }
    }

    @Published var debugSeasonSelection: SeasonSelection = .automatic
#endif

    func season(for date: Date = Date()) -> SeasonalMoment {
        let month = Calendar.current.component(.month, from: date)

        switch month {
        case 3...5:
            return .spring
        case 6...8:
            return .summer
        case 9...11:
            return .fall
        default:
            return .winter
        }
    }

    func currentSeason(on date: Date = Date()) -> SeasonalMoment {
#if DEBUG
        if let override = debugSeasonSelection.season {
            return override
        }
#endif
        return season(for: date)
    }

    func productsForCurrentSeason(from products: [Product], on date: Date = Date()) -> [Product] {
        let currentSeason = currentSeason(on: date)

        let filtered = products.filter { product in
            let normalizedTags = product.tags.map { $0.lowercased() }
            return normalizedTags.contains(currentSeason.accentKeyword) || normalizedTags.contains("all-season")
        }

        if !filtered.isEmpty {
            return Array(filtered.prefix(6))
        }

        return Array(products.prefix(6))
    }
}
