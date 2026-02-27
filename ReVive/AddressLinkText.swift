import SwiftUI
import Foundation
import UIKit

struct AddressLinkText: View {
    let text: String
    let font: Font
    var color: Color = .primary
    var lineLimit: Int? = nil

    var body: some View {
        Text(AddressLinkFormatter.makeAttributedText(text, color: color))
            .font(font)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .tint(.blue)
    }
}

private enum AddressLinkFormatter {
    static func makeAttributedText(_ text: String, color: Color) -> AttributedString {
        let normalizedText = normalizeLocationLabels(in: text)
        let base = NSMutableAttributedString(
            string: normalizedText,
            attributes: [.foregroundColor: UIColor(color)]
        )

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else {
            return AttributedString(base)
        }

        let matches = detector.matches(
            in: normalizedText,
            options: [],
            range: NSRange(location: 0, length: (normalizedText as NSString).length)
        )
        for match in matches {
            let nsText = normalizedText as NSString
            let address = nsText.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
            guard let mapsURL = URL(string: "http://maps.apple.com/?q=\(encodedAddress)") else { continue }

            base.addAttributes(
                [
                    .link: mapsURL,
                    .foregroundColor: UIColor.systemBlue,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ],
                range: match.range
            )
        }

        return AttributedString(base)
    }

    private static func normalizeLocationLabels(in text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else {
            return text
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let normalizedLines = lines.map { line -> String in
            let lineText = String(line)
            let range = NSRange(lineText.startIndex..., in: lineText)
            guard let match = detector.firstMatch(in: lineText, options: [], range: range) else {
                return lineText
            }
            let nsLine = lineText as NSString
            let address = nsLine.substring(with: match.range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { return lineText }
            let prefix = nsLine.substring(to: match.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
            if prefix.hasSuffix(":") || prefix.lowercased().hasPrefix("nearest disposal:") {
                return lineText
            }
            return "Nearest Disposal: \(address)"
        }
        return normalizedLines.joined(separator: "\n")
    }
}
