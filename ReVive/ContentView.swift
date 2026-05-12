//
//  ContentView.swift
//  Recyclability
//
//  Created by Sidharth Kumar on 1/24/26.
//
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: AuthStore
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if hasSeenOnboarding {
                MainTabView()
                    .preferredColorScheme(auth.preferredColorScheme)
            } else {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { auth.isShowingPasswordRecovery },
                set: { isPresented in
                    if !isPresented {
                        auth.dismissPasswordRecovery()
                    }
                }
            )
        ) {
            PasswordRecoveryView()
                .environmentObject(auth)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthStore())
        .environmentObject(HistoryStore())
        .environmentObject(AppConfigStore())
        .environmentObject(LeaderboardStore())
}
