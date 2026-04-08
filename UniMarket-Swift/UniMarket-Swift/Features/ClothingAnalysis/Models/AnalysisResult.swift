//
//  ClothingTag.swift
//  UniMarket-Swift
//
//  Created by Joseph Linares on 17/03/26.
//

import Foundation

struct AnalysisResult: Codable {
    let category: String
    let colors: [String]
    let style: String?
    let pattern: String?
    let confidence: Double
    let processingTimeMs: Int
    let allTags: [ClothingTag]
    let timestamp: Date
    
    init(
        category: String,
        colors: [String],
        style: String?,
        pattern: String?,
        confidence: Double,
        processingTimeMs: Int,
        allTags: [ClothingTag],
        timestamp: Date = Date()
    ) {
        self.category = category
        self.colors = colors
        self.style = style
        self.pattern = pattern
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.processingTimeMs = processingTimeMs
        self.allTags = allTags
        self.timestamp = timestamp
    }
    
    var confidencePercentage: Int {
        Int(confidence * 100)
    }

    var listingDraft: AIListingDraft {
        let primaryColor = sanitizedWord(from: colors.first)
        let normalizedCategory = sanitizedWord(from: category) ?? "Clothing"
        let normalizedStyle = sanitizedWord(from: style)
        let normalizedPattern = sanitizedWord(from: pattern)

        var tags: [String] = []
        for candidate in [normalizedCategory, primaryColor, normalizedStyle, normalizedPattern] {
            guard let candidate else { continue }
            appendTag(candidate, to: &tags)
        }

        for tag in allTags {
            guard let normalized = sanitizedWord(from: tag.name) else { continue }
            appendTag(normalized, to: &tags)
            if tags.count == 8 { break }
        }

        let titleWords = [primaryColor, normalizedCategory].compactMap { $0 }
        let title = titleWords.isEmpty ? "Clothing Item" : titleWords.joined(separator: " ")

        let description: String
        if let normalizedStyle, let primaryColor, let normalizedPattern, normalizedPattern.lowercased() != "solid" {
            description = "AI detected a \(primaryColor.lowercased()) \(normalizedStyle.lowercased()) \(normalizedCategory.lowercased()) with a \(normalizedPattern.lowercased()) pattern."
        } else if let normalizedStyle, let primaryColor {
            description = "AI detected a \(primaryColor.lowercased()) \(normalizedStyle.lowercased()) \(normalizedCategory.lowercased()) for everyday wear."
        } else if let primaryColor {
            description = "AI detected a \(primaryColor.lowercased()) \(normalizedCategory.lowercased()) in a versatile style."
        } else {
            description = "AI detected a \(normalizedCategory.lowercased()) ready for a quick listing."
        }

        return AIListingDraft(
            title: title,
            description: description,
            tags: tags
        )
    }
    
    var summaryText: String {
        var summary = "✅ Analysis Complete (\(processingTimeMs)ms)\n\n"
        summary += "Category: \(category)\n"
        
        if !colors.isEmpty {
            summary += "Colors: \(colors.joined(separator: ", "))\n"
        }
        
        if let style = style {
            summary += "Style: \(style)\n"
        }
        
        if let pattern = pattern {
            summary += "Pattern: \(pattern)\n"
        }
        
        summary += "Confidence: \(confidencePercentage)%"
        
        return summary
    }

    private func sanitizedWord(from value: String?) -> String? {
        guard let value else { return nil }

        let components = value
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !$0.isEmpty }

        guard let first = components.first else { return nil }
        return first.prefix(1).uppercased() + first.dropFirst().lowercased()
    }

    private func appendTag(_ value: String, to tags: inout [String]) {
        let normalized = value.lowercased()
        guard !tags.contains(normalized) else { return }
        tags.append(normalized)
    }
}

struct AIListingDraft: Codable, Equatable {
    let title: String
    let description: String
    let tags: [String]
}
