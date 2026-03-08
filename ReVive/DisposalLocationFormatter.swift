import Foundation

enum DisposalLocationFormatter {
    static func formatted(_ raw: String?) -> String? {
        guard var cleaned = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }
        if let pipe = cleaned.firstIndex(of: "|") {
            cleaned = String(cleaned[cleaned.index(after: pipe)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = cleaned.range(of: "(?i)nearest disposal\\s*:\\s*", options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = cleaned.range(of: "(?i)nearest drop[- ]off\\s*:\\s*", options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let range = cleaned.range(of: "(?i)drop[- ]off\\s*:\\s*", options: .regularExpression) {
            cleaned = String(cleaned[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    static func extractedFromRawPayload(_ rawPayload: String?) -> String? {
        guard let rawPayload else { return nil }
        let trimmed = rawPayload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(AIRecyclingResult.self, from: data),
           let decodedLocation = normalized(decoded.disposalLocation) {
            return decodedLocation
        }

        let pattern = #"(?i)"(?:disposal_location|disposalLocation|location)"\s*:\s*"((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range),
              match.numberOfRanges > 1,
              let capturedRange = Range(match.range(at: 1), in: trimmed) else { return nil }

        let escaped = String(trimmed[capturedRange])
        let unescaped = escaped
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\r")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
        return normalized(unescaped)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
