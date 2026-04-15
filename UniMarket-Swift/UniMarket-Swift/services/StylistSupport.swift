import Foundation

enum StylistPromptBuilder {
    static func makeSearchPrompt(prompt: String, photoContext: String?) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        if let photoContext, !photoContext.isEmpty, trimmedPrompt.isEmpty {
            return photoContext
        }

        guard let photoContext, !photoContext.isEmpty else {
            return trimmedPrompt
        }

        return "\(trimmedPrompt) \(photoContext)"
    }
}

enum StylistCatalogMatcher {
    static func suggestedProducts(for prompt: String, in catalog: [Product]) -> [Product] {
        guard !catalog.isEmpty else { return [] }

        let tokens = Set(
            prompt
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
        )

        let ranked = catalog
            .filter { $0.status == .active }
            .map { product in
                let haystack = "\(product.title) \(product.description) \(product.tags.joined(separator: " ")) \(product.conditionTag)".lowercased()
                let score = tokens.reduce(into: 0) { partialResult, token in
                    if haystack.contains(token) {
                        partialResult += 1
                    }
                }
                return (product, score)
            }
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.createdAt > $1.0.createdAt
                }
                return $0.1 > $1.1
            }

        let matched = ranked.filter { $0.1 > 0 }.map(\.0)
        if !matched.isEmpty {
            return matched
        }

        return Array(ranked.prefix(3).map(\.0))
    }
}
