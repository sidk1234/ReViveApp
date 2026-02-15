//
//  AccountView.swift
//  Recyclability
//

import SwiftUI
import PhotosUI
import UIKit
import Combine


struct AccountView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEditProfile = false
    @State private var showDeleteAlert = false
    @State private var isSigningOut = false

    private var totalScans: Int { history.entries.count }
    private var recyclableCount: Int { history.entries.filter { $0.recyclable }.count }
    private var totalPoints: Int {
        history.entries.filter { $0.source == .photo && $0.recyclable }.count
    }

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

                NavigationLink(isActive: $showEditProfile) {
                    EditProfileView()
                        .environmentObject(auth)
                } label: {
                    EmptyView()
                }
                .hidden()

                if isSigningOut {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: auth.isSignedIn) { _, newValue in
            if !newValue {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isSigningOut = false
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
                        .accountCard()
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

                deleteAccountCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 120)
        }
    }

    private var accountHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let image = ProfileExtrasStore.loadProfileImage() {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                } else if let avatarURL = auth.user?.avatarURL, let url = URL(string: avatarURL) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Circle().fill(Color.white.opacity(0.08))
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                } else {
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 54, height: 54)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.primary.opacity(0.7))
                        )
                }

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
                    Text("\(totalPoints)")
                        .font(AppType.title(20))
                        .foregroundStyle(AppTheme.mint)
                    Text("Impact")
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
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSigningOut = true
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 180_000_000)
                        auth.signOut()
                    }
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
        .accountCard()
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

    private var deleteAccountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete account")
                .font(AppType.title(16))
                .foregroundStyle(.primary)

            Text("Delete your account and all associated data.")
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
        .accountCard()
    }
}

private struct EditProfileView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String = ""
    @State private var email: String = ""
    @State private var currentPassword: String = ""
    @State private var newPassword: String = ""
    @State private var confirmNewPassword: String = ""
    @State private var phoneNumber: String = ""
    @State private var location: String = ""
    @State private var bio: String = ""
    @State private var website: String = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var pendingImage: PendingImage?
    @FocusState private var nameFocused: Bool
    
    private var profileImage: Image? {
        ProfileExtrasStore.loadProfileImage(data: photoData)
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(.dark)
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle().fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)

                        Text("Edit profile")
                            .font(AppType.title(20))
                            .foregroundStyle(.primary)

                        Spacer()
                    }

                    HStack(spacing: 16) {
                        if let profileImage {
                            profileImage
                                .resizable()
                                .scaledToFill()
                                .frame(width: 72, height: 72)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        } else if let avatarURL = auth.user?.avatarURL, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image {
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    Circle().fill(Color.white.opacity(0.08))
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.primary.opacity(0.12), lineWidth: 1))
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 72, height: 72)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundStyle(.primary.opacity(0.7))
                                )
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Profile photo")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))
                            PhotosPicker(
                                selection: $selectedPhoto,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Text("Change photo")
                                    .font(AppType.body(13))
                                    .foregroundStyle(AppTheme.mint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 6)

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Phone number")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                        TextField("Optional", text: $phoneNumber)
                            .textFieldStyle(.plain)
                            .keyboardType(.phonePad)
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
                        Text("Location")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                        TextField("City, State", text: $location)
                            .textFieldStyle(.plain)
                            .textInputAutocapitalization(.words)
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
                        Text("Website")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                        TextField("Optional", text: $website)
                            .textFieldStyle(.plain)
                            .keyboardType(.URL)
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
                        Text("Bio")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
                        TextField("Tell us a bit about you", text: $bio, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3...5)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
                    } else if auth.canAddPassword {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Add a password")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.7))

                            SecureField("Create a password", text: $newPassword)
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

                            SecureField("Confirm password", text: $confirmNewPassword)
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
                    } else {
                        Text("Password updates are unavailable for this account.")
                            .font(AppType.body(12))
                            .foregroundStyle(.primary.opacity(0.7))
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
                            let wantsPasswordChange = auth.canUpdatePassword &&
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

                            if (emailChanged || (wantsPasswordChange && auth.canEditEmailPassword)) && currentPassword.isEmpty {
                                auth.errorMessage = "Enter your current password to continue."
                                return
                            }

                            let ok = await auth.updateProfile(
                                displayName: trimmedName,
                                email: emailChanged ? trimmedEmail : nil,
                                newPassword: wantsPasswordChange ? newPassword : nil,
                                currentPassword: (emailChanged || (wantsPasswordChange && auth.canEditEmailPassword)) ? currentPassword : nil
                            )
                            if ok {
                                if let photoData {
                                    _ = await auth.updateProfilePhoto(photoData: photoData)
                                }
                                ProfileExtrasStore.save(
                                    phoneNumber: phoneNumber,
                                    location: location,
                                    bio: bio,
                                    website: website,
                                    photoData: photoData
                                )
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
                phoneNumber = ProfileExtrasStore.loadPhoneNumber()
                location = ProfileExtrasStore.loadLocation()
                bio = ProfileExtrasStore.loadBio()
                website = ProfileExtrasStore.loadWebsite()
                photoData = ProfileExtrasStore.loadProfileImageData()
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let newValue else { return }
                Task { @MainActor in
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pendingImage = PendingImage(image: image)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .fullScreenCover(item: $pendingImage) { item in
            ProfilePhotoCropper(
                image: item.image,
                onCancel: {
                    pendingImage = nil
                },
                onSave: { cropped in
                    photoData = cropped.compressedJPEGData(targetBytes: 100_000) ??
                        cropped.jpegData(compressionQuality: 0.85)
                    pendingImage = nil
                }
            )
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

private struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ProfilePhotoCropper: View {
    let image: UIImage
    let onCancel: () -> Void
    let onSave: (UIImage) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var controller: CropController
    @State private var cropSide: CGFloat = 280
    @State private var cropRect: CGRect = .zero
    @State private var imageOrigin: CGPoint = .zero

    init(image: UIImage, onCancel: @escaping () -> Void, onSave: @escaping (UIImage) -> Void) {
        self.image = image
        self.onCancel = onCancel
        self.onSave = onSave
        _controller = StateObject(wrappedValue: CropController(image: image.normalizedImage()))
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                            .offset(x: 4, y: 4)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 48)

                Text("Crop & rotate")
                    .font(AppType.title(18))
                    .foregroundStyle(.primary)

                GeometryReader { geo in
                    let containerSize = geo.size
                    let side = min(containerSize.width, containerSize.height)
                    let computedOrigin = CGPoint(
                        x: (containerSize.width - side) / 2,
                        y: (containerSize.height - side) / 2
                    )
                    ZStack {
                        Color.clear
                            .onAppear {
                                cropSide = side
                                imageOrigin = computedOrigin
                                cropRect = defaultCropRect(containerSize: containerSize, imageSide: side)
                            }
                            .onChange(of: geo.size) { _, _ in
                                cropSide = side
                                imageOrigin = computedOrigin
                                cropRect = defaultCropRect(containerSize: containerSize, imageSide: side)
                            }

                        ZoomableCropView(controller: controller, cropSide: side)
                            .frame(width: side, height: side)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                        cropOverlay(bounds: CGRect(origin: .zero, size: containerSize), cropRect: $cropRect)

                        PinchZoomOverlay(controller: controller)
                            .frame(width: side, height: side)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .frame(height: 340)

                RotateTickControl(controller: controller)

                Button {
                    if let cropped = controller.cropImage(
                        cropRect: cropRect,
                        cropSide: cropSide,
                        imageOrigin: imageOrigin
                    ) {
                        onSave(cropped)
                    }
                } label: {
                    Text("Save as profile picture")
                        .font(AppType.title(16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

                Spacer()
            }
        }
    }

    private func cropOverlay(bounds: CGRect, cropRect: Binding<CGRect>) -> some View {
        ZStack {
            ZStack {
                Color.black.opacity(0.55)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .frame(width: cropRect.wrappedValue.width, height: cropRect.wrappedValue.height)
                    .position(x: cropRect.wrappedValue.midX, y: cropRect.wrappedValue.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()

            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                .frame(width: cropRect.wrappedValue.width, height: cropRect.wrappedValue.height)
                .position(x: cropRect.wrappedValue.midX, y: cropRect.wrappedValue.midY)

            cropHandles(cropRect: cropRect, bounds: bounds)
        }
        .allowsHitTesting(true)
    }

    private func cropHandles(cropRect: Binding<CGRect>, bounds: CGRect) -> some View {
        CropHandlesView(cropRect: cropRect, bounds: bounds)
    }

    private func defaultCropRect(containerSize: CGSize, imageSide: CGFloat) -> CGRect {
        let side = imageSide * 0.62
        let origin = CGPoint(
            x: (containerSize.width - side) / 2,
            y: (containerSize.height - side) / 2
        )
        return CGRect(origin: origin, size: CGSize(width: side, height: side))
    }

}

private final class CropController: ObservableObject {
    private var baseImage: UIImage
    @Published private(set) var image: UIImage
    fileprivate weak var scrollView: UIScrollView?
    fileprivate weak var contentView: UIView?
    fileprivate weak var imageView: UIImageView?
    fileprivate var baseScale: CGFloat = 1
    @Published var rotationDegrees: Double = 0
    private var rotationRequestID = UUID()

    init(image: UIImage) {
        self.baseImage = image
        self.image = image
    }

    func setRotationPreview(degrees: Double) {
        let clamped = min(max(degrees, -90), 90)
        rotationDegrees = clamped
        if let imageView {
            let radians = CGFloat(clamped * Double.pi / 180)
            imageView.transform = CGAffineTransform(rotationAngle: radians)
        }
    }

    func commitRotation() {
        let requestID = UUID()
        rotationRequestID = requestID
        let degrees = min(max(rotationDegrees, -90), 90)
        if abs(degrees) < 0.01 {
            imageView?.transform = .identity
            rotationDegrees = 0
            return
        }
        let source = baseImage
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let rendered = autoreleasepool { source.rotated(byDegrees: degrees) }
            DispatchQueue.main.async {
                guard let self, self.rotationRequestID == requestID else { return }
                self.imageView?.transform = .identity
                self.baseImage = rendered
                self.image = rendered
                self.rotationDegrees = 0
            }
        }
    }

    func applyZoom(delta: CGFloat) {
        guard let scrollView else { return }
        let current = scrollView.zoomScale
        let target = min(max(current * delta, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
        if abs(target - current) <= 0.0001 { return }

        let bounds = scrollView.bounds.size
        let anchor = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let locationInContent = CGPoint(
            x: (anchor.x + scrollView.contentOffset.x) / current,
            y: (anchor.y + scrollView.contentOffset.y) / current
        )
        let zoomSize = CGSize(width: bounds.width / target, height: bounds.height / target)
        let zoomOrigin = CGPoint(
            x: locationInContent.x - zoomSize.width / 2,
            y: locationInContent.y - zoomSize.height / 2
        )
        let zoomRect = CGRect(origin: zoomOrigin, size: zoomSize)
        scrollView.zoom(to: zoomRect, animated: false)
    }

    func applyPan(delta: CGPoint) {
        guard let scrollView else { return }
        if scrollView.zoomScale <= scrollView.minimumZoomScale + 0.0001 { return }
        var offset = scrollView.contentOffset
        offset.x -= delta.x
        offset.y -= delta.y
        scrollView.contentOffset = offset
        clampOffsets(scrollView)
    }

    func cropImage(cropRect: CGRect, cropSide: CGFloat, imageOrigin: CGPoint) -> UIImage? {
        guard let scrollView else { return nil }
        let zoomScale = scrollView.zoomScale
        let scale = baseScale * zoomScale
        let offset = scrollView.contentOffset
        let adjustedRect = cropRect.offsetBy(dx: -imageOrigin.x, dy: -imageOrigin.y)
        var rect = CGRect(
            x: (offset.x + adjustedRect.origin.x) / scale,
            y: (offset.y + adjustedRect.origin.y) / scale,
            width: adjustedRect.size.width / scale,
            height: adjustedRect.size.height / scale
        )
        let bounds = CGRect(origin: .zero, size: image.size)
        rect = rect.intersection(bounds).integral
        guard let cg = image.cgImage?.cropping(to: rect), rect.width > 0, rect.height > 0 else {
            return nil
        }
        return UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
    }

    fileprivate func updateLayout() {
        guard let scrollView, let contentView, let imageView else { return }
        let cropSide = min(scrollView.bounds.width, scrollView.bounds.height)
        let imageSize = image.size
        let fillScale = max(cropSide / imageSize.width, cropSide / imageSize.height)
        let fitScale = min(cropSide / imageSize.width, cropSide / imageSize.height)
        baseScale = fillScale
        let baseSize = CGSize(width: imageSize.width * fillScale, height: imageSize.height * fillScale)
        contentView.frame = CGRect(origin: .zero, size: baseSize)
        imageView.frame = contentView.bounds
        scrollView.contentSize = baseSize
        contentView.center = CGPoint(x: baseSize.width / 2, y: baseSize.height / 2)

        let minTotalScale = min(1, fitScale)
        let minZoom = minTotalScale / fillScale
        scrollView.minimumZoomScale = minZoom
        scrollView.maximumZoomScale = 6
        if scrollView.zoomScale < minZoom {
            scrollView.zoomScale = minZoom
        }

        updateInsets(scrollView)
        let offsetX = max(0, (baseSize.width - cropSide) / 2)
        let offsetY = max(0, (baseSize.height - cropSide) / 2)
        scrollView.contentOffset = CGPoint(x: offsetX, y: offsetY)
    }

    private func updateInsets(_ scrollView: UIScrollView) {
        let bounds = scrollView.bounds.size
        let size = scrollView.contentSize
        let insetX = max((bounds.width - size.width) / 2, 0)
        let insetY = max((bounds.height - size.height) / 2, 0)
        scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
        scrollView.scrollIndicatorInsets = scrollView.contentInset
    }

    private func clampOffsets(_ scrollView: UIScrollView) {
        let size = scrollView.contentSize
        let bounds = scrollView.bounds.size
        let inset = scrollView.contentInset
        let maxX = max(-inset.left, size.width - bounds.width + inset.right)
        let maxY = max(-inset.top, size.height - bounds.height + inset.bottom)
        let minX = -inset.left
        let minY = -inset.top
        let clampedX = min(max(scrollView.contentOffset.x, minX), maxX)
        let clampedY = min(max(scrollView.contentOffset.y, minY), maxY)
        if clampedX != scrollView.contentOffset.x || clampedY != scrollView.contentOffset.y {
            scrollView.contentOffset = CGPoint(x: clampedX, y: clampedY)
        }
    }
}

private struct ZoomableCropView: UIViewRepresentable {
    @ObservedObject var controller: CropController
    let cropSide: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        scrollView.bouncesZoom = true
        scrollView.decelerationRate = .fast
        scrollView.clipsToBounds = true
        scrollView.delegate = context.coordinator
        scrollView.pinchGestureRecognizer?.isEnabled = false

        let contentView = UIView()
        contentView.backgroundColor = .clear
        let imageView = UIImageView(image: controller.image)
        imageView.contentMode = .scaleAspectFill
        contentView.addSubview(imageView)
        scrollView.addSubview(contentView)

        controller.scrollView = scrollView
        controller.contentView = contentView
        controller.imageView = imageView

        scrollView.frame = CGRect(origin: .zero, size: CGSize(width: cropSide, height: cropSide))
        controller.updateLayout()
        context.coordinator.lastBoundsSize = scrollView.bounds.size

        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        var needsLayout = false
        if let imageView = controller.imageView {
            if imageView.image !== controller.image {
                imageView.image = controller.image
                needsLayout = true
            }
        }
        uiView.frame = CGRect(origin: .zero, size: CGSize(width: cropSide, height: cropSide))
        if needsLayout || context.coordinator.lastBoundsSize != uiView.bounds.size {
            controller.updateLayout()
            context.coordinator.lastBoundsSize = uiView.bounds.size
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        private let controller: CropController
        var lastBoundsSize: CGSize?

        init(controller: CropController) {
            self.controller = controller
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return controller.contentView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updateInsets(scrollView)
            clampOffsets(scrollView)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            clampOffsets(scrollView)
        }

        private func clampOffsets(_ scrollView: UIScrollView) {
            let size = scrollView.contentSize
            let bounds = scrollView.bounds.size
            let inset = scrollView.contentInset
            let maxX = max(-inset.left, size.width - bounds.width + inset.right)
            let maxY = max(-inset.top, size.height - bounds.height + inset.bottom)
            let minX = -inset.left
            let minY = -inset.top
            let clampedX = min(max(scrollView.contentOffset.x, minX), maxX)
            let clampedY = min(max(scrollView.contentOffset.y, minY), maxY)
            if clampedX != scrollView.contentOffset.x || clampedY != scrollView.contentOffset.y {
                scrollView.contentOffset = CGPoint(x: clampedX, y: clampedY)
            }
        }

        private func updateInsets(_ scrollView: UIScrollView) {
            let bounds = scrollView.bounds.size
            let size = scrollView.contentSize
            let insetX = max((bounds.width - size.width) / 2, 0)
            let insetY = max((bounds.height - size.height) / 2, 0)
            scrollView.contentInset = UIEdgeInsets(top: insetY, left: insetX, bottom: insetY, right: insetX)
            scrollView.scrollIndicatorInsets = scrollView.contentInset
        }
    }
}

private struct PinchZoomOverlay: UIViewRepresentable {
    @ObservedObject var controller: CropController

    func makeUIView(context: Context) -> WindowPinchView {
        let view = WindowPinchView()
        view.backgroundColor = .clear
        view.onPinch = { delta, _ in
            controller.applyZoom(delta: delta)
        }
        view.onPan = { delta in
            controller.applyPan(delta: delta)
        }
        return view
    }

    func updateUIView(_ uiView: WindowPinchView, context: Context) {}
}

private final class WindowPinchView: UIView, UIGestureRecognizerDelegate {
    var onPinch: ((CGFloat, CGPoint) -> Void)?
    var onPan: ((CGPoint) -> Void)?
    private var lastScale: CGFloat = 1
    private var lastLocation: CGPoint = .zero
    private var isActive = false
    private weak var pinchRecognizer: UIPinchGestureRecognizer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window, pinchRecognizer == nil {
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = false
            pinch.delegate = self
            window.addGestureRecognizer(pinch)
            pinchRecognizer = pinch
        } else if window == nil, let pinchRecognizer {
            pinchRecognizer.view?.removeGestureRecognizer(pinchRecognizer)
            self.pinchRecognizer = nil
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let window else { return }
        let locationInWindow = recognizer.location(in: window)
        let location = convert(locationInWindow, from: window)
        switch recognizer.state {
        case .began:
            isActive = bounds.contains(location)
            lastScale = 1
            lastLocation = location
        case .changed:
            guard isActive else { return }
            let delta = recognizer.scale / lastScale
            lastScale = recognizer.scale
            onPinch?(delta, location)
            let move = CGPoint(x: location.x - lastLocation.x, y: location.y - lastLocation.y)
            lastLocation = location
            if move != .zero {
                onPan?(move)
            }
        default:
            isActive = false
            lastScale = 1
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        false
    }
}

private struct CropHandlesView: View {
    @Binding var cropRect: CGRect
    let bounds: CGRect

    private let minSide: CGFloat = 80
    @State private var dragStart: CGRect?
    @State private var resizeStart: CGRect?
    @State private var activeAnchor: Anchor?

    var body: some View {
        let handleSize: CGFloat = 26
        let cornerOffset: CGFloat = handleSize / 2

        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .contentShape(Rectangle())
                .gesture(dragCropGesture())

            handle(at: CGPoint(x: cropRect.minX, y: cropRect.minY), size: handleSize)
                .gesture(resizeGesture(anchor: .topLeft))
            handle(at: CGPoint(x: cropRect.maxX, y: cropRect.minY), size: handleSize)
                .gesture(resizeGesture(anchor: .topRight))
            handle(at: CGPoint(x: cropRect.minX, y: cropRect.maxY), size: handleSize)
                .gesture(resizeGesture(anchor: .bottomLeft))
            handle(at: CGPoint(x: cropRect.maxX, y: cropRect.maxY), size: handleSize)
                .gesture(resizeGesture(anchor: .bottomRight))
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private func handle(at point: CGPoint, size: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .position(x: point.x, y: point.y)
    }

    private func dragCropGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = cropRect
                }
                guard let start = dragStart else { return }
                var rect = start
                rect.origin.x += value.translation.width
                rect.origin.y += value.translation.height
                cropRect = clamped(rect: rect)
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private enum Anchor {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    private func resizeGesture(anchor: Anchor) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeStart == nil {
                    resizeStart = cropRect
                    activeAnchor = anchor
                }
                guard let start = resizeStart else { return }
                var rect = start
                let delta = max(value.translation.width, value.translation.height)
                switch anchor {
                case .topLeft:
                    rect.origin.x += delta
                    rect.origin.y += delta
                    rect.size.width -= delta
                    rect.size.height -= delta
                case .topRight:
                    rect.origin.y += delta
                    rect.size.width += delta
                    rect.size.height -= delta
                case .bottomLeft:
                    rect.origin.x += delta
                    rect.size.width -= delta
                    rect.size.height += delta
                case .bottomRight:
                    rect.size.width += delta
                    rect.size.height += delta
                }
                rect = enforceSquare(rect)
                cropRect = clamped(rect: rect)
            }
            .onEnded { _ in
                resizeStart = nil
                activeAnchor = nil
            }
    }

    private func enforceSquare(_ rect: CGRect) -> CGRect {
        let side = max(minSide, min(rect.width, rect.height))
        return CGRect(x: rect.origin.x, y: rect.origin.y, width: side, height: side)
    }

    private func clamped(rect: CGRect) -> CGRect {
        var rect = rect
        rect.size.width = max(minSide, rect.size.width)
        rect.size.height = rect.size.width
        let maxX = bounds.maxX - rect.size.width
        let maxY = bounds.maxY - rect.size.height
        rect.origin.x = min(max(rect.origin.x, bounds.minX), maxX)
        rect.origin.y = min(max(rect.origin.y, bounds.minY), maxY)
        return rect
    }
}

private struct RotateTickControl: View {
    @ObservedObject var controller: CropController
    @State private var lastHapticStep: Int = 0
    private let feedback = UISelectionFeedbackGenerator()

    private let range: ClosedRange<Double> = -90...90
    private let stepDegrees: Double = 1
    private var normalizedPosition: Double {
        let clamped = min(max(controller.rotationDegrees, range.lowerBound), range.upperBound)
        return (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Rotate")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.75))

                Text("\(Int(controller.rotationDegrees.rounded()))°")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.75))
            }

            ZStack {
                RotateTickMarks()
                RotateIndicator(position: normalizedPosition)
            }
            .frame(width: 260, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let width: CGFloat = 260
                        let x = min(max(value.location.x, 0), width)
                        let t = Double(x / width)
                        let degrees = range.lowerBound + t * (range.upperBound - range.lowerBound)
                        let step = Int((degrees / stepDegrees).rounded())
                        if step != lastHapticStep {
                            lastHapticStep = step
                            feedback.selectionChanged()
                            controller.setRotationPreview(degrees: Double(step) * stepDegrees)
                        }
                    }
                    .onEnded { _ in
                        feedback.prepare()
                        controller.commitRotation()
                    }
            )
            .onAppear { feedback.prepare() }
        }
    }
}

private struct RotateTickMarks: View {
    var body: some View {
        GeometryReader { geo in
            let count = 41
            let spacing = geo.size.width / CGFloat(count - 1)
            let center = count / 2
            ForEach(0..<count, id: \.self) { index in
                let isCenter = index == center
                Rectangle()
                    .fill(Color.primary.opacity(isCenter ? 0.9 : 0.35))
                    .frame(width: 2, height: isCenter ? 10 : 6)
                    .position(x: CGFloat(index) * spacing, y: geo.size.height / 2)
            }
        }
    }
}

private struct RotateIndicator: View {
    let position: Double

    var body: some View {
        GeometryReader { geo in
            let x = CGFloat(position) * geo.size.width
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white)
                .frame(width: 3, height: 14)
                .position(x: x, y: geo.size.height / 2)
        }
    }
}

private extension UIImage {
    private func makeRenderer(size: CGSize) -> UIGraphicsImageRenderer? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    func compressedJPEGData(targetBytes: Int, minQuality: CGFloat = 0.35) -> Data? {
        let maxBytes = max(10_000, targetBytes)
        var working = self
        var quality: CGFloat = 0.9

        for _ in 0..<3 {
            quality = 0.9
            if let data = working.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
            while quality > minQuality {
                quality -= 0.07
                if let data = working.jpegData(compressionQuality: quality), data.count <= maxBytes {
                    return data
                }
            }

            guard let data = working.jpegData(compressionQuality: minQuality) else { break }
            if data.count <= maxBytes {
                return data
            }
            let ratio = sqrt(CGFloat(maxBytes) / CGFloat(max(data.count, 1)))
            let scale = min(0.9, max(0.6, ratio))
            let newSize = CGSize(width: working.size.width * scale, height: working.size.height * scale)
            guard let resized = working.resized(to: newSize) else { break }
            working = resized
        }

        return working.jpegData(compressionQuality: minQuality)
    }

    private func resized(to size: CGSize) -> UIImage? {
        guard let renderer = makeRenderer(size: size) else { return nil }
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func normalizedImage() -> UIImage {
        if imageOrientation == .up { return self }
        guard let renderer = makeRenderer(size: size) else { return self }
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func rotatedRight() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        guard let renderer = makeRenderer(size: newSize) else { return self }
        return renderer.image { context in
            context.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }

    func rotated(byDegrees degrees: Double) -> UIImage {
        let radians = CGFloat(degrees * Double.pi / 180)
        let newBounds = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
            .integral
        let newSize = CGSize(width: abs(newBounds.width), height: abs(newBounds.height))
        guard let renderer = makeRenderer(size: newSize) else { return self }
        return renderer.image { context in
            context.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.cgContext.rotate(by: radians)
            draw(in: CGRect(
                x: -size.width / 2,
                y: -size.height / 2,
                width: size.width,
                height: size.height
            ))
        }
    }
}

private enum ProfileExtrasStore {
    private static let phoneKey = "recai.profile.phone"
    private static let locationKey = "recai.profile.location"
    private static let bioKey = "recai.profile.bio"
    private static let websiteKey = "recai.profile.website"
    private static let photoKey = "recai.profile.photo"

    static func loadPhoneNumber() -> String {
        UserDefaults.standard.string(forKey: phoneKey) ?? ""
    }

    static func loadLocation() -> String {
        UserDefaults.standard.string(forKey: locationKey) ?? ""
    }

    static func loadBio() -> String {
        UserDefaults.standard.string(forKey: bioKey) ?? ""
    }

    static func loadWebsite() -> String {
        UserDefaults.standard.string(forKey: websiteKey) ?? ""
    }

    static func loadProfileImageData() -> Data? {
        UserDefaults.standard.data(forKey: photoKey)
    }

    static func save(
        phoneNumber: String,
        location: String,
        bio: String,
        website: String,
        photoData: Data?
    ) {
        UserDefaults.standard.set(phoneNumber, forKey: phoneKey)
        UserDefaults.standard.set(location, forKey: locationKey)
        UserDefaults.standard.set(bio, forKey: bioKey)
        UserDefaults.standard.set(website, forKey: websiteKey)
        if let photoData {
            UserDefaults.standard.set(photoData, forKey: photoKey)
        } else {
            UserDefaults.standard.removeObject(forKey: photoKey)
        }
    }

    static func loadProfileImage(data: Data? = nil) -> Image? {
        let resolved = data ?? loadProfileImageData()
        guard let resolved, let uiImage = UIImage(data: resolved) else { return nil }
        return Image(uiImage: uiImage)
    }

    static func loadProfileImage() -> Image? {
        loadProfileImage(data: nil)
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
        .transaction { $0.disablesAnimations = true }
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

    private var locationCard: some View {
        let textFieldShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
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

        return settingsCard(content)
    }

    private var appearanceCard: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
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
        return settingsCard(content)
    }

    private var captureCard: some View {
        let content = VStack(alignment: .leading, spacing: 12) {
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

            Toggle("Allow web search for local rules", isOn: allowWebSearchBinding)
                .font(AppType.body(13))
                .foregroundStyle(.primary)
                .tint(AppTheme.mint)
        }
        return settingsCard(content)
    }


    private func settingsCard<Content: View>(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return content
            .padding(16)
            .background(
                shape.fill(AppTheme.cardGradient)
            )
            .overlay(
                shape.stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .transaction { $0.disablesAnimations = true }
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
        .accountCard(cornerRadius: 18)
        .opacity(unlocked ? 1.0 : 0.55)
    }
}

// MARK: - Account card styling
// NOTE: Use static backgrounds instead of ultraThinMaterial here.
// Dynamic materials flash during scrolling and state updates on this screen.
private extension View {
    func accountCard(cornerRadius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(shape.fill(AppTheme.cardGradient))
            .overlay(shape.stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .transaction { $0.disablesAnimations = true }
    }
}

#Preview {
    AccountView()
        .environmentObject(AuthStore())
        .environmentObject(HistoryStore())
}
