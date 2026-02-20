//
//  MainTabView.swift
//  Recyclability
//

import SwiftUI
import Combine

struct MainTabView: View {
    enum Tab: Int, CaseIterable {
        case impact
        case account
        case camera
        case bin
        case leaderboard
    }

    @State private var selection: Tab = .camera
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var auth: AuthStore
    @State private var bannerQuota: GuestQuota?

    var body: some View {
        TabView(selection: $selection) {
                NavigationStack {
                    ImpactView()
                }
                    .tabItem {
                        Label("Impact", systemImage: "leaf.fill")
                    }
                    .tag(Tab.impact)

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

                NavigationStack {
                    BinView()
                }
                .tabItem {
                    Label("Bin", systemImage: "trash.fill")
                }
                .tag(Tab.bin)

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
                auth.applyGuestQuotaUpdate(quota)
                bannerQuota = auth.guestQuota
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveRequestSignIn)) { _ in
            selection = .account
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveOpenBin)) { _ in
            selection = .bin
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveRequestUpgrade)) { _ in
            selection = .account
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NotificationCenter.default.post(name: .reviveOpenSubscription, object: nil)
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
                Task { @MainActor in
                    await auth.refreshImpactFromServer(history: history)
                    if auth.autoSyncImpactEnabled {
                        auth.syncImpact(entries: history.entries, history: history)
                    }
                }
            }
        }
        .onAppear {
            syncBinReminder(for: history.entries)
        }
        .onChange(of: history.entries) { _, entries in
            syncBinReminder(for: entries)
        }
    }

    private func syncBinReminder(for entries: [HistoryEntry]) {
        let markedCount = markedForRecycleCount(in: entries)
        BinReminderNotificationManager.shared.syncPendingBinReminder(markedCount: markedCount)
    }

    private func markedForRecycleCount(in entries: [HistoryEntry]) -> Int {
        var count = 0
        for entry in entries where entry.recycleStatus == .markedForRecycle {
            count += 1
        }
        return count
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
