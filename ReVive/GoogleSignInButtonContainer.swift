//
//  GoogleSignInButtonContainer.swift
//  Recyclability
//

import SwiftUI
import GoogleSignIn

struct GoogleSignInButtonView: View {
    var body: some View {
        GoogleSignInButtonContainer()
            .frame(maxWidth: .infinity)
            .frame(height: 48)
    }
}

struct GoogleSignInButtonContainer: UIViewControllerRepresentable {
    @EnvironmentObject private var auth: AuthStore

    func makeUIViewController(context: Context) -> ButtonHostController {
        let controller = ButtonHostController()
        controller.onTap = { [weak auth, weak controller] in
            guard let controller else { return }
            auth?.signInWithGoogle(presenting: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ButtonHostController, context: Context) {
        uiViewController.isLoading = auth.isLoading
        uiViewController.refreshStyle()
    }
}

final class ButtonHostController: UIViewController {
    private let button = GIDSignInButton()
    var onTap: (() -> Void)?

    var isLoading: Bool = false {
        didSet {
            button.isEnabled = !isLoading
            button.alpha = isLoading ? 0.6 : 1.0
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .dark

        applyGoogleStyle()
        button.addTarget(self, action: #selector(handleTap), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyGoogleStyle()
    }

    func refreshStyle() {
        applyGoogleStyle()
    }

    private func applyGoogleStyle() {
        button.style = .wide
        button.colorScheme = .dark
        button.overrideUserInterfaceStyle = .dark
    }

    @objc private func handleTap() {
        onTap?()
    }
}
