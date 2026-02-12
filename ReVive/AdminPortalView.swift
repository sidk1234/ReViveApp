//
//  AdminPortalView.swift
//  Recyclability
//

import SwiftUI

struct AdminPortalView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var store = AdminPortalStore()
    @State private var userFilter: String = ""
    @State private var impactFilter: String = ""
    @State private var impactUserFilter: String?
    @State private var pendingAdminUser: ProfileRow?
    @State private var showingAdminConfirm = false
    @State private var profileToEdit: ProfileRow?
    @State private var impactToEdit: ImpactEntryRow?
    @State private var pendingImpactDelete: ImpactEntryRow?
    @State private var showingImpactDeleteConfirm = false

    private var accessToken: String? { auth.session?.accessToken }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Admin Portal")
                        .font(AppType.display(28))
                        .foregroundStyle(.primary)

                    Text("Manage accounts, impact data, and app settings.")
                        .font(AppType.body(14))
                        .foregroundStyle(.primary.opacity(0.7))

                    if !auth.isAdmin {
                        Text("This area is restricted to admins.")
                            .font(AppType.body(13))
                            .foregroundStyle(.primary.opacity(0.7))
                            .padding(14)
                            .glassCard(cornerRadius: 20)
                    } else {
                        if let errorMessage = store.errorMessage, !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                        settingsSection
                        usersSection
                        impactSection
                        leaderboardSection
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 120)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard auth.isAdmin, let token = accessToken else { return }
            store.refresh(accessToken: token)
        }
        .onChange(of: auth.isAdmin) { _, isAdmin in
            guard isAdmin, let token = accessToken else { return }
            store.refresh(accessToken: token)
        }
        .alert("Make Admin", isPresented: $showingAdminConfirm, presenting: pendingAdminUser) { user in
            Button("Cancel", role: .cancel) {}
            Button("Confirm") {
                guard let token = accessToken else { return }
                store.updateAdminStatus(id: user.id, isAdmin: true, accessToken: token)
            }
        } message: { user in
            Text("Are you sure you want to grant admin access to \(user.displayName ?? user.email ?? "this user")?")
        }
        .alert("Remove Activity", isPresented: $showingImpactDeleteConfirm, presenting: pendingImpactDelete) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                guard let token = accessToken else { return }
                store.deleteImpactEntry(entry: entry, accessToken: token)
            }
        } message: { entry in
            Text("Delete \(entry.item) for this user? This will remove it from the leaderboard.")
        }
        .sheet(item: $profileToEdit) { profile in
            AdminProfileEditor(profile: profile) { displayName, email in
                guard let token = accessToken else { return }
                store.updateProfile(id: profile.id, displayName: displayName, email: email, accessToken: token)
            }
        }
        .sheet(item: $impactToEdit) { entry in
            ImpactEntryEditor(entry: entry) { updated in
                guard let token = accessToken else { return }
                store.updateImpactEntry(original: entry, updated: updated, accessToken: token)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Controls")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            Toggle(isOn: Binding(get: { auth.photoStorageEnabled }, set: { newValue in
                auth.updatePhotoStorageEnabled(newValue)
            })) {
                Text("Photo storage (Supabase)")
                    .font(AppType.body(14))
                    .foregroundStyle(.primary)
            }
            .tint(AppTheme.mint)

            Text("When off, photos stay local and aren’t uploaded to Supabase storage.")
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var usersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Users", subtitle: "Promote admins and edit profile metadata.")

            TextField("Search users by name or email", text: $userFilter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppType.body(14))
                .foregroundStyle(.primary)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )

            if store.isLoadingProfiles {
                ProgressView()
                    .tint(.primary)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredProfiles) { profile in
                        AdminUserRow(
                            profile: profile,
                            onEdit: { profileToEdit = profile },
                            onFocusImpact: { impactUserFilter = profile.id },
                            onMakeAdmin: {
                                pendingAdminUser = profile
                                showingAdminConfirm = true
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Impact Entries", subtitle: "Edit activity to correct data or adjust points.")

            TextField("Filter by user id, item, or material", text: $impactFilter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppType.body(14))
                .foregroundStyle(.primary)
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )

            if let impactUserFilter {
                HStack {
                    Text("Filtering user: \(impactUserFilter)")
                        .font(AppType.body(12))
                        .foregroundStyle(.primary.opacity(0.7))
                    Spacer()
                    Button("Clear") { self.impactUserFilter = nil }
                        .font(AppType.body(12))
                        .foregroundStyle(.primary)
                }
            }

            if store.isLoadingImpact {
                ProgressView()
                    .tint(.primary)
            } else {
                VStack(spacing: 10) {
                    ForEach(filteredImpactEntries) { entry in
                        AdminImpactRow(
                            entry: entry,
                            onEdit: { impactToEdit = entry },
                            onDelete: {
                                pendingImpactDelete = entry
                                showingImpactDeleteConfirm = true
                            }
                        )
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "Leaderboard", subtitle: "Derived from impact entries. Edit entries above to adjust totals.")

            if store.isLoadingLeaderboard {
                ProgressView()
                    .tint(.primary)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(store.leaderboardEntries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: 12) {
                            Text("#\(index + 1)")
                                .font(AppType.title(12))
                                .foregroundStyle(.primary.opacity(0.7))
                                .frame(width: 36, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.displayName ?? "Recycler")
                                    .font(AppType.title(14))
                                    .foregroundStyle(.primary)
                                Text("\(entry.totalPoints) points")
                                    .font(AppType.body(12))
                                    .foregroundStyle(.primary.opacity(0.7))
                            }

                            Spacer()

                            Button("Focus impact") {
                                impactUserFilter = entry.userId
                            }
                            .font(AppType.body(12))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .liquidGlassButton(
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                tint: Color.white.opacity(0.7)
                            )
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 16)
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppType.title(16))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))
        }
    }

    private var filteredProfiles: [ProfileRow] {
        let trimmed = userFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return store.profiles }
        return store.profiles.filter { profile in
            let name = profile.displayName?.lowercased() ?? ""
            let email = profile.email?.lowercased() ?? ""
            return name.contains(trimmed) || email.contains(trimmed)
        }
    }

    private var filteredImpactEntries: [ImpactEntryRow] {
        let trimmed = impactFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.impactEntries.filter { entry in
            if let impactUserFilter, impactUserFilter != entry.userId {
                return false
            }
            if trimmed.isEmpty { return true }
            let haystack = [
                entry.userId.lowercased(),
                entry.item.lowercased(),
                entry.material.lowercased()
            ]
            return haystack.contains { $0.contains(trimmed) }
        }
    }
}

private struct AdminUserRow: View {
    let profile: ProfileRow
    let onEdit: () -> Void
    let onFocusImpact: () -> Void
    let onMakeAdmin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.displayName ?? "Unnamed User")
                        .font(AppType.title(14))
                        .foregroundStyle(.primary)
                    Text(profile.email ?? "No email on file")
                        .font(AppType.body(12))
                        .foregroundStyle(.primary.opacity(0.7))
                }

                Spacer()

                if profile.isAdmin == true {
                    Text("Admin")
                        .font(AppType.body(11))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppTheme.mint))
                }
            }

            HStack(spacing: 10) {
                Button("Edit") {
                    onEdit()
                }
                .font(AppType.body(12))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassButton(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Focus impact") {
                    onFocusImpact()
                }
                .font(AppType.body(12))
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassButton(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                if profile.isAdmin != true {
                    Button("Make admin") {
                        onMakeAdmin()
                    }
                    .font(AppType.body(12))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        tint: Color.white.opacity(0.7)
                    )
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }
}

private struct AdminImpactRow: View {
    let entry: ImpactEntryRow
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.item)
                        .font(AppType.title(14))
                        .foregroundStyle(.primary)
                    Text("User: \(entry.userId)")
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.6))
                }
                Spacer()
                Text("\(entry.points)")
                    .font(AppType.title(16))
                    .foregroundStyle(AppTheme.mint)
            }

            Text("\(entry.material) • \(entry.bin)")
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.75))

            HStack(spacing: 10) {
                Button("Edit") { onEdit() }
                    .font(AppType.body(12))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassButton(in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button("Delete") { onDelete() }
                    .font(AppType.body(12))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .liquidGlassButton(
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        tint: Color.white.opacity(0.7)
                    )
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }
}

private struct AdminProfileEditor: View {
    let profile: ProfileRow
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var email: String

    init(profile: ProfileRow, onSave: @escaping (String, String) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _displayName = State(initialValue: profile.displayName ?? "")
        _email = State(initialValue: profile.email ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Display name") {
                    TextField("Display name", text: $displayName)
                }
                Section("Email (profile metadata)") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(displayName, email)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ImpactEntryEditor: View {
    let entry: ImpactEntryRow
    let onSave: (ImpactEntryRow) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var item: String
    @State private var material: String
    @State private var bin: String
    @State private var notes: String
    @State private var recyclable: Bool
    @State private var points: Int

    init(entry: ImpactEntryRow, onSave: @escaping (ImpactEntryRow) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _item = State(initialValue: entry.item)
        _material = State(initialValue: entry.material)
        _bin = State(initialValue: entry.bin)
        _notes = State(initialValue: entry.notes)
        _recyclable = State(initialValue: entry.recyclable)
        _points = State(initialValue: entry.points)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Item", text: $item)
                    TextField("Material", text: $material)
                    TextField("Bin", text: $bin)
                }
                Section("Details") {
                    Toggle("Recyclable", isOn: $recyclable)
                    Stepper(value: $points, in: 0...50) {
                        Text("Points: \(points)")
                    }
                    TextField("Notes", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Edit Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updatedKey = ImpactKey.itemKey(item: item, material: material, bin: bin)
                        let updated = ImpactEntryRow(
                            rowId: entry.rowId,
                            userId: entry.userId,
                            itemKey: updatedKey,
                            dayKey: entry.dayKey,
                            item: item,
                            material: material,
                            recyclable: recyclable,
                            bin: bin,
                            notes: notes,
                            scannedAt: entry.scannedAt,
                            points: points,
                            scanCount: entry.scanCount,
                            source: entry.source,
                            imagePath: entry.imagePath
                        )
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    AdminPortalView()
        .environmentObject(AuthStore())
}
