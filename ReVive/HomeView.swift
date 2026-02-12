//
//  AccountView.swift
//  Recyclability
//

import SwiftUI

struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEditProfile = false

    private var totalScans: Int { history.entries.count }
    private var recyclableCount: Int { history.entries.filter { $0.recyclable }.count }

    private var badges: [Badge] {
        [
            Badge(title: "Sprout", threshold: 1, icon: "leaf.fill", detail: "Recycle 1 item"),
            Badge(title: "Seedling", threshold: 5, icon: "leaf.circle.fill", detail: "Recycle 5 items"),
            Badge(title: "Sapling", threshold: 15, icon: "tree.fill", detail: "Recycle 15 items"),
            Badge(title: "Grove", threshold: 30, icon: "tree.circle.fill", detail: "Recycle 30 items"),
            Badge(title: "Forest", threshold: 60, icon: "leaf.arrow.triangle.circlepath", detail: "Recycle 60 items"),
            Badge(title: "Earthkeeper", threshold: 120, icon: "globe.americas.fill", detail: "Recycle 120 items")
        ]
    }

    private var currentLevel: Int {
        let index = badges.lastIndex { recyclableCount >= $0.threshold } ?? -1
        return index + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient(colorScheme)
                    .ignoresSafeArea()

                if auth.isSignedIn {
                    signedInContent
                } else {
                    LoginScreen()
                }
            }
        }
    }

    private var signedInContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Account")
                    .font(AppType.display(30))
                    .foregroundStyle(.primary)

                accountHeader

                if auth.isAdmin {
                    NavigationLink {
                        AdminPortalView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Admin Portal")
                                    .font(AppType.title(16))
                                Text("Manage users, impact, and settings.")
                                    .font(AppType.body(12))
                                    .foregroundStyle(.primary.opacity(0.7))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.primary)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .glassCard(cornerRadius: 20)
                    }
                    .buttonStyle(.plain)
                }

                if let errorMessage = auth.displayErrorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(AppType.body(12))
                        .foregroundStyle(.primary.opacity(0.7))
                }

                Text("Badges")
                    .font(AppType.title(18))
                    .foregroundStyle(.primary)

                badgeGrid
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(auth.isSignedIn ? "Signed in" : "Guest")
                        .font(AppType.title(16))
                        .foregroundStyle(.primary)
                    Text(auth.user?.displayName ?? auth.user?.email ?? "Sign in to sync your impact.")
                        .font(AppType.body(13))
                        .foregroundStyle(.primary.opacity(0.7))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(recyclableCount)")
                        .font(AppType.title(20))
                        .foregroundStyle(AppTheme.mint)
                    Text("Recycled")
                        .font(AppType.body(12))
                        .foregroundStyle(.primary.opacity(0.6))
                    Text("Level \(currentLevel)/\(badges.count)")
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }

            HStack(spacing: 12) {
                Button {
                    showEditProfile = true
                } label: {
                    HStack {
                        Image(systemName: "pencil")
                        Text("Edit profile")
                            .font(AppType.title(14))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .liquidGlassButton(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    auth.signOut()
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign out")
                            .font(AppType.title(14))
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .liquidGlassButton(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
        .sheet(isPresented: $showEditProfile) {
            EditProfileSheet()
                .environmentObject(auth)
                .presentationDetents([.medium, .large])
        }
    }

    private var badgeGrid: some View {
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(badges) { badge in
                BadgeCard(
                    badge: badge,
                    unlocked: recyclableCount >= badge.threshold,
                    currentCount: recyclableCount
                )
            }
        }
    }
}

private struct EditProfileSheet: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmNewPassword: String = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(.dark)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Edit profile")
                            .font(AppType.title(20))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button("Done") { dismiss() }
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                            .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display name")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                        TextField("Your name", text: $displayName)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit { nameFocused = false }
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                        TextField("", text: $email)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .disabled(!auth.canEditEmailPassword)
                            .padding(.horizontal, 14)
                            .frame(height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(auth.canEditEmailPassword ? 0.06 : 0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(auth.canEditEmailPassword ? 0.12 : 0.08), lineWidth: 1)
                            )
                    }

                    if auth.canEditEmailPassword {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current password")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                            SecureField("Enter your password", text: $currentPassword)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("New password")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                            SecureField("Leave blank to keep current", text: $newPassword)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm new password")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                            SecureField("Re-enter new password", text: $confirmNewPassword)
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .padding(.horizontal, 14)
                                .frame(height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                    }

                    if let message = auth.displayErrorMessage, !message.isEmpty {
                        Text(message)
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                    }

                    Button {
                        Task { @MainActor in
                            auth.errorMessage = nil
                            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                            let emailChanged = auth.canEditEmailPassword && trimmedEmail != (auth.user?.email ?? "")
                            let wantsPasswordChange = auth.canEditEmailPassword &&
                                (!newPassword.isEmpty || !confirmNewPassword.isEmpty)

                            if wantsPasswordChange {
                                guard newPassword == confirmNewPassword else {
                                    auth.errorMessage = "Passwords do not match."
                                    return
                                }
                                guard newPassword.count >= 6 else {
                                    auth.errorMessage = "Password must be at least 6 characters."
                                    return
                                }
                            }

                            if (emailChanged || wantsPasswordChange) && currentPassword.isEmpty {
                                auth.errorMessage = "Enter your current password to continue."
                                return
                            }

                            let ok = await auth.updateProfile(
                                displayName: trimmedName,
                                email: emailChanged ? trimmedEmail : nil,
                                newPassword: wantsPasswordChange ? newPassword : nil,
                                currentPassword: (emailChanged || wantsPasswordChange) ? currentPassword : nil
                            )
                            if ok {
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text(auth.isLoading ? "Saving..." : "Save changes")
                                .font(AppType.title(14))
                            Spacer()
                        }
                        .foregroundStyle(.primary)
                        .padding(.vertical, 12)
                        .liquidGlassButton(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(auth.isLoading)

                }
                .padding(20)
            }
            .onAppear {
                displayName = auth.user?.displayName ?? ""
                email = auth.user?.email ?? ""
                currentPassword = ""
                newPassword = ""
                confirmNewPassword = ""
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false }
                    .font(AppType.body(13))
                    .foregroundStyle(AppTheme.mint)
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var locationManager = LocationManager()
    @State private var defaultZipInput: String = ""
    @FocusState private var zipFocused: Bool
    @State private var showDeleteAlert = false

    private var appearanceBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { auth.preferences.appearanceMode ?? .system },
            set: { auth.updateAppearanceMode($0) }
        )
    }

    private var allowWebSearchBinding: Binding<Bool> {
        Binding(
            get: { auth.allowWebSearchEnabled },
            set: { auth.updateAllowWebSearch($0) }
        )
    }

    private var autoSyncBinding: Binding<Bool> {
        Binding(
            get: { auth.autoSyncImpactEnabled },
            set: { auth.updateAutoSyncImpact($0) }
        )
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { auth.enableHaptics },
            set: { auth.updateEnableHaptics($0) }
        )
    }

    private var captureInstructionBinding: Binding<Bool> {
        Binding(
            get: { auth.showCaptureInstructions },
            set: { auth.updateShowCaptureInstructions($0) }
        )
    }

    private var reduceMotionBinding: Binding<Bool> {
        Binding(
            get: { auth.reduceMotionEnabled },
            set: { auth.updateReduceMotion($0) }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient(colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Settings")
                            .font(AppType.display(30))
                            .foregroundStyle(.primary)

                        locationCard
                        appearanceCard
                        captureCard
                        syncCard
                        if auth.isSignedIn {
                            accountActionsCard
                        }

                        if !auth.isSignedIn {
                            Text("Sign in to sync preferences across devices.")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 28)
                    .padding(.bottom, 120)
                }
            }
        }
        .onAppear {
            defaultZipInput = auth.defaultZipCode
        }
        .onChange(of: auth.preferences.defaultZip) { _, newValue in
            defaultZipInput = newValue ?? ""
        }
        .onChange(of: defaultZipInput) { _, newValue in
            let filtered = newValue.filter { $0.isNumber }
            let trimmed = String(filtered.prefix(5))
            if trimmed != newValue {
                defaultZipInput = trimmed
                return
            }
            auth.updateDefaultZip(trimmed)
        }
        .onChange(of: locationManager.postalCode) { _, newValue in
            guard !newValue.isEmpty else { return }
            defaultZipInput = newValue
        }
    }

    private var locationCard: some View     {
        let textFieldShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let cardShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let isDarkMode = colorScheme == .dark
        let showZipDone = zipFocused

        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Location")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Default ZIP code")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.7))

                HStack(spacing: 10) {
                    ZStack(alignment: .trailing) {
                        TextField("ZIP code", text: $defaultZipInput)
                            .keyboardType(.numberPad)
                            .textContentType(.postalCode)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.primary)
                            .tint(AppTheme.mint)
                            .focused($zipFocused)
                            .frame(maxWidth: .infinity)
                            .padding(.leading, 14)
                            .padding(.trailing, showZipDone ? 48 : 14)
                            .frame(height: 46)

                        if showZipDone {
                            Button("Done") {
                                zipFocused = false
                            }
                            .font(AppType.body(13))
                            .foregroundStyle(.primary.opacity(0.9))
                            .buttonStyle(.plain)
                            .padding(.trailing, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .background(
                        Group {
                            if isDarkMode {
                                textFieldShape.fill(Color.white.opacity(0.06))
                            } else {
                                textFieldShape.fill(.ultraThinMaterial)
                            }
                        }
                    )
                    .overlay(
                        textFieldShape
                            .stroke(Color.primary.opacity(isDarkMode ? 0.08 : 0.12), lineWidth: 1)
                    )

                    Button {
                        zipFocused = false
                        locationManager.requestLocation()
                    } label: {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.primary)
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 42, height: 42)
                            .liquidGlassButton(in: Circle(), interactive: true)
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("Allow web search for local rules", isOn: allowWebSearchBinding)
                .font(AppType.body(13))
                .foregroundStyle(.primary)
                .tint(AppTheme.mint)
        }
        .padding(16)

        return Group {
            if isDarkMode {
                content
                    .background(cardShape.fill(Color.white.opacity(0.05)))
                    .overlay(cardShape.stroke(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                content
                    .glassCard(cornerRadius: 20)
            }
        }
    }

    private var appearanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            Picker("Theme", selection: appearanceBinding) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .tint(AppTheme.mint)
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Capture")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            Toggle("Haptic feedback", isOn: hapticsBinding)
                .font(AppType.body(13))
                .foregroundStyle(.primary)
                .tint(AppTheme.mint)

            Toggle("Show capture instructions", isOn: captureInstructionBinding)
                .font(AppType.body(13))
                .foregroundStyle(.primary)
                .tint(AppTheme.mint)

            Toggle("Reduce motion", isOn: reduceMotionBinding)
                .font(AppType.body(13))
                .foregroundStyle(.primary)
                .tint(AppTheme.mint)
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var syncCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            Toggle("Auto-sync impact", isOn: autoSyncBinding)
                .font(AppType.body(13))
                .foregroundStyle(.primary)
                .tint(AppTheme.mint)

            if !auth.isSignedIn {
                Text("Auto-sync requires a signed-in account.")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.7))
        }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var accountActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            Text("Delete your account and all associated data from Supabase.")
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))

            Button {
                showDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text(auth.isLoading ? "Deleting..." : "Delete account")
                        .font(AppType.title(14))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlassButton(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(auth.isLoading)
            .alert("Delete account?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    auth.deleteAccount()
                }
            } message: {
                Text("This action permanently deletes your account and cannot be undone.")
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }
}

private struct Badge: Identifiable {
    let id = UUID()
    let title: String
    let threshold: Int
    let icon: String
    let detail: String
}

private struct BadgeCard: View {
    let badge: Badge
    let unlocked: Bool
    let currentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: badge.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(unlocked ? AppTheme.mint : .primary.opacity(0.5))
                Spacer()
                if unlocked {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.mint)
                }
            }

            Text(badge.title)
                .font(AppType.title(15))
                .foregroundStyle(.primary)

            Text(badge.detail)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))

            Text("\(min(currentCount, badge.threshold)) / \(badge.threshold)")
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.6))
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .opacity(unlocked ? 1.0 : 0.55)
    }
}

#Preview {
    AccountView()
        .environmentObject(AuthStore())
        .environmentObject(HistoryStore())
}
