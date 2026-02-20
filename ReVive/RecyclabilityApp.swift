//
//  ReViveApp.swift
//  ReVive
//
//  Created by Sidharth Kumar on 1/24/26.
//

import SwiftUI
import GoogleSignIn
import Combine

@main
struct ReViveApp: App {
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
                    if GIDSignIn.sharedInstance.handle(url) {
                        return
                    }
                    guard url.scheme?.lowercased() == "revive",
                          url.host?.lowercased() == "billing"
                    else { return }

                    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    let hasCheckoutSession = components?.queryItems?.contains(where: {
                        $0.name == "session_id" && !($0.value ?? "").isEmpty
                    }) ?? false

                    Task { @MainActor in
                        await authStore.refreshSignedInUserState()
                    }

                    let action = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
                    switch action {
                    case "success":
                        if hasCheckoutSession {
                            NotificationCenter.default.post(name: .reviveBillingSuccess, object: nil)
                        }
                    case "cancel", "error", "failed":
                        if hasCheckoutSession {
                            NotificationCenter.default.post(name: .reviveBillingError, object: nil)
                        }
                    case "return", "portal-return":
                        break
                    default:
                        break
                    }
                }
        }
    }
}
