//
//  RecyclabilityApp.swift
//  Recyclability
//
//  Created by Sidharth Kumar on 1/24/26.
//

import SwiftUI
import GoogleSignIn
import Combine

@main
struct RecyclabilityApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var historyStore = HistoryStore()
    @StateObject private var authStore = AuthStore()
    @StateObject private var configStore = AppConfigStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(historyStore)
                .environmentObject(authStore)
                .environmentObject(configStore)
                .preferredColorScheme(authStore.preferredColorScheme)
                .task {
                    await configStore.load()
                    authStore.applyConfigIfAvailable()
                }
                .onChange(of: configStore.config) { _, _ in
                    authStore.applyConfigIfAvailable()
                }
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
