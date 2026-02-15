//
//  ContentView.swift
//  Recyclability
//
//  Created by Sidharth Kumar on 1/24/26.
//
import SwiftUI

struct ContentView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if hasSeenOnboarding {
                MainTabView()
            } else {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
