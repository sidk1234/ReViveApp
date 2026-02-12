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

    private var supabase: SupabaseService? {
        SupabaseConfig.load().map(SupabaseService.init)
    }

    func refresh(accessToken: String?) {
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            print("[LeaderboardStore] ERROR: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return
        }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let rows = try await supabase.fetchLeaderboard(accessToken: accessToken)
                await MainActor.run {
                    self.entries = rows
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Leaderboard unavailable."
                    self.isLoading = false
                }
            }
        }
    }
}
