//
//  LeaderboardView.swift
//  Recyclability
//

import SwiftUI

struct LeaderboardView: View {
    var onGoToAccount: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var store: LeaderboardStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var hasRequestedInitialLoad = false
    @State private var hasCompletedInitialLoad = false
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            GeometryReader { pageGeo in
                VStack(alignment: .leading, spacing: 16) {
                    Text("Leaderboard")
                        .font(AppType.display(30))
                        .foregroundStyle(.primary)

                    Text("Top recyclers ranked by total CO2e saved.")
                        .font(AppType.body(16))
                        .foregroundStyle(.primary.opacity(0.7))

                    LeaderboardAccountRow(onGoToAccount: onGoToAccount)

                    if let authError = auth.displayErrorMessage, !authError.isEmpty {
                        Text(authError)
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                    }

                    ZStack {
                        leaderboardBodyContent
                            .opacity(contentOpacity)

                        LeaderboardLoadingPlaceholder()
                            .opacity(shouldShowInitialLoadingOverlay ? 1 : 0)
                            .allowsHitTesting(false)
                    }
                    .animation(.easeOut(duration: 0.56), value: shouldShowInitialLoadingOverlay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, AppLayout.pageHorizontalPadding(for: pageGeo.size.width))
                .padding(.top, AppLayout.pageTopPadding(for: pageGeo.size.width))
                .padding(.bottom, 0)
                .adaptivePageFrame(width: pageGeo.size.width)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .onAppear {
            if hasCompletedInitialLoad {
                contentOpacity = 1
            }
            hasRequestedInitialLoad = true
            if isInitialLoadReadyForReveal {
                revealInitialContentIfNeeded(animated: false)
            }
        }
        .onChange(of: isInitialLoadReadyForReveal) { _, isReady in
            guard isReady else { return }
            revealInitialContentIfNeeded(animated: true)
        }
    }

    @ViewBuilder
    private var leaderboardBodyContent: some View {
        if let error = store.errorMessage {
            Text(error)
                .font(AppType.body(13))
                .foregroundStyle(.primary.opacity(0.7))
        } else if store.entries.isEmpty {
            VStack {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(AppTheme.accentGradient)
                    Text("No leaderboard data yet")
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                    Text("Sign in and start scanning to appear here.")
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.7))
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .staticCard(cornerRadius: 26)
                Spacer()
            }
        } else {
            ZStack(alignment: .topTrailing) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(rank: index + 1, entry: entry)
                        }
                    }
                    .padding(.top, 4)
                }

                if store.isLoading {
                    ProgressView()
                        .tint(.primary)
                        .padding(8)
                        .background(Circle().fill(.ultraThinMaterial))
                        .padding(.top, 4)
                }
            }
        }
    }

    private var shouldShowInitialLoadingOverlay: Bool {
        !hasCompletedInitialLoad
    }

    private var isInitialLoadReadyForReveal: Bool {
        hasRequestedInitialLoad && store.hasLoadedAtLeastOnce
    }

    private func revealInitialContentIfNeeded(animated: Bool) {
        guard !hasCompletedInitialLoad else { return }
        hasCompletedInitialLoad = true
        if animated {
            withAnimation(.easeOut(duration: 0.56)) {
                contentOpacity = 1
            }
            return
        }
        contentOpacity = 1
    }
}

private struct LeaderboardLoadingPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.primary)
            Text("Loading leaderboard...")
                .font(AppType.body(13))
                .foregroundStyle(.primary.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
        .staticCard(cornerRadius: 22)
    }
}

private struct LeaderboardRow: View {
    let rank: Int
    let entry: LeaderboardEntry

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(rank)")
                .font(AppType.title(14))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName ?? "Recycler")
                    .font(AppType.title(16))
                    .foregroundStyle(.primary)

                let scans = entry.totalScans ?? 0
                let recycled = entry.recyclableCount ?? 0
                Text("\(recycled) recyclable • \(scans) scans")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.7))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatCarbon(entry.totalCarbonSavedKg))
                    .font(AppType.title(18))
                    .foregroundStyle(AppTheme.mint)
                Text("CO2e")
                    .font(AppType.body(11))
                    .foregroundStyle(.primary.opacity(0.62))
            }
        }
        .padding(16)
        .staticCard(cornerRadius: 20)
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg", clamped)
        }
        return String(format: "%.1f kg", clamped)
    }
}

private struct LeaderboardAccountRow: View {
    let onGoToAccount: () -> Void
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if !auth.isSignedIn {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sign in to appear on the leaderboard.")
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
                        tint: AppTheme.mint
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .staticCard(cornerRadius: 20)
        }
    }
}

#Preview {
    LeaderboardView()
        .environmentObject(AuthStore())
        .environmentObject(LeaderboardStore())
}
