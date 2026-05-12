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
    @State private var showOptInToast = false
    @State private var showOptOutConfirmNote = false

    @AppStorage("revive.leaderboard.hasSeenOptIn") private var hasSeenOptIn: Bool = false
    @AppStorage("revive.leaderboard.optedIn") private var optedIn: Bool = true

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            GeometryReader { pageGeo in
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Leaderboard")
                                .font(AppType.display(30))
                                .foregroundStyle(.primary)

                            Text("Top recyclers ranked by total CO2e saved.")
                                .font(AppType.body(16))
                                .foregroundStyle(.primary.opacity(0.7))
                        }

                        Spacer()

                        if auth.isSignedIn {
                            Button {
                                toggleOptIn()
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: optedIn ? "trophy.fill" : "trophy")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(optedIn ? AppTheme.mint : .primary.opacity(0.45))
                                    Text(optedIn ? "Ranked" : "Hidden")
                                        .font(AppType.body(10))
                                        .foregroundStyle(optedIn ? AppTheme.mint : .primary.opacity(0.45))
                                }
                                .frame(width: 52, height: 52)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 2)
                        }
                    }

                    if showOptOutConfirmNote {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13, weight: .medium))
                            Text("You can rejoin anytime using the trophy toggle above.")
                                .font(AppType.body(13))
                        }
                        .foregroundStyle(.primary.opacity(0.75))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .staticCard(cornerRadius: 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }

                    if !optedIn && auth.isSignedIn {
                        HStack(spacing: 10) {
                            Image(systemName: "eye.slash")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.6))
                            Text("You are not on the leaderboard.")
                                .font(AppType.body(13))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .staticCard(cornerRadius: 14)
                    }

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

            if showOptInToast {
                LeaderboardOptInOverlay(
                    onJoin: {
                        withAnimation(.easeInOut(duration: 0.2)) { showOptInToast = false }
                        optedIn = true
                        Task { await auth.updateLeaderboardVisibility(true) }
                    },
                    onDecline: {
                        withAnimation(.easeInOut(duration: 0.2)) { showOptInToast = false }
                        optedIn = false
                        Task { await auth.updateLeaderboardVisibility(false) }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            showOptOutConfirmNote = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                showOptOutConfirmNote = false
                            }
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
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
            if auth.isSignedIn && !hasSeenOptIn {
                hasSeenOptIn = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showOptInToast = true
                    }
                }
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
        } else if visibleEntries.isEmpty && store.hasLoadedAtLeastOnce {
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
                        ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                            LeaderboardRow(
                                rank: index + 1,
                                entry: entry,
                                isCurrentUser: entry.userId == auth.user?.id
                            )
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

    private var visibleEntries: [LeaderboardEntry] {
        guard auth.isSignedIn, !optedIn, let userID = auth.user?.id else {
            return store.entries
        }
        return store.entries.filter { $0.userId != userID }
    }

    private func toggleOptIn() {
        let newValue = !optedIn
        withAnimation(.easeInOut(duration: 0.18)) {
            optedIn = newValue
        }
        Task { await auth.updateLeaderboardVisibility(newValue) }
        if !newValue {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                showOptOutConfirmNote = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.easeOut(duration: 0.3)) { showOptOutConfirmNote = false }
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

private struct LeaderboardOptInOverlay: View {
    let onJoin: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(AppTheme.mint)
                    Text("Join the Leaderboard?")
                        .font(AppType.title(18))
                        .foregroundStyle(.primary)
                }

                Text("Compete with other recyclers and show off your CO2e savings. You can opt out anytime.")
                    .font(AppType.body(14))
                    .foregroundStyle(.primary.opacity(0.8))

                HStack(spacing: 10) {
                    Button("No thanks") {
                        onDecline()
                    }
                    .font(AppType.title(14))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )

                    Button("Yes, join") {
                        onJoin()
                    }
                    .font(AppType.title(14))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        tint: AppTheme.mint
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: 360)
            .staticCard(cornerRadius: 18)
        }
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
    var isCurrentUser: Bool = false

    var body: some View {
        HStack(spacing: 14) {
            Text(rankLabel)
                .font(AppType.title(rank <= 3 ? 16 : 14))
                .foregroundStyle(rankColor)
                .lineLimit(1)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.displayName ?? "Recycler")
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                    if isCurrentUser {
                        Text("You")
                            .font(AppType.body(11))
                            .foregroundStyle(AppTheme.mint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppTheme.mint.opacity(0.15)))
                    }
                }

                let scans = entry.totalScans ?? 0
                let recycled = entry.recyclableCount ?? 0
                Text("\(recycled) recyclable · \(scans) scans")
                    .font(AppType.body(12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                Text(formatCarbon(entry.totalCarbonSavedKg))
                    .font(AppType.display(20))
                    .foregroundStyle(AppTheme.mint)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                Text("CO2e")
                    .font(AppType.body(11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .staticCard(cornerRadius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(isCurrentUser ? AppTheme.mint.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    private var rankLabel: String {
        switch rank {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "#\(rank)"
        }
    }

    private var rankColor: Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.80, blue: 0.20)
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.80)
        case 3: return Color(red: 0.80, green: 0.55, blue: 0.28)
        default: return .secondary
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
