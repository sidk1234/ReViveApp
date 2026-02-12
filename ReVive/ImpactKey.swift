//
//  ImpactKey.swift
//  Recyclability
//

import Foundation

enum ImpactKey {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func dayKey(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func itemKey(item: String, material: String, bin: String) -> String {
        let tokens = tokenSet(item: item, material: material)
        if tokens.isEmpty { return "unknown" }
        return tokens.sorted().joined(separator: "-")
    }

    static func tokenSet(item: String, material: String, includeMaterial: Bool = true) -> Set<String> {
        var tokens = tokenize(item)
        let materialToken = normalizedMaterial(material)
        if materialToken != "unknown" {
            tokens.remove(materialToken)
            if includeMaterial {
                tokens.insert(materialToken)
            }
        }
        return tokens
    }

    static func similarityTokenSet(item: String, material: String) -> Set<String> {
        let tokens = tokenSet(item: item, material: material, includeMaterial: false)
        if tokens.isEmpty {
            return tokenSet(item: item, material: material, includeMaterial: true)
        }
        return tokens
    }

    static func normalizedMaterial(_ material: String) -> String {
        let trimmed = material.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "unknown" }
        if trimmed.contains("unknown") { return "unknown" }
        return trimmed
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func areSimilarTokens(_ lhs: Set<String>, _ rhs: Set<String>) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        let intersection = lhs.intersection(rhs).count
        let union = lhs.union(rhs).count
        let jaccard = Double(intersection) / Double(union)
        let minCount = min(lhs.count, rhs.count)
        if minCount <= 2 {
            return intersection >= 1 && jaccard >= 0.34
        }
        let required = min(2, minCount)
        return intersection >= required && jaccard >= 0.5
    }

    private static func tokenize(_ text: String) -> Set<String> {
        let stopwords: Set<String> = [
            "a", "an", "the", "and", "or", "of", "for", "with", "without",
            "in", "on", "at", "to", "from", "by", "into", "over", "under",
            "this", "that", "these", "those", "item", "recyclable", "recycling"
        ]
        let cleaned = text.lowercased()
        let parts = cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let tokens = parts.compactMap { raw -> String? in
            guard !raw.isEmpty else { return nil }
            guard !stopwords.contains(raw) else { return nil }
            if raw.count > 3, raw.hasSuffix("s") {
                return String(raw.dropLast())
            }
            return raw
        }
        return Set(tokens)
    }
}
