//
//  LeaderboardStore.swift
//  Recyclability
//

import Foundation
import Combine

@MainActor
final class LeaderboardStore: ObservableObject {
    @Published var entries: [LeaderboardEntry] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasLoadedAtLeastOnce: Bool = false

    private var passiveRefreshTask: Task<Void, Never>?
    private var currentAccessToken: String?
    private let passiveRefreshIntervalNanoseconds: UInt64 = 10_000_000_000

    private var supabase: SupabaseService? {
        SupabaseConfig.load().map(SupabaseService.init)
    }

    func setAccessToken(_ accessToken: String?) {
        currentAccessToken = accessToken
    }

    func startPassiveRefresh() {
        guard passiveRefreshTask == nil else { return }
        passiveRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refreshNow(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.passiveRefreshIntervalNanoseconds)
                guard !Task.isCancelled else { break }
                await self.refreshNow()
            }
        }
    }

    func stopPassiveRefresh() {
        passiveRefreshTask?.cancel()
        passiveRefreshTask = nil
    }

    func refreshNow(force: Bool = false) {
        refresh(accessToken: currentAccessToken, force: force)
    }

    func refresh(accessToken: String?, force: Bool = false) {
        if !force, isLoading { return }
        currentAccessToken = accessToken
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            print("[LeaderboardStore] ERROR: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            hasLoadedAtLeastOnce = true
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        let token = currentAccessToken

        Task {
            do {
                let rows = try await supabase.fetchLeaderboard(accessToken: token)
                await MainActor.run {
                    self.entries = rows
                    self.hasLoadedAtLeastOnce = true
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Leaderboard unavailable."
                    self.hasLoadedAtLeastOnce = true
                    self.isLoading = false
                }
            }
        }
    }
}
