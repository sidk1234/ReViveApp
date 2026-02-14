//
//  MainTabView.swift
//  Recyclability
//

import SwiftUI

struct MainTabView: View {
    enum Tab: Int, CaseIterable {
        case settings
        case account
        case camera
        case impact
        case leaderboard
    }

    @State private var selection: Tab = .camera
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var auth: AuthStore
    @State private var bannerQuota: GuestQuota?

    var body: some View {
        TabView(selection: $selection) {
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    .tag(Tab.settings)

                AccountView()
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle.fill")
                    }
                    .tag(Tab.account)

                CameraScreen()
                    .tabItem {
                        Label("Capture", systemImage: "camera.fill")
                    }
                    .tag(Tab.camera)

                ImpactView {
                    selection = .account
                }
                .tabItem {
                    Label("Impact", systemImage: "leaf.fill")
                }
                .tag(Tab.impact)

                LeaderboardView {
                    selection = .account
                }
                .tabItem {
                    Label("Ranks", systemImage: "trophy.fill")
                }
                .tag(Tab.leaderboard)
        }
        .tint(AppTheme.mint)
        .safeAreaInset(edge: .top) {
            if !auth.isSignedIn, let quota = bannerQuota {
                GuestBanner(remaining: quota.remaining, limit: quota.limit) {
                    selection = .account
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .task {
            if !auth.isSignedIn {
                for _ in 0..<3 {
                    if let quota = await auth.fetchGuestQuota() {
                        bannerQuota = quota
                        break
                    }
                    try? await Task.sleep(nanoseconds: 600_000_000)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveGuestQuotaUpdated)) { note in
            if let quota = note.object as? GuestQuota, !auth.isSignedIn {
                auth.guestQuota = quota
                bannerQuota = quota
            }
        }
        .onChange(of: auth.guestQuota) { _, newValue in
            if let newValue, !auth.isSignedIn {
                bannerQuota = newValue
            }
        }
        .onChange(of: auth.isSignedIn) { _, newValue in
            if newValue {
                bannerQuota = nil
            } else {
                Task { @MainActor in
                    if let quota = await auth.fetchGuestQuota() {
                        bannerQuota = quota
                    }
                }
            }
        }
        .onChange(of: auth.user?.id ?? "") { _, newValue in
            if !newValue.isEmpty {
                if auth.autoSyncImpactEnabled {
                    auth.syncImpact(entries: history.entries, history: history)
                }
            }
        }
    }
}

private struct GuestBanner: View {
    let remaining: Int
    let limit: Int
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("You are a guest")
                    .font(AppType.title(13))
                    .foregroundStyle(.primary)
                Text("You have \(remaining) of \(limit) scans remaining. Please sign in to scan more.")
                    .font(AppType.body(11))
                    .foregroundStyle(.primary.opacity(0.75))
            }

            Spacer(minLength: 12)

            Button("Sign in") {
                onSignIn()
            }
            .font(AppType.body(12))
            .foregroundStyle(AppTheme.mint)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .staticCard(cornerRadius: 16)
    }
}

#Preview {
    MainTabView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
