import SwiftUI

struct HistoryDetailInfoCard: View {
    let title: String?
    let statusText: String?
    let statusColor: Color
    let materialBinText: String?
    let notesText: String?
    let carbonSavedText: String
    let carbonSavedColor: Color
    let metaText: String?
    let dateText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = cleaned(title) {
                Text(title)
                    .font(AppType.title(20))
                    .foregroundStyle(.primary)
            }

            if let statusText = cleaned(statusText) {
                Text(statusText)
                    .font(AppType.body(13))
                    .foregroundStyle(statusColor)
            }

            if let materialBinText = cleaned(materialBinText) {
                AddressLinkText(
                    text: materialBinText,
                    font: AppType.body(14),
                    color: .primary.opacity(0.75)
                )
            }

            if let notesText = cleaned(notesText) {
                AddressLinkText(
                    text: notesText,
                    font: AppType.body(14),
                    color: .primary.opacity(0.85)
                )
            }

            Text("Carbon saved: \(carbonSavedText)")
                .font(AppType.body(13))
                .foregroundStyle(carbonSavedColor)

            if let metaText = cleaned(metaText) {
                Text(metaText)
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.72))
            }

            Text(dateText)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.6))

            Text("Results are AI-generated. Please proceed with caution.")
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.6))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 20)
    }

    private func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
