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
        let base = NSMutableAttributedString(
            string: text,
            attributes: [.foregroundColor: UIColor(color)]
        )

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) else {
            return AttributedString(base)
        }

        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length))
        for match in matches {
            let nsText = text as NSString
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
}
