//
//  ImpactView.swift
//  Recyclability
//

import SwiftUI
import UIKit

struct ImpactView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedEntry: HistoryEntry?
    @State private var searchText: String = ""

    private var recycledEntries: [HistoryEntry] {
        history.entries.filter { $0.recycleStatus == .recycled }
    }

    private var filteredRecycledEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recycledEntries }
        return recycledEntries.filter { entry in
            [
                entry.item,
                entry.material,
                entry.bin,
                entry.notes
            ].joined(separator: " ").lowercased().contains(query)
        }
    }

    private var recycledCount: Int {
        recycledEntries.count
    }

    private var totalCarbonSavedKg: Double {
        recycledEntries.reduce(0) { partial, entry in
            partial + max(0, entry.carbonSavedKg)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Impact")
                        .font(AppType.display(30))
                        .foregroundStyle(.primary)

                    ImpactCarbonStatsRow(
                        recycledCount: recycledCount,
                        totalCarbonSavedKg: totalCarbonSavedKg
                    )
                    ImpactSearchBar(text: $searchText)

                    if recycledEntries.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "leaf")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(AppTheme.accentGradient)

                            Text("No recycled items yet")
                                .font(AppType.title(18))
                                .foregroundStyle(.primary)

                            Text("Add an item to Bin, then mark it as recycled to track your impact here.")
                                .font(AppType.body(14))
                                .foregroundStyle(.primary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .staticCard(cornerRadius: 24)
                    } else if filteredRecycledEntries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(.primary.opacity(0.75))
                            Text("No matching recycled items")
                                .font(AppType.title(16))
                                .foregroundStyle(.primary)
                            Text("Try a different search term.")
                                .font(AppType.body(13))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(22)
                        .staticCard(cornerRadius: 24)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(filteredRecycledEntries) { entry in
                                ImpactCarbonCard(entry: entry) {
                                    selectedEntry = entry
                                }
                            }
                        }
                    }

                    if !auth.isSignedIn {
                        Text("Sign in to sync your recycled impact across devices.")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.65))
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 120)
            }
        }
        .sheet(item: $selectedEntry) { entry in
            ImpactCarbonDetailView(entry: entry)
        }
    }
}

private struct ImpactSearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.7))
            TextField("Search recycled items", text: $text)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(.primary)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ImpactCarbonStatsRow: View {
    let recycledCount: Int
    let totalCarbonSavedKg: Double

    var body: some View {
        HStack(spacing: 10) {
            ImpactCarbonStatCard(title: "Recycled", value: "\(recycledCount)")
            ImpactCarbonStatCard(title: "CO2e Saved", value: formatCarbon(totalCarbonSavedKg))
        }
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg", clamped)
        }
        return String(format: "%.1f kg", clamped)
    }
}

private struct ImpactCarbonStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.55))

            Text(value)
                .font(AppType.title(18))
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .liquidGlassBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ImpactCarbonCard: View {
    let entry: HistoryEntry
    let onTap: () -> Void
    private static let contentRowMinHeight: CGFloat = 96
    private let statusColor = Color(red: 0.18, green: 0.86, blue: 0.52)

    var body: some View {
        let itemTitle = cleanedImpactValue(entry.item) ?? "Recycled item"
        let materialText = cleanedImpactValue(entry.material)
        let binText = cleanedImpactValue(entry.bin)

        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 8) {
                ImpactCarbonThumbnail(entry: entry)
                Text("\(max(1, entry.scanCount))")
                    .font(AppType.title(20))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(width: 64, alignment: .top)
            .frame(minHeight: Self.contentRowMinHeight, alignment: .top)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(itemTitle)
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .layoutPriority(1)
                    Text("Recycled")
                        .font(AppType.body(11))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                if materialText != nil || binText != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        if let materialText {
                            Text(materialText)
                                .font(AppType.body(13))
                                .foregroundStyle(.primary.opacity(0.75))
                                .lineLimit(1)
                        }

                        if let binText {
                            AddressLinkText(
                                text: binText,
                                font: AppType.body(13),
                                color: .primary.opacity(0.75),
                                lineLimit: 1
                            )
                        }
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(formatImpactDate(entry.date))
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.6))
                    Spacer(minLength: 8)
                    Text(formatCarbon(entry.carbonSavedKg))
                        .font(AppType.body(11))
                        .foregroundStyle(statusColor.opacity(0.92))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(minHeight: Self.contentRowMinHeight, alignment: .topLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(statusColor.opacity(0.9), lineWidth: 2)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg CO2e", clamped)
        }
        return String(format: "%.1f kg CO2e", clamped)
    }
}

private struct ImpactCarbonThumbnail: View {
    let entry: HistoryEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)

            if let image = loadHistoryImageForImpact(path: entry.localImagePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Image(systemName: entry.source == .text ? "text.alignleft" : "photo")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct ImpactCarbonDetailView: View {
    let entry: HistoryEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let itemTitle = cleanedImpactValue(entry.item) ?? "Recycled item"
        let materialText = cleanedImpactValue(entry.material)
        let binText = cleanedImpactValue(entry.bin)
        let notesText = cleanedImpactNotes(entry.notes)
        let materialBinLine: String? = {
            if let materialText, let binText { return "\(materialText) • \(binText)" }
            return materialText ?? binText
        }()

        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(itemTitle)
                            .font(AppType.display(28))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 32, height: 32)
                                .liquidGlassButton(in: Circle(), interactive: true)
                        }
                        .buttonStyle(.plain)
                    }

                    if let image = loadHistoryImageForImpact(path: entry.localImagePath) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                            )
                            .staticCard(cornerRadius: 22)
                    }

                    HistoryDetailInfoCard(
                        title: itemTitle,
                        statusText: "Recycled",
                        statusColor: AppTheme.mint,
                        materialBinText: materialBinLine,
                        notesText: notesText,
                        carbonSavedText: formatCarbon(entry.carbonSavedKg),
                        carbonSavedColor: AppTheme.mint,
                        metaText: nil,
                        dateText: formatImpactDate(entry.date)
                    )
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 100)
            }
        }
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg CO2e", clamped)
        }
        return String(format: "%.1f kg CO2e", clamped)
    }
}

private func loadHistoryImageForImpact(path: String?) -> UIImage? {
    guard let path, !path.isEmpty else { return nil }
    if let image = UIImage(contentsOfFile: path) {
        return image
    }

    let fileName = URL(fileURLWithPath: path).lastPathComponent
    guard !fileName.isEmpty else { return nil }

    let fileManager = FileManager.default
    if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let docsCandidate = docs
            .appendingPathComponent("impact-images", isDirectory: true)
            .appendingPathComponent(fileName)
        if let image = UIImage(contentsOfFile: docsCandidate.path) {
            return image
        }
    }

    if let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        let supportCandidate = support
            .appendingPathComponent("ReVive", isDirectory: true)
            .appendingPathComponent("impact-images", isDirectory: true)
            .appendingPathComponent(fileName)
        if let image = UIImage(contentsOfFile: supportCandidate.path) {
            return image
        }
    }

    return nil
}

private func formatImpactDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func cleanedImpactValue(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let normalized = trimmed.lowercased()
    if ["unknown", "n/a", "na", "none", "null", "-"].contains(normalized) {
        return nil
    }
    return trimmed
}

private func cleanedImpactNotes(_ raw: String) -> String? {
    guard let text = cleanedImpactValue(raw) else { return nil }
    if text.caseInsensitiveCompare("No special prep.") == .orderedSame {
        return nil
    }
    return text
}

#Preview {
    ImpactView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
