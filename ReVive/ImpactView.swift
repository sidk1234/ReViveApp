//
//  ImpactView.swift
//  Recyclability
//

import SwiftUI
import UIKit

struct ImpactView: View {
    var onGoToAccount: () -> Void = {}
    @EnvironmentObject private var history: HistoryStore
    @State private var selectedEntry: HistoryEntry?
    @State private var headerHeight: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let scoredEntries = history.entries.filter { $0.source == .photo }
        let totalScans = scoredEntries.reduce(0) { $0 + $1.scanCount }
        let recyclableCount = scoredEntries.filter { $0.recyclable }.count
        let impactScore = recyclableCount

        ZStack(alignment: .top) {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if history.entries.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundStyle(AppTheme.accentGradient)

                            Text("No impact yet")
                                .font(AppType.title(18))
                                .foregroundStyle(.primary)

                            Text("Scan an item from the camera tab and it will appear here.")
                                .font(AppType.body(14))
                                .foregroundStyle(.primary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .staticCard(cornerRadius: 26)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(history.entries) { entry in
                                ImpactCard(entry: entry) {
                                    selectedEntry = entry
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, headerHeight + 8)
                .padding(.bottom, 120)
            }
            .ignoresSafeArea(.container, edges: .bottom)

            ImpactHeader(
                totalScans: totalScans,
                recyclableCount: recyclableCount,
                impactScore: impactScore,
                onGoToAccount: onGoToAccount
            )
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .background(
                ImpactHeaderGlass()
                    .padding(.top, -28)
                    .ignoresSafeArea(edges: .top)
            )
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: ImpactHeaderHeightKey.self, value: proxy.size.height)
                }
            )
            .zIndex(1)
        }
        .onPreferenceChange(ImpactHeaderHeightKey.self) { height in
            if headerHeight != height {
                headerHeight = height
            }
        }
        .sheet(item: $selectedEntry) { entry in
            ImpactDetailView(entry: entry)
        }
    }
}

private struct ImpactHeader: View {
    let totalScans: Int
    let recyclableCount: Int
    let impactScore: Int
    let onGoToAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Impact")
                .font(AppType.display(30))
                .foregroundStyle(.primary)

            Text("Track your scans, see your impact, and sync your progress.")
                .font(AppType.body(16))
                .foregroundStyle(.primary.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            ImpactStatsRow(
                totalScans: totalScans,
                recyclableCount: recyclableCount,
                impactScore: impactScore
            )

            Text("Recyclable counts items marked recyclable. Impact equals recyclable scans (1 point each).")
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.65))

            ImpactAccountRow(onGoToAccount: onGoToAccount)
        }
    }
}

private struct ImpactHeaderGlass: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        shape
            .fill(.ultraThinMaterial)
            .opacity(0.6)
            .liquidGlassBackground(in: shape)
            .allowsHitTesting(false)
    }
}

private struct ImpactHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > value {
            value = next
        }
    }
}

private extension View {
    func softGlassCard(cornerRadius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape.fill(.ultraThinMaterial)
                    .opacity(0.6)
            )
            .overlay(
                shape.stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .liquidGlassBackground(in: shape)
    }
}

private struct ImpactCard: View {
    let entry: HistoryEntry
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ImpactEntryThumbnail(entry: entry)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(entry.item)
                            .font(AppType.title(16))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(entry.recyclable ? "Recyclable" : "Not recyclable")
                            .font(AppType.body(12))
                            .foregroundStyle(entry.recyclable ? AppTheme.mint : Color(red: 0.92, green: 0.27, blue: 0.32))
                    }

                    Text("\(entry.material) • \(entry.bin)")
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.75))

                    Text(entry.notes)
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(formatDate(entry.date))
                            .font(AppType.body(11))
                            .foregroundStyle(.primary.opacity(0.6))
                        if entry.source == .text {
                            Text("Manual")
                                .font(AppType.body(11))
                                .foregroundStyle(.primary.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule().fill(.ultraThinMaterial)
                                )
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .staticCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }
}

private struct ImpactEntryThumbnail: View {
    let entry: HistoryEntry

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: 64, height: 64)

            if let image = loadImpactImage(path: entry.localImagePath) {
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

private func loadImpactImage(path: String?) -> UIImage? {
    guard let path, !path.isEmpty else { return nil }
    return UIImage(contentsOfFile: path)
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private struct ImpactStatsRow: View {
    let totalScans: Int
    let recyclableCount: Int
    let impactScore: Int

    var body: some View {
        HStack(spacing: 12) {
            ImpactStatCard(title: "Scans", value: "\(totalScans)")
            ImpactStatCard(title: "Recyclable", value: "\(recyclableCount)")
            ImpactStatCard(title: "Impact", value: "\(impactScore)")
        }
    }
}

private struct ImpactStatCard: View {
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
        .softGlassCard(cornerRadius: 18)
    }
}

private struct ImpactAccountRow: View {
    let onGoToAccount: () -> Void
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if auth.isSignedIn {
            Text("Signed in as \(auth.user?.displayName ?? auth.user?.email ?? "Recycler")")
                .font(AppType.body(13))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .softGlassCard(cornerRadius: 20)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to sync your impact and score.")
                    .font(AppType.body(13))
                    .foregroundStyle(.primary.opacity(0.75))

                Button {
                    onGoToAccount()
                } label: {
                    HStack {
                        Text("Go to Account")
                            .font(AppType.title(14))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                        tint: Color.white.opacity(0.7)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .softGlassCard(cornerRadius: 20)
        }
    }
}

private struct ImpactDetailView: View {
    let entry: HistoryEntry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Activity")
                            .font(AppType.display(28))
                            .foregroundStyle(.primary)
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

                    if let image = loadImpactImage(path: entry.localImagePath) {
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
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: entry.source == .text ? "text.alignleft" : "photo")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                            Text(entry.source == .text ? "Manual entry" : "No image available")
                                .font(AppType.body(13))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .staticCard(cornerRadius: 22)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(entry.item)
                            .font(AppType.title(20))
                            .foregroundStyle(.primary)

                        Text("\(entry.material) • \(entry.bin)")
                            .font(AppType.body(14))
                            .foregroundStyle(.primary.opacity(0.75))

                        Text(entry.recyclable ? "Recyclable" : "Not recyclable")
                            .font(AppType.body(13))
                            .foregroundStyle(entry.recyclable ? AppTheme.mint : Color(red: 0.92, green: 0.27, blue: 0.32))

                        Text(entry.notes)
                            .font(AppType.body(14))
                            .foregroundStyle(.primary.opacity(0.85))

                        Text(formatDate(entry.date))
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.6))

                        Text("Scanned \(entry.scanCount) time\(entry.scanCount == 1 ? "" : "s")")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))

                        if entry.source == .text {
                            Text("Manual entry - not counted toward score.")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .staticCard(cornerRadius: 20)
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 120)
            }
        }
    }
}

#Preview {
    ImpactView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
