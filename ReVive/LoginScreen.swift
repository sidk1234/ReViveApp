//
//  LoginScreen.swift
//  Recyclability
//

import SwiftUI
import UIKit
import GoogleSignIn

private enum AuthField: Hashable {
    case email
    case password
    case confirmPassword
}

struct LoginScreen: View {
    enum AuthMode: Int, Hashable {
        case signIn
        case create
    }

    @EnvironmentObject private var auth: AuthStore
    @State private var mode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var notice: String?
    @FocusState private var focusedField: AuthField?

    private var isCreate: Bool { mode == .create }

    var body: some View {
        AuthShell(isCreate: isCreate) {
            authCard
        }
        .task {
            auth.refreshGuestQuota()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedField = nil
                }
                .font(AppType.body(13))
                .foregroundStyle(AppTheme.mint)
            }
        }
    }

    private var authCard: some View {
        ZStack {
            if mode == .signIn {
                signInCard
                    .transition(.opacity)
            } else {
                createCard
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: mode)
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Sign in")
                    .font(AppType.title(22))
                    .foregroundStyle(.primary)

                Spacer()

                Text("New here?")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.7))
                Button("Create one") {
                    switchMode(.create)
                }
                .font(AppType.body(12))
                .foregroundStyle(AppTheme.mint)
                .buttonStyle(.plain)
            }

            AuthTextField(
                label: "Email",
                placeholder: "you@email.com",
                text: $email,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                isSecure: false,
                submitLabel: .next,
                onSubmit: { focusedField = .password },
                field: .email,
                focus: $focusedField
            )

            AuthTextField(
                label: "Password",
                placeholder: "Enter your password",
                text: $password,
                keyboard: .default,
                contentType: .password,
                isSecure: true,
                submitLabel: .done,
                onSubmit: { focusedField = nil },
                field: .password,
                focus: $focusedField
            )

            HStack {
                Spacer()
                Button("Forgot password?") {
                    Task { @MainActor in
                        notice = nil
                        let ok = await auth.sendPasswordReset(email: email)
                        if ok {
                            notice = "Password reset email sent."
                        }
                    }
                }
                .font(AppType.body(12))
                .foregroundStyle(AppTheme.mint)
                .buttonStyle(.plain)
            }

            AuthMessageView(errorMessage: auth.displayErrorMessage, notice: notice)

            Button {
                submitSignIn()
            } label: {
                HStack {
                    Spacer()
                    Text(auth.isLoading ? "Please wait..." : "Sign in")
                        .font(AppType.title(15))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(auth.isLoading)

            AuthDividerRow()

            AuthSocialButtons(
                isLoading: auth.isLoading,
                onGoogle: signInWithGoogle,
                onApple: auth.signInWithApple
            )

            AuthLegalRow()
                .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: 420)
        .glassCard(cornerRadius: 24)
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Create account")
                    .font(AppType.title(22))
                    .foregroundStyle(.primary)

                Spacer()

                Text("Have an account?")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.7))
                Button("Sign in") {
                    switchMode(.signIn)
                }
                .font(AppType.body(12))
                .foregroundStyle(AppTheme.mint)
                .buttonStyle(.plain)
            }

            AuthTextField(
                label: "Email",
                placeholder: "you@email.com",
                text: $email,
                keyboard: .emailAddress,
                contentType: .emailAddress,
                isSecure: false,
                submitLabel: .next,
                onSubmit: { focusedField = .password },
                field: .email,
                focus: $focusedField
            )

            AuthTextField(
                label: "Password",
                placeholder: "Create a password",
                text: $password,
                keyboard: .default,
                contentType: .newPassword,
                isSecure: true,
                submitLabel: .next,
                onSubmit: { focusedField = .confirmPassword },
                field: .password,
                focus: $focusedField
            )

            AuthTextField(
                label: "Confirm password",
                placeholder: "Re-enter your password",
                text: $confirmPassword,
                keyboard: .default,
                contentType: .newPassword,
                isSecure: true,
                submitLabel: .done,
                onSubmit: { focusedField = nil },
                field: .confirmPassword,
                focus: $focusedField
            )

            AuthMessageView(errorMessage: auth.displayErrorMessage, notice: notice)

            Button {
                submitCreate()
            } label: {
                HStack {
                    Spacer()
                    Text(auth.isLoading ? "Please wait..." : "Create account")
                        .font(AppType.title(15))
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(auth.isLoading)

            AuthDividerRow()

            AuthSocialButtons(
                isLoading: auth.isLoading,
                onGoogle: signInWithGoogle,
                onApple: auth.signInWithApple
            )

            AuthLegalRow()
                .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: 420)
        .glassCard(cornerRadius: 24)
    }

    private func submitSignIn() {
        notice = nil
        auth.errorMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || password.isEmpty {
            auth.errorMessage = "Email and password are required."
            return
        }

        auth.signInWithEmail(email: trimmedEmail, password: password)
    }

    private func submitCreate() {
        notice = nil
        auth.errorMessage = nil

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty || password.isEmpty {
            auth.errorMessage = "Email and password are required."
            return
        }

        guard password == confirmPassword else {
            auth.errorMessage = "Passwords do not match."
            return
        }

        guard password.count >= 6 else {
            auth.errorMessage = "Password must be at least 6 characters."
            return
        }

        auth.signUpWithEmail(email: trimmedEmail, password: password)
    }

    private func switchMode(_ newMode: AuthMode) {
        guard mode != newMode else { return }
        notice = nil
        auth.errorMessage = nil
        confirmPassword = ""
        focusedField = nil
        mode = newMode
    }

    private func signInWithGoogle() {
        guard let presenter = UIApplication.shared.topMostViewController() else {
            auth.errorMessage = "Unable to present sign-in (no active window)."
            return
        }
        auth.signInWithGoogle(presenting: presenter)
    }
}

private struct AuthShell<Right: View>: View {
    @EnvironmentObject private var auth: AuthStore

    let isCreate: Bool
    private let rightPane: Right

    init(isCreate: Bool, @ViewBuilder rightPane: () -> Right) {
        self.isCreate = isCreate
        self.rightPane = rightPane()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                let isWide = proxy.size.width > 720
                Group {
                    if isWide {
                        HStack(alignment: .top, spacing: 36) {
                            AuthLeftPane(isCreate: isCreate, quota: auth.guestQuota)
                            rightPane
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 28) {
                            AuthLeftPane(isCreate: isCreate, quota: auth.guestQuota)
                            rightPane
                        }
                    }
                }
                .frame(maxWidth: 980, alignment: .center)
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 120)
            }
        }
    }
}

private struct AuthLeftPane: View {
    let isCreate: Bool
    let quota: GuestQuota?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("SECURE ACCESS")
                .font(AppType.body(12))
                .foregroundStyle(AppTheme.mint.opacity(0.85))
                .tracking(2)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )

            Text(isCreate ? "Create your account" : "Welcome back")
                .font(AppType.display(34))
                .foregroundStyle(.primary)

            Text(isCreate
                 ? "Create an account to sync your recycling impact across devices."
                 : "Sign in to continue tracking your recycling impact.")
                .font(AppType.body(14))
                .foregroundStyle(.primary.opacity(0.7))

            VStack(alignment: .leading, spacing: 10) {
                AuthBulletRow("Track recycling totals across devices.")
                AuthBulletRow("Sync profile details for your dashboard.")
                AuthBulletRow("Keep credentials protected with Supabase Auth.")
            }

            if let quota {
                Text("Guest access: \(quota.remaining) of \(quota.limit) scans left today.")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.7))
            }
        }
        .frame(maxWidth: 420, alignment: .leading)
    }
}

private struct AuthTextField: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let contentType: UITextContentType?
    let isSecure: Bool
    let submitLabel: SubmitLabel
    let onSubmit: (() -> Void)?
    let field: AuthField
    let focus: FocusState<AuthField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.7))

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .textContentType(contentType)
            .submitLabel(submitLabel)
            .onSubmit {
                onSubmit?()
            }
            .textFieldStyle(.plain)
            .foregroundStyle(.primary)
            .tint(AppTheme.mint)
            .focused(focus, equals: field)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(
                Group {
                    if colorScheme == .dark {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.2), lineWidth: 1)
            )
        }
    }
}

private struct AuthDividerRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
            Text("or continue with")
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.6))
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
    }
}

private struct AuthSocialButtons: View {
    let isLoading: Bool
    let onGoogle: () -> Void
    let onApple: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            GoogleBrandedSignInButton(isLoading: isLoading, action: onGoogle)

            Button {
                onApple()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "applelogo")
                    Text("Continue with Apple")
                        .font(AppType.title(14))
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .liquidGlassButton(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }
}

private struct GoogleBrandedSignInButton: View {
    let isLoading: Bool
    let action: () -> Void

    private let fillColor = Color(red: 19 / 255, green: 19 / 255, blue: 20 / 255) // #131314
    private let strokeColor = Color(red: 142 / 255, green: 145 / 255, blue: 143 / 255) // #8E918F
    private let textColor = Color(red: 227 / 255, green: 227 / 255, blue: 227 / 255) // #E3E3E3

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GoogleLogoBadge()
                Text("Sign in with Google")
                    .font(googleButtonFont)
                    .foregroundStyle(textColor)
            }
            .padding(.leading, 16)
            .padding(.trailing, 16)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(fillColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(strokeColor, lineWidth: 1)
        )
        .opacity(isLoading ? 0.6 : 1)
        .allowsHitTesting(!isLoading)
    }

    private var googleButtonFont: Font {
        if UIFont(name: "Roboto-Medium", size: 14) != nil {
            return .custom("Roboto-Medium", size: 14)
        }
        if UIFont(name: "Roboto-Bold", size: 14) != nil {
            return .custom("Roboto-Bold", size: 14)
        }
        return .system(size: 14, weight: .medium)
    }
}

private struct GoogleLogoBadge: View {
    private let logoSize: CGFloat = 18

    var body: some View {
        if let image = GoogleBrandAssets.logo {
            Image(uiImage: image)
                .resizable()
                .renderingMode(.original)
                .frame(width: logoSize, height: logoSize)
        } else {
            Text("G")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255))
        }
    }
}

private enum GoogleBrandAssets {
    static let logo: UIImage? = {
        let candidates = googleResourceBundleCandidates()
        for bundle in candidates {
            if let image = UIImage(named: "google", in: bundle, compatibleWith: nil) {
                return image
            }
            if let path = bundle.path(forResource: "google", ofType: "png"),
               let image = UIImage(contentsOfFile: path) {
                return image
            }
        }
        if let image = UIImage(named: "google") {
            return image
        }
        return nil
    }()

    private static func googleResourceBundleCandidates() -> [Bundle] {
        var bundles: [Bundle] = []
        let bundleNames = ["GoogleSignIn_GoogleSignIn", "GoogleSignIn"]
        for name in bundleNames {
            if let path = Bundle.main.path(forResource: name, ofType: "bundle"),
               let bundle = Bundle(path: path) {
                bundles.append(bundle)
            }
        }
        let frameworkBundle = Bundle(for: GIDSignInButton.self)
        for name in bundleNames {
            if let path = frameworkBundle.path(forResource: name, ofType: "bundle"),
               let bundle = Bundle(path: path) {
                bundles.append(bundle)
            }
        }
        bundles.append(frameworkBundle)
        return bundles
    }
}

private struct AuthMessageView: View {
    let errorMessage: String?
    let notice: String?

    var body: some View {
        if let message = errorMessage, !message.isEmpty {
            Text(message)
                .font(AppType.body(12))
                .foregroundStyle(Color.white.opacity(0.9))
        } else if let notice {
            Text(notice)
                .font(AppType.body(12))
                .foregroundStyle(AppTheme.mint.opacity(0.85))
        }
    }
}

private struct AuthBulletRow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(AppTheme.mint)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.75))
        }
    }
}

private struct AuthLegalRow: View {
    var body: some View {
        Text(legalText)
            .font(AppType.body(11))
            .foregroundStyle(.primary.opacity(0.6))
    }

    private var legalText: AttributedString {
        var text = AttributedString("By continuing, you agree to the Terms of Service and Privacy Policy.")

        if let range = text.range(of: "Terms of Service") {
            text[range].link = URL(string: "https://reviveearth.vercel.app/terms")
            text[range].foregroundColor = .blue
            text[range].underlineStyle = .single
        }

        if let range = text.range(of: "Privacy Policy") {
            text[range].link = URL(string: "https://reviveearth.vercel.app/policy")
            text[range].foregroundColor = .blue
            text[range].underlineStyle = .single
        }

        return text
    }
}

#Preview {
    LoginScreen()
        .environmentObject(AuthStore())
        .preferredColorScheme(.dark)
}
