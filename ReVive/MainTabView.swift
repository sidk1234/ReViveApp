//
//  MainTabView.swift
//  Recyclability
//

import SwiftUI
import Combine

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
            ZStack {
                if !auth.isSignedIn, let quota = bannerQuota {
                    GuestBanner(remaining: quota.remaining, limit: quota.limit) {
                        selection = .account
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .zIndex(-1)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: !auth.isSignedIn && bannerQuota != nil)
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
        .onReceive(
            NotificationCenter.default.publisher(for: .reviveGuestQuotaUpdated)
                .receive(on: RunLoop.main)
        ) { note in
            if let quota = note.object as? GuestQuota, !auth.isSignedIn {
                auth.guestQuota = quota
                bannerQuota = quota
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveRequestSignIn)) { _ in
            selection = .account
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
                Task { @MainActor in
                    await auth.refreshImpactFromServer(history: history)
                    if auth.autoSyncImpactEnabled {
                        auth.syncImpact(entries: history.entries, history: history)
                    }
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
                    .foregroundStyle(.black)
                Text("You have \(remaining) of \(limit) scans remaining. Please sign in to scan more.")
                    .font(AppType.body(11))
                    .foregroundStyle(.black)
            }

            Spacer(minLength: 12)
                
            Button("Sign in") {
                onSignIn()
            }
            .font(AppType.body(12))
            .foregroundStyle(Color.black)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.2), lineWidth: 2)
        )
        .staticCard(cornerRadius: 16)
    }
}

#Preview {
    MainTabView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
