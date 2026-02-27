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
        // Do not merge entries based only on non-specific placeholders.
        let genericTokens: Set<String> = [
            "unknown", "unkown", "unknow", "unidentified", "item", "object", "thing"
        ]
        let meaningfulOverlap = lhs.intersection(rhs).subtracting(genericTokens)
        guard !meaningfulOverlap.isEmpty else { return false }

        let intersection = lhs.intersection(rhs).count
        let minCount = min(lhs.count, rhs.count)
        if minCount >= 3 {
            let overlap = Double(intersection) / Double(minCount)
            if intersection >= 3, overlap >= 0.7 {
                return true
            }
        }
        let union = lhs.union(rhs).count
        let jaccard = Double(intersection) / Double(union)
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
            "this", "that", "these", "those", "item", "recyclable", "recycling",
            "unknown", "unkown", "unknow", "unidentified", "object", "objects", "thing"
        ]
        let measurementTokens: Set<String> = [
            "oz", "floz", "fl", "ml", "l", "ltr", "liter", "liters",
            "g", "kg", "lb", "lbs", "ct", "count", "pack", "pk",
            "qt", "gal", "cm", "mm", "inch", "inches"
        ]
        let typoCorrections: [String: String] = [
            "stailnless": "stainless",
            "stainles": "stainless",
            "stainlss": "stainless",
            "vacum": "vacuum",
            "vaccum": "vacuum",
            "vaccuum": "vacuum",
            "insualted": "insulated",
            "insulted": "insulated",
            // Common model wording variance for powered appliances.
            "electronic": "electric",
            "electronics": "electric"
        ]

        let cleaned = text.lowercased()
        let parts = cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted)
        let tokens = parts.compactMap { raw -> String? in
            guard !raw.isEmpty else { return nil }
            guard !stopwords.contains(raw) else { return nil }
            if raw.allSatisfy(\.isNumber) { return nil }
            if measurementTokens.contains(raw) { return nil }

            let corrected = typoCorrections[raw] ?? raw
            if corrected.count > 3, corrected.hasSuffix("s") {
                return String(corrected.dropLast())
            }
            return corrected
        }
        return Set(tokens)
    }
}
