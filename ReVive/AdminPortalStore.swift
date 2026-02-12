//
//  AdminPortalStore.swift
//  Recyclability
//

import Foundation
import Combine

@MainActor
final class AdminPortalStore: ObservableObject {
    @Published var profiles: [ProfileRow] = []
    @Published var impactEntries: [ImpactEntryRow] = []
    @Published var leaderboardEntries: [LeaderboardEntry] = []
    @Published var isLoadingProfiles: Bool = false
    @Published var isLoadingImpact: Bool = false
    @Published var isLoadingLeaderboard: Bool = false
    @Published var errorMessage: String?

    private var supabase: SupabaseService? {
        SupabaseConfig.load().map(SupabaseService.init)
    }

    func refresh(accessToken: String) {
        refreshProfiles(accessToken: accessToken)
        refreshImpactEntries(accessToken: accessToken)
        refreshLeaderboard(accessToken: accessToken)
    }

    func refreshProfiles(accessToken: String) {
        guard let supabase else { return }
        isLoadingProfiles = true
        errorMessage = nil
        Task {
            do {
                let rows = try await supabase.fetchProfiles(accessToken: accessToken)
                await MainActor.run {
                    self.profiles = rows
                    self.isLoadingProfiles = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load users."
                    self.isLoadingProfiles = false
                }
            }
        }
    }

    func refreshImpactEntries(accessToken: String) {
        guard let supabase else { return }
        isLoadingImpact = true
        errorMessage = nil
        Task {
            do {
                let rows = try await supabase.fetchImpactEntries(accessToken: accessToken)
                await MainActor.run {
                    self.impactEntries = rows
                    self.isLoadingImpact = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load impact entries."
                    self.isLoadingImpact = false
                }
            }
        }
    }

    func refreshLeaderboard(accessToken: String?) {
        guard let supabase else { return }
        isLoadingLeaderboard = true
        errorMessage = nil
        Task {
            do {
                let rows = try await supabase.fetchLeaderboard(accessToken: accessToken)
                await MainActor.run {
                    self.leaderboardEntries = rows
                    self.isLoadingLeaderboard = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load leaderboard."
                    self.isLoadingLeaderboard = false
                }
            }
        }
    }

    func updateProfile(
        id: String,
        displayName: String,
        email: String,
        accessToken: String
    ) {
        guard let supabase else { return }
        Task {
            do {
                try await supabase.updateProfile(
                    id: id,
                    displayName: displayName,
                    email: email,
                    accessToken: accessToken
                )
                await MainActor.run {
                    self.refreshProfiles(accessToken: accessToken)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Profile update failed."
                }
            }
        }
    }

    func updateAdminStatus(
        id: String,
        isAdmin: Bool,
        accessToken: String
    ) {
        guard let supabase else { return }
        Task {
            do {
                try await supabase.updateProfileAdminStatus(id: id, isAdmin: isAdmin, accessToken: accessToken)
                await MainActor.run {
                    self.refreshProfiles(accessToken: accessToken)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Admin update failed."
                }
            }
        }
    }

    func updateImpactEntry(original: ImpactEntryRow, updated: ImpactEntryRow, accessToken: String) {
        guard let supabase else { return }
        Task {
            do {
                try await supabase.updateImpactEntry(
                    originalUserId: original.userId,
                    originalItemKey: original.itemKey,
                    originalDayKey: original.dayKey,
                    updated: updated,
                    accessToken: accessToken
                )
                await MainActor.run {
                    self.refreshImpactEntries(accessToken: accessToken)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Impact update failed."
                }
            }
        }
    }

    func deleteImpactEntry(entry: ImpactEntryRow, accessToken: String) {
        guard let supabase else { return }
        Task {
            do {
                try await supabase.deleteImpactEntry(
                    userId: entry.userId,
                    itemKey: entry.itemKey,
                    dayKey: entry.dayKey,
                    accessToken: accessToken
                )
                await MainActor.run {
                    self.refreshImpactEntries(accessToken: accessToken)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Impact delete failed."
                }
            }
        }
    }
}
