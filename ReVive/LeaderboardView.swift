//
//  LeaderboardView.swift
//  Recyclability
//

import SwiftUI

struct LeaderboardView: View {
    var onGoToAccount: () -> Void = {}
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var store = LeaderboardStore()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text("Leaderboard")
                    .font(AppType.display(30))
                    .foregroundStyle(.primary)

                Text("Top recyclers based on verified daily impact.")
                    .font(AppType.body(16))
                    .foregroundStyle(.primary.opacity(0.7))

                LeaderboardAccountRow(onGoToAccount: onGoToAccount)

                if let authError = auth.displayErrorMessage, !authError.isEmpty {
                    Text(authError)
                        .font(AppType.body(12))
                        .foregroundStyle(.primary.opacity(0.7))
                }

                if store.isLoading {
                    ProgressView()
                        .tint(.primary)
                } else if let error = store.errorMessage {
                    Text(error)
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.7))
                } else if store.entries.isEmpty {
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
                    .glassCard(cornerRadius: 26)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                                LeaderboardRow(rank: index + 1, entry: entry)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
        }
        .onAppear {
            store.refresh(accessToken: auth.session?.accessToken)
        }
        .onChange(of: auth.isSignedIn) { _, _ in
            store.refresh(accessToken: auth.session?.accessToken)
        }
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

            Text("\(entry.totalPoints)")
                .font(AppType.title(18))
                .foregroundStyle(AppTheme.mint)
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }
}

private struct LeaderboardAccountRow: View {
    let onGoToAccount: () -> Void
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        if auth.isSignedIn {
            Text("Signed in as \(auth.user?.displayName ?? auth.user?.email ?? "Recycler")")
                .font(AppType.body(13))
                .foregroundStyle(.primary.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .glassCard(cornerRadius: 20)
        } else {
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
                        tint: Color.white.opacity(0.7)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .glassCard(cornerRadius: 20)
        }
    }
}

#Preview {
    LeaderboardView()
        .environmentObject(AuthStore())
}
