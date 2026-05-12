import SwiftUI

struct PasswordRecoveryView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedField: Field?
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var notice: String?

    private enum Field {
        case password
        case confirmPassword
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient(colorScheme)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Reset password")
                            .font(AppType.display(28))
                            .foregroundStyle(.primary)

                        Text("Choose a new password to finish resetting your account inside ReVive.")
                            .font(AppType.body(13))
                            .foregroundStyle(.primary.opacity(0.72))

                        passwordField(
                            title: "New password",
                            placeholder: "Create a new password",
                            text: $password,
                            field: .password,
                            submitLabel: .next
                        ) {
                            focusedField = .confirmPassword
                        }

                        passwordField(
                            title: "Confirm password",
                            placeholder: "Re-enter your new password",
                            text: $confirmPassword,
                            field: .confirmPassword,
                            submitLabel: .done
                        ) {
                            focusedField = nil
                            submit()
                        }

                        if let message = auth.displayErrorMessage, !message.isEmpty {
                            Text(message)
                                .font(AppType.body(12))
                                .foregroundStyle(.red.opacity(0.95))
                        } else if let notice, !notice.isEmpty {
                            Text(notice)
                                .font(AppType.body(12))
                                .foregroundStyle(AppTheme.mint)
                        }

                        Button {
                            submit()
                        } label: {
                            HStack {
                                Spacer()
                                Text(auth.isLoading ? "Updating..." : "Update password")
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
                    }
                    .padding(24)
                }
            }
            .onAppear {
                focusedField = .password
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        auth.dismissPasswordRecovery()
                        dismiss()
                    }
                }
            }
        }
    }

    private func submit() {
        notice = nil
        auth.errorMessage = nil

        Task { @MainActor in
            let ok = await auth.completePasswordRecovery(
                newPassword: password,
                confirmPassword: confirmPassword
            )
            if ok {
                notice = "Password updated."
                dismiss()
            }
        }
    }

    private func passwordField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        submitLabel: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppType.body(12))
                .foregroundStyle(.primary.opacity(0.75))

            SecureField(placeholder, text: text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .textContentType(.newPassword)
                .submitLabel(submitLabel)
                .focused($focusedField, equals: field)
                .onSubmit(onSubmit)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
