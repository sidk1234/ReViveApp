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
        .onChange(of: auth.user?.id ?? "") { _, newValue in
            if !newValue.isEmpty {
                if auth.autoSyncImpactEnabled {
                    auth.syncImpact(entries: history.entries, history: history)
                }
            }
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
