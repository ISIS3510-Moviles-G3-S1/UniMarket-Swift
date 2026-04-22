//
//  SustainabilityImpact.swift
//  UniMarket-Swift
//

import Foundation

enum ImpactCategory: String, CaseIterable, Codable {
    case jacket
    case jeans
    case dress
    case top
    case shoes
    case accessory
    case other

    // (water liters, CO2 kg, waste kg) per reused garment.
    // Figures are rough per-garment averages drawn from UNEP / Ellen MacArthur / WWF textile footprint references.
    var coefficients: (water: Int, co2: Double, waste: Double) {
        switch self {
        case .jacket:    return (9_000, 25.0, 1.0)
        case .jeans:     return (7_500, 33.0, 0.8)
        case .dress:     return (2_500, 10.0, 0.4)
        case .top:       return (2_700,  7.0, 0.25)
        case .shoes:     return (8_000, 14.0, 0.8)
        case .accessory: return (1_500,  4.0, 0.2)
        case .other:     return (3_000,  8.0, 0.4)
        }
    }

    var displayName: String {
        switch self {
        case .jacket:    return "Jackets & outerwear"
        case .jeans:     return "Jeans & pants"
        case .dress:     return "Dresses & skirts"
        case .top:       return "Tops & shirts"
        case .shoes:     return "Shoes"
        case .accessory: return "Accessories"
        case .other:     return "Other garments"
        }
    }

    static func infer(from tags: [String], title: String) -> ImpactCategory {
        let haystack = (tags + [title]).map { $0.lowercased() }.joined(separator: " ")

        let buckets: [(ImpactCategory, [String])] = [
            (.jacket,    ["jacket", "coat", "blazer", "hoodie", "sweater", "cardigan", "parka"]),
            (.jeans,     ["jeans", "pants", "trousers", "shorts", "denim"]),
            (.dress,     ["dress", "skirt", "gown"]),
            (.shoes,     ["shoes", "sneaker", "boot", "sandal", "heels"]),
            (.accessory, ["bag", "purse", "hat", "scarf", "belt", "accessory"]),
            (.top,       ["shirt", "tee", "t-shirt", "tshirt", "blouse", "top", "polo", "tank"])
        ]

        for (category, keywords) in buckets {
            if keywords.contains(where: { haystack.contains($0) }) {
                return category
            }
        }
        return .other
    }
}

struct SustainabilityImpact: Codable, Equatable {
    let itemsReused: Int
    let waterLiters: Int
    let co2Kg: Double
    let wasteKg: Double
    let categoryCounts: [ImpactCategory: Int]

    static let empty = SustainabilityImpact(
        itemsReused: 0, waterLiters: 0, co2Kg: 0, wasteKg: 0, categoryCounts: [:]
    )

    static func calculate(from reusedItems: [Product]) -> SustainabilityImpact {
        guard !reusedItems.isEmpty else { return .empty }

        var water = 0
        var co2 = 0.0
        var waste = 0.0
        var counts: [ImpactCategory: Int] = [:]

        for item in reusedItems {
            let category = ImpactCategory.infer(from: item.tags, title: item.title)
            let c = category.coefficients
            water += c.water
            co2 += c.co2
            waste += c.waste
            counts[category, default: 0] += 1
        }

        return SustainabilityImpact(
            itemsReused: reusedItems.count,
            waterLiters: water,
            co2Kg: co2,
            wasteKg: waste,
            categoryCounts: counts
        )
    }

    // MARK: - Human-relatable comparisons

    // An average shower uses ~65 L (8-min at 8 L/min).
    var showerEquivalents: Int { waterLiters / 65 }

    // A passenger car emits ~0.17 kg CO2 per km driven (EPA average).
    var drivingKilometersAvoided: Int { Int((co2Kg / 0.17).rounded()) }

    // A mature tree absorbs ~21 kg CO2/year.
    var treeYearsEquivalent: Double { (co2Kg / 21.0 * 10).rounded() / 10 }

    var topCategories: [(category: ImpactCategory, count: Int)] {
        categoryCounts
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { (category: $0.key, count: $0.value) }
    }
}
