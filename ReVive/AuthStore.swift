//
//  AuthStore.swift
//  Recyclability
//

import SwiftUI
import AuthenticationServices
import UIKit
import CryptoKit
import GoogleSignIn
import Security
import Combine
import StoreKit

// MARK: - Logging

private enum AuthLog {
    static func info(_ message: String) { print("ℹ️ [AuthStore] \(message)") }
    static func warn(_ message: String) { print("⚠️ [AuthStore] \(message)") }
    static func error(_ message: String) { print("❌ [AuthStore] \(message)") }
}

@MainActor
final class AuthStore: NSObject, ObservableObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    @Published var session: SupabaseSession?
    @Published var user: SupabaseUser?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var isAdmin: Bool = false
    @Published var photoStorageEnabled: Bool = false
    @Published var preferences: UserPreferences = .default
    @Published var isShowingPasswordRecovery: Bool = false
    @Published var guestQuota: GuestQuota? {
        didSet {
            saveGuestQuota(guestQuota)
        }
    }
    @Published var hasActiveSubscription: Bool = false
    @Published private(set) var didResolveSubscriptionState: Bool = false
    @Published private(set) var signedInQuotaRemaining: Int?
    @Published private(set) var guestQuotaLimit: Int = 5
    @Published private(set) var signedInFreeQuotaLimit: Int = 25
    @Published private(set) var proMonthlyPriceCents: Int = 199
    @Published private(set) var proBillingURL: String?
    @Published private(set) var proPortalURL: String?
    @Published private(set) var shouldOfferTutorialAfterSignup: Bool = false
    @Published private(set) var lastKnownSignedInUserID: String?
    @Published private(set) var subscriptionProduct: Product?
    @Published private(set) var isLoadingSubscriptionProduct: Bool = false
    @Published private(set) var isPurchasingSubscription: Bool = false
    @Published private(set) var isRestoringPurchases: Bool = false

    var displayErrorMessage: String? {
        guard let message = errorMessage, !message.isEmpty else { return nil }
        if Self.showTechnicalErrors {
            return message
        }
        let sanitized = Self.sanitizeErrorForUI(message)
        return sanitized.isEmpty ? message : sanitized
    }

    private static var showTechnicalErrors: Bool {
        if let flag = Bundle.main.object(forInfoDictionaryKey: "SHOW_TECH_ERRORS") as? Bool {
            return flag
        }
        if let flag = Bundle.main.object(forInfoDictionaryKey: "SHOW_TECH_ERRORS") as? String {
            let trimmed = flag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed == "true" || trimmed == "1" || trimmed == "yes"
        }
        return false
    }

    private static func sanitizeErrorForUI(_ message: String) -> String {
        var cleaned = message
        cleaned = cleaned.replacingOccurrences(
            of: "Supabase HTTP \\d+:\\s*",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "HTTP \\d+:\\s*",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\s*\\([^\\)]*\\d+\\)",
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSignedIn: Bool { session != nil }
    var preferredColorScheme: ColorScheme? { preferences.appearanceMode?.colorScheme }
    var enableHaptics: Bool { preferences.enableHaptics ?? true }
    var showCaptureInstructions: Bool { preferences.showCaptureInstructions ?? true }
    var autoSyncImpactEnabled: Bool { true }
    var reduceMotionEnabled: Bool { preferences.reduceMotion ?? false }
    var defaultZipCode: String { preferences.defaultZip ?? "" }
    var canEditEmailPassword: Bool {
        let providers = user?.authProviders.map { $0.lowercased() } ?? []
        guard !providers.isEmpty else { return false }
        let hasEmail = providers.contains("email")
        let hasSocial = providers.contains("google") || providers.contains("apple")
        return hasEmail && !hasSocial
    }
    var canAddPassword: Bool {
        let providers = user?.authProviders.map { $0.lowercased() } ?? []
        guard !providers.isEmpty else { return false }
        let hasSocial = providers.contains("google") || providers.contains("apple")
        let hasEmail = !(user?.email ?? "").isEmpty
        return hasSocial && hasEmail
    }
    var canUpdatePassword: Bool { canEditEmailPassword || canAddPassword }

    private let sessionKey = "recai.supabase.session"
    private let legacyPreferencesKey = "recai.user.preferences"
    private let guestPreferencesKey = "recai.user.preferences.guest"
    private let userPreferencesKeyPrefix = "recai.user.preferences.user."
    private let guestQuotaKey = "recai.guest.quota"
    private let guestQuotaFilename = "guest-quota.json"
    private let tutorialOfferKey = "recai.tutorial.offer_after_signup"
    private let lastSignedInUserIDKey = "recai.last_signed_in_user_id"
    private var notificationObservers: [NSObjectProtocol] = []
    private var currentNonce: String?
    private var needsProfileRefresh = false
    private var didAttemptGoogleRestore = false
    private var activePreferencesScope: PreferencesScope = .guest
    private var transactionUpdatesTask: Task<Void, Never>?
    private var lastMirroredSubscriptionState: (userID: String, isActive: Bool)?
    private var passwordRecoverySession: SupabaseSession?
    private var passwordRecoveryPreviousSession: SupabaseSession?

    private enum PreferencesScope: Equatable {
        case guest
        case user(String)
    }

    // ✅ Updated: validate + log missing config
    private var supabase: SupabaseService? {
        guard let config = SupabaseConfig.load() else {
            logMissingSupabaseConfig()
            return nil
        }

        if config.url.absoluteString.isEmpty {
            AuthLog.error("Supabase config loaded but URL is empty.")
            return nil
        }

        if config.anonKey.isEmpty {
            AuthLog.error("Supabase config loaded but anonKey is empty.")
            return nil
        }

        // NOTE: Your project previously compiled with `SupabaseService.init` mapping.
        // The screenshot you shared indicated your init expects `config:` label.
        return SupabaseService(config: config)
    }

    override init() {
        super.init()
        bindRuntimeNotifications()
        startTransactionUpdatesListener()
        loadPreferences()
        loadGuestQuota()
        shouldOfferTutorialAfterSignup = UserDefaults.standard.bool(forKey: tutorialOfferKey)
        lastKnownSignedInUserID = UserDefaults.standard.string(forKey: lastSignedInUserIDKey)

        if SupabaseConfig.load() == nil {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.warn("App launched without Supabase configuration. \(diag.summary)")
        } else {
            AuthLog.info("Supabase configuration loaded successfully.")
        }

        restoreSession()
        Task { @MainActor [weak self] in
            await self?.loadSubscriptionProduct()
            _ = await self?.reconcileStoreKitSubscriptionState(syncToSupabase: false)
        }
    }

    var isStoreKitSubscriptionConfigured: Bool {
        BootstrapConfig.appStoreSubscriptionProductID != nil
    }

    var subscriptionDisplayPrice: String? {
        subscriptionProduct?.displayPrice
    }

    private func loadGuestQuota() {
        if let data = try? Data(contentsOf: guestQuotaURL()),
           let decoded = try? JSONDecoder().decode(GuestQuota.self, from: data) {
            guestQuota = normalizedGuestQuota(decoded)
            return
        }

        guard let data = UserDefaults.standard.data(forKey: guestQuotaKey) else { return }
        if let decoded = try? JSONDecoder().decode(GuestQuota.self, from: data) {
            guestQuota = normalizedGuestQuota(decoded)
            saveGuestQuota(guestQuota)
            UserDefaults.standard.removeObject(forKey: guestQuotaKey)
        }
    }

    private func normalizedGuestQuota(_ quota: GuestQuota) -> GuestQuota {
        let used = max(0, quota.used)
        let limit = quota.limit > 0 ? quota.limit : guestQuotaLimit
        let cappedUsed = min(used, limit)
        let remaining = max(0, limit - cappedUsed)
        return GuestQuota(used: cappedUsed, remaining: remaining, limit: limit)
    }

    private func applyCloudSubscriptionState(from profile: SupabaseUser, authoritativeIsPro: Bool?) {
        if let authoritativeIsPro {
            hasActiveSubscription = authoritativeIsPro
        } else if let cloudIsPro = profile.isProSubscriber {
            hasActiveSubscription = cloudIsPro
        }
        if hasActiveSubscription {
            signedInQuotaRemaining = nil
            return
        }

        if let cloudLimit = profile.signedInMonthlyQuotaLimit, cloudLimit > 0 {
            signedInFreeQuotaLimit = cloudLimit
        }

        if let cloudRemaining = profile.analysisQuotaRemaining {
            signedInQuotaRemaining = max(0, cloudRemaining)
            return
        }

        // Do not default to full quota when cloud state is unknown.
        // Keep existing value until server usage sync arrives.
        return
    }

    private func clearSignedInQuotaState() {
        signedInQuotaRemaining = nil
        hasActiveSubscription = false
        didResolveSubscriptionState = false
    }

    var signedInQuotaLimit: Int { signedInFreeQuotaLimit }
    var hasUnlimitedAnalysis: Bool { hasActiveSubscription }

    var remainingAnalysisRequests: Int? {
        if hasUnlimitedAnalysis {
            return nil
        }
        if !isSignedIn {
            return guestQuota?.remaining
        }
        return signedInQuotaRemaining
    }

    var isAnalysisQuotaExhausted: Bool {
        if hasUnlimitedAnalysis { return false }
        guard isSignedIn else {
            return (guestQuota?.remaining ?? 0) <= 0
        }
        guard let signedInQuotaRemaining else { return false }
        return signedInQuotaRemaining <= 0
    }

    @discardableResult
    func consumeAnalysisRequest() -> Bool {
        if hasUnlimitedAnalysis { return true }
        if !isSignedIn {
            return !isAnalysisQuotaExhausted
        }
        let current = max(0, signedInQuotaRemaining ?? signedInFreeQuotaLimit)
        guard current > 0 else {
            signedInQuotaRemaining = 0
            return false
        }
        if signedInQuotaRemaining != nil {
            signedInQuotaRemaining = max(0, current - 1)
        } else {
            signedInQuotaRemaining = max(0, signedInFreeQuotaLimit - 1)
        }
        return true
    }

    func applySignedInQuotaUpdate(_ update: SignedInQuotaUpdate) {
        if update.limit > 0 {
            signedInFreeQuotaLimit = update.limit
        }
        if let isPro = update.isPro {
            if isPro {
                hasActiveSubscription = true
            } else if !hasActiveSubscription {
                hasActiveSubscription = false
            }
        }
        if hasActiveSubscription {
            signedInQuotaRemaining = nil
        } else if let remaining = update.remaining {
            signedInQuotaRemaining = max(0, remaining)
        }
        if isSignedIn {
            didResolveSubscriptionState = true
        }
    }

    func applyGuestQuotaUpdate(_ quota: GuestQuota) {
        if quota.limit > 0 {
            guestQuotaLimit = quota.limit
        }
        guestQuota = normalizedGuestQuota(quota)
    }

    private func saveGuestQuota(_ quota: GuestQuota?) {
        let url = guestQuotaURL()
        if let quota, let data = try? JSONEncoder().encode(quota) {
            try? data.write(to: url, options: [.atomic])
            UserDefaults.standard.set(data, forKey: guestQuotaKey)
        } else {
            try? FileManager.default.removeItem(at: url)
            UserDefaults.standard.removeObject(forKey: guestQuotaKey)
        }
    }

    private func guestQuotaURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("ReVive", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent(guestQuotaFilename)
    }

    private func bindRuntimeNotifications() {
        let token = NotificationCenter.default.addObserver(
            forName: .reviveSignedQuotaUpdated,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.isSignedIn else { return }
                guard let update = note.object as? SignedInQuotaUpdate else { return }
                self.applySignedInQuotaUpdate(update)
            }
        }
        notificationObservers.append(token)
    }

    // ✅ Added: centralized diagnostic log
    private func logMissingSupabaseConfig(
        file: StaticString = #file,
        function: StaticString = #function,
        line: UInt = #line
    ) {
        let diag = SupabaseConfig.diagnostics()
        AuthLog.error("""
        Missing Supabase config (SupabaseConfig.load() returned nil).
        • Location: \(file):\(line)
        • Function: \(function)
        • Diagnostics: \(diag.summary)
        • Check:
          - Secrets / SupabaseConfig source is included in target
          - Build config (Debug vs Release) has the right values
          - Any required plist/json is in Copy Bundle Resources
        """)
    }

    func applyConfigIfAvailable() {
        guard supabase != nil else { return }
        refreshAppSettings()
        Task { @MainActor [weak self] in
            await self?.loadSubscriptionProduct()
            _ = await self?.reconcileStoreKitSubscriptionState()
        }
        if !isSignedIn {
            refreshGuestQuota()
        }
        if needsProfileRefresh {
            needsProfileRefresh = false
            Task { @MainActor [weak self] in
                await self?.loadUserAndProfile()
            }
        }
        if !didAttemptGoogleRestore {
            didAttemptGoogleRestore = true
            restoreGoogleSignIn()
        }
    }

    func loadSubscriptionProduct(force: Bool = false) async {
        guard let productID = BootstrapConfig.appStoreSubscriptionProductID else {
            subscriptionProduct = nil
            return
        }
        if !force, subscriptionProduct?.id == productID {
            return
        }

        isLoadingSubscriptionProduct = true
        defer { isLoadingSubscriptionProduct = false }

        do {
            subscriptionProduct = try await fetchSubscriptionProduct(productID: productID)
        } catch {
            subscriptionProduct = nil
            AuthLog.warn("Failed to load App Store product \(productID): \(error.localizedDescription)")
        }
    }

    func purchaseSubscription() async throws {
        guard let productID = BootstrapConfig.appStoreSubscriptionProductID else {
            throw StoreSubscriptionError.missingProductConfiguration
        }

        if subscriptionProduct?.id != productID {
            subscriptionProduct = nil
        }

        if subscriptionProduct == nil {
            subscriptionProduct = try await fetchSubscriptionProduct(productID: productID)
        }

        guard let product = subscriptionProduct else {
            throw StoreSubscriptionError.productLookupFailed(
                productID: productID,
                reason: "Product reference was nil after lookup.",
                code: "IAP-LOOKUP-NIL"
            )
        }

        isPurchasingSubscription = true
        defer { isPurchasingSubscription = false }

        var purchaseOptions: Set<Product.PurchaseOption> = []
        if let userID = user?.id, let accountUUID = UUID(uuidString: userID) {
            purchaseOptions.insert(.appAccountToken(accountUUID))
        }
        let result = try await product.purchase(options: purchaseOptions)
        switch result {
        case .success(let verification):
            let transaction = try verifiedTransaction(from: verification)
            await transaction.finish()
            let isActive = isTransactionEntitled(transaction)
            _ = await reconcileStoreKitSubscriptionState()
            if !isActive {
                throw StoreSubscriptionError.inactiveEntitlement
            }
        case .pending:
            throw StoreSubscriptionError.pending
        case .userCancelled:
            throw StoreSubscriptionError.userCancelled
        @unknown default:
            throw StoreSubscriptionError.unknown
        }
    }

    func restorePurchases() async throws {
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        try await AppStore.sync()
        let state = await reconcileStoreKitSubscriptionState()
        guard let hasActiveSubscription = state else {
            throw StoreSubscriptionError.missingProductConfiguration
        }
        guard hasActiveSubscription else {
            throw StoreSubscriptionError.noActiveSubscriptionToRestore
        }
    }

    func updateDefaultZip(_ zip: String) {
        var updated = preferences
        let filtered = zip.filter { $0.isNumber }
        let trimmed = String(filtered.prefix(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        updated.defaultZip = trimmed.isEmpty ? nil : trimmed
        applyPreferences(updated, sync: true)
    }

    func updateAppearanceMode(_ mode: AppAppearanceMode) {
        var updated = preferences
        updated.appearanceMode = mode
        applyPreferences(updated, sync: true)
    }

    func updateEnableHaptics(_ enabled: Bool) {
        var updated = preferences
        updated.enableHaptics = enabled
        applyPreferences(updated, sync: true)
    }

    func updateShowCaptureInstructions(_ enabled: Bool) {
        var updated = preferences
        updated.showCaptureInstructions = enabled
        applyPreferences(updated, sync: true)
    }

    func updateAutoSyncImpact(_ enabled: Bool) {
        var updated = preferences
        updated.autoSyncImpact = enabled
        applyPreferences(updated, sync: true)
    }

    func updateReduceMotion(_ enabled: Bool) {
        var updated = preferences
        updated.reduceMotion = enabled
        applyPreferences(updated, sync: true)
    }

    private func loadPreferences() {
        if case .guest = activePreferencesScope {
            migrateLegacyGuestPreferencesIfNeeded()
        }

        let key = preferencesKey(for: activePreferencesScope)
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONDecoder().decode(UserPreferences.self, from: data)
        else {
            preferences = .default
            return
        }
        preferences = stored
    }

    private func savePreferences(_ preferences: UserPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        let key = preferencesKey(for: activePreferencesScope)
        UserDefaults.standard.set(data, forKey: key)
    }

    private func applyPreferences(_ preferences: UserPreferences, sync: Bool) {
        if self.preferences != preferences {
            self.preferences = preferences
        }
        savePreferences(preferences)
        if sync {
            pushPreferencesToServer(preferences)
        }
    }

    private func syncPreferencesIfNeeded(remote: UserPreferences?) {
        if let remote {
            applyPreferences(remote, sync: false)
            return
        }
        if preferences.hasAnyValue {
            pushPreferencesToServer(preferences)
        }
    }

    private func switchPreferencesScope(to scope: PreferencesScope) {
        guard scope != activePreferencesScope else { return }
        savePreferences(preferences)
        activePreferencesScope = scope
        loadPreferences()
    }

    private func preferencesKey(for scope: PreferencesScope) -> String {
        switch scope {
        case .guest:
            return guestPreferencesKey
        case .user(let userID):
            return userPreferencesKeyPrefix + userID
        }
    }

    private func migrateLegacyGuestPreferencesIfNeeded() {
        guard UserDefaults.standard.data(forKey: guestPreferencesKey) == nil else { return }
        guard let legacyData = UserDefaults.standard.data(forKey: legacyPreferencesKey) else { return }
        UserDefaults.standard.set(legacyData, forKey: guestPreferencesKey)
        UserDefaults.standard.removeObject(forKey: legacyPreferencesKey)
    }

    private func pushPreferencesToServer(_ preferences: UserPreferences) {
        guard let supabase else { return }
        guard !preferences.metadataPayload().isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let accessToken = await self.ensureValidSession() else { return }
            do {
                try await supabase.updateUserPreferences(preferences, accessToken: accessToken)
            } catch {
                // best-effort sync
            }
        }
    }

    func signInWithGoogle(presenting presenter: UIViewController) {
        guard !isLoading else { return }
        guard supabase != nil else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("signInWithGoogle aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return
        }
        guard configureGoogleSignIn(reportErrors: true) else { return }
        guard presenter.view.window != nil else {
            errorMessage = "Unable to present sign-in (no active window)."
            return
        }

        isLoading = true
        errorMessage = nil

        GIDSignIn.sharedInstance.signIn(
            withPresenting: presenter,
            hint: nil,
            additionalScopes: nil,
            nonce: nil
        ) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isLoading = false
                if let error = error {
                    let nsError = error as NSError
                    if self.isUserCancelledGoogleSignIn(nsError) {
                        return
                    }
                    self.errorMessage = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
                    return
                }
                guard let result else {
                    self.errorMessage = "Google sign-in returned no result."
                    return
                }
                guard let idToken = result.user.idToken?.tokenString else {
                    self.errorMessage = "Missing Google ID token."
                    return
                }
                let tokenNonce = self.normalizedNonce(from: idToken)
                await self.completeIDTokenSignIn(provider: "google", idToken: idToken, nonce: tokenNonce)
            }
        }
    }

    func restoreGoogleSignIn() {
        guard supabase != nil else { return }
        guard configureGoogleSignIn(reportErrors: false) else { return }
        GIDSignIn.sharedInstance.restorePreviousSignIn { [weak self] user, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error = error {
                    let nsError = error as NSError
                    if self.isIgnorableGoogleRestoreError(nsError) {
                        return
                    }
                    self.errorMessage = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
                    return
                }
                guard let idToken = user?.idToken?.tokenString else { return }
                let tokenNonce = self.normalizedNonce(from: idToken)
                await self.completeIDTokenSignIn(provider: "google", idToken: idToken, nonce: tokenNonce)
            }
        }
    }

    func signInWithApple() {
        guard supabase != nil else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("signInWithApple aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return
        }

        isLoading = true
        errorMessage = nil

        let nonce = randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func signOut() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let supabase, let accessToken = session?.accessToken else {
                clearSession()
                refreshGuestQuota()
                return
            }
            do {
                try await logout(accessToken: accessToken, supabase: supabase)
            } catch {
                // best-effort logout
            }
            GIDSignIn.sharedInstance.signOut()
            clearSession()
            refreshGuestQuota()
        }
    }

    func signInWithEmail(email: String, password: String) {
        guard !isLoading else { return }
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("signInWithEmail aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }

        isLoading = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                let newSession = try await supabase.signInWithEmail(email: trimmedEmail, password: password)
                self.session = newSession
                self.saveSession(newSession)
                self.guestQuota = nil
                await self.loadUserAndProfile()
            } catch {
                self.errorMessage = readableAuthError(error, provider: "email")
            }
        }
    }

    func signUpWithEmail(email: String, password: String) {
        guard !isLoading else { return }
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("signUpWithEmail aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Email and password are required."
            return
        }

        isLoading = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                if let newSession = try await supabase.signUpWithEmail(email: trimmedEmail, password: password) {
                    self.session = newSession
                    self.saveSession(newSession)
                    self.guestQuota = nil
                    self.shouldOfferTutorialAfterSignup = true
                    UserDefaults.standard.set(true, forKey: self.tutorialOfferKey)
                    await self.loadUserAndProfile()
                } else {
                    do {
                        try await supabase.resendSignupConfirmation(email: trimmedEmail)
                    } catch {
                        let resendMessage = self.readableAuthError(error, provider: "email")
                        let lowercased = resendMessage.lowercased()
                        if lowercased.contains("already exists")
                            || lowercased.contains("already registered")
                            || lowercased.contains("user exists") {
                            self.errorMessage = "This email has already been used. Please sign in instead."
                            return
                        }
                    }
                    self.shouldOfferTutorialAfterSignup = true
                    UserDefaults.standard.set(true, forKey: self.tutorialOfferKey)
                    self.errorMessage = "Check your email to confirm your account."
                }
            } catch {
                self.errorMessage = readableAuthError(error, provider: "email")
            }
        }
    }

    func sendPasswordReset(email: String) async -> Bool {
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("sendPasswordReset aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return false
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            errorMessage = "Enter your email to reset your password."
            return false
        }

        do {
            try await supabase.sendPasswordReset(
                email: trimmedEmail,
                redirectURL: passwordRecoveryRedirectURL()
            )
            return true
        } catch {
            errorMessage = readableAuthError(error, provider: "email")
            return false
        }
    }

    func handleIncomingURL(_ url: URL) -> Bool {
        guard let supabase else { return false }

        let items = incomingURLItems(url)
        let callbackType = items["type"]?.lowercased()
        let isRecovery = callbackType == "recovery" || url.path.lowercased().contains("reset-password")
        guard isRecovery else { return false }

        guard let recoverySession = supabase.parseOAuthCallback(url) else {
            errorMessage = "This password reset link is invalid or has expired."
            isShowingPasswordRecovery = false
            passwordRecoverySession = nil
            passwordRecoveryPreviousSession = nil
            return false
        }

        passwordRecoveryPreviousSession = session
        session = recoverySession
        saveSession(recoverySession)
        passwordRecoverySession = recoverySession
        errorMessage = nil
        isShowingPasswordRecovery = true
        return true
    }

    func dismissPasswordRecovery() {
        isShowingPasswordRecovery = false
        passwordRecoverySession = nil
        if let previousSession = passwordRecoveryPreviousSession {
            session = previousSession
            saveSession(previousSession)
        } else {
            clearSession()
            refreshGuestQuota()
        }
        passwordRecoveryPreviousSession = nil
    }

    func completePasswordRecovery(newPassword: String, confirmPassword: String) async -> Bool {
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("completePasswordRecovery aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return false
        }
        guard let recoverySession = passwordRecoverySession else {
            errorMessage = "Start password reset again. This recovery session is no longer active."
            return false
        }

        let trimmedPassword = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedConfirm = confirmPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPassword.isEmpty else {
            errorMessage = "Enter a new password."
            return false
        }
        guard trimmedPassword == trimmedConfirm else {
            errorMessage = "Passwords do not match."
            return false
        }
        guard trimmedPassword.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await supabase.updateAuthUser(
                email: nil,
                password: trimmedPassword,
                accessToken: recoverySession.accessToken
            )
            session = recoverySession
            saveSession(recoverySession)
            guestQuota = nil
            passwordRecoverySession = nil
            passwordRecoveryPreviousSession = nil
            isShowingPasswordRecovery = false
            await loadUserAndProfile()
            return true
        } catch {
            errorMessage = readableAuthError(error, provider: "email")
            return false
        }
    }

    func deleteAccount(confirmPassword: String? = nil) {
        guard !isLoading else { return }
        guard let supabase, let accessToken = session?.accessToken else {
            errorMessage = "Sign in required to delete your account."
            return
        }
        let trimmedPassword = confirmPassword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if canEditEmailPassword {
            guard !trimmedPassword.isEmpty else {
                errorMessage = "Enter your password to continue."
                return
            }
        }

        isLoading = true
        errorMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isLoading = false }
            do {
                var tokenForDelete = accessToken
                if self.canEditEmailPassword {
                    guard let email = self.user?.email, !email.isEmpty else {
                        self.errorMessage = "Unable to verify account email."
                        return
                    }
                    let reauthSession = try await supabase.signInWithEmail(
                        email: email,
                        password: trimmedPassword
                    )
                    self.session = reauthSession
                    self.saveSession(reauthSession)
                    tokenForDelete = reauthSession.accessToken
                }

                try await supabase.deleteAccount(accessToken: tokenForDelete)
                GIDSignIn.sharedInstance.signOut()
                self.clearSession()
                self.refreshGuestQuota()
            } catch {
                self.errorMessage = readableAuthError(error, provider: "delete")
            }
        }
    }

    func consumeTutorialOffer() {
        shouldOfferTutorialAfterSignup = false
        UserDefaults.standard.set(false, forKey: tutorialOfferKey)
    }

    func refreshGuestQuota() {
        guard !isSignedIn else {
            guestQuota = nil
            return
        }
        Task { @MainActor [weak self] in
            guard let self, let supabase else { return }
            do {
                let quota = try await supabase.fetchGuestQuota()
                self.applyGuestQuotaUpdate(quota)
            } catch {
                self.guestQuota = nil
            }
        }
    }

    func fetchGuestQuota() async -> GuestQuota? {
        guard !isSignedIn else {
            guestQuota = nil
            return nil
        }
        guard let supabase else { return nil }
        do {
            let quota = try await supabase.fetchGuestQuota()
            applyGuestQuotaUpdate(quota)
            return guestQuota
        } catch {
            return nil
        }
    }

    func refreshAppSettings() {
        guard let supabase else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let settings = try await supabase.fetchAppSettings(accessToken: session?.accessToken)
                self.photoStorageEnabled = settings?.photoStorageEnabled ?? false
                if let guestLimit = settings?.guestQuotaLimit, guestLimit > 0 {
                    self.guestQuotaLimit = guestLimit
                } else {
                    self.guestQuotaLimit = 5
                }
                if let signedInLimit = settings?.signedInFreeQuotaLimit, signedInLimit > 0 {
                    self.signedInFreeQuotaLimit = signedInLimit
                } else {
                    self.signedInFreeQuotaLimit = 25
                }
                if let priceCents = settings?.proMonthlyPriceCents, priceCents > 0 {
                    self.proMonthlyPriceCents = priceCents
                } else {
                    self.proMonthlyPriceCents = 199
                }
                self.proBillingURL = settings?.proBillingURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.proPortalURL = settings?.proPortalURL?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let quota = self.guestQuota {
                    self.guestQuota = self.normalizedGuestQuota(quota)
                }
            } catch {
                self.photoStorageEnabled = false
                self.guestQuotaLimit = 5
                self.signedInFreeQuotaLimit = 25
                self.proMonthlyPriceCents = 199
                self.proBillingURL = nil
                self.proPortalURL = nil
            }
        }
    }

    func updateProfile(
        displayName: String,
        email: String?,
        newPassword: String?,
        currentPassword: String?
    ) async -> Bool {
        guard let supabase else {
            let diag = SupabaseConfig.diagnostics()
            AuthLog.error("updateProfile aborted: Missing Supabase config. \(diag.summary)")
            errorMessage = "Supabase config missing: \(diag.short)."
            return false
        }
        guard let user else {
            errorMessage = "Sign in required to edit your profile."
            return false
        }

        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Display name is required."
            return false
        }

        let trimmedEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailChangeRequested = (trimmedEmail != nil && trimmedEmail != user.email)
        if emailChangeRequested, let trimmedEmail, trimmedEmail.isEmpty {
            errorMessage = "Email is required."
            return false
        }
        let passwordChangeRequested = (newPassword != nil && !(newPassword ?? "").isEmpty)
        if emailChangeRequested && !canEditEmailPassword {
            errorMessage = "Email changes are only available for email sign-in accounts."
            return false
        }
        if passwordChangeRequested && !canUpdatePassword {
            errorMessage = "Password changes are not available for this account."
            return false
        }
        let needsReauth = emailChangeRequested || (passwordChangeRequested && canEditEmailPassword)

        if needsReauth {
            guard let currentEmail = user.email, !currentEmail.isEmpty else {
                errorMessage = "Email unavailable for this account."
                return false
            }
            guard let currentPassword, !currentPassword.isEmpty else {
                errorMessage = "Enter your current password to continue."
                return false
            }

            do {
                let reauthSession = try await supabase.signInWithEmail(
                    email: currentEmail,
                    password: currentPassword
                )
                self.session = reauthSession
                self.saveSession(reauthSession)
            } catch {
                errorMessage = readableAuthError(error, provider: "email")
                return false
            }
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let accessToken = await ensureValidSession() else {
            errorMessage = "Session expired. Please sign in again."
            return false
        }

        do {
            if emailChangeRequested || passwordChangeRequested {
                try await supabase.updateAuthUser(
                    email: emailChangeRequested ? trimmedEmail : nil,
                    password: passwordChangeRequested ? newPassword : nil,
                    accessToken: accessToken
                )
            }

            try await supabase.updateProfile(
                id: user.id,
                displayName: trimmed,
                email: emailChangeRequested ? (trimmedEmail ?? "") : (user.email ?? ""),
                accessToken: accessToken
            )
            try await supabase.updateUserDisplayName(trimmed, accessToken: accessToken)
            self.user = SupabaseUser(
                id: user.id,
                email: emailChangeRequested ? trimmedEmail : user.email,
                displayName: trimmed,
                preferences: user.preferences,
                authProviders: user.authProviders,
                avatarURL: user.avatarURL,
                isProSubscriber: user.isProSubscriber,
                analysisQuotaRemaining: user.analysisQuotaRemaining,
                analysisQuotaMonth: user.analysisQuotaMonth,
                signedInMonthlyQuotaLimit: user.signedInMonthlyQuotaLimit
            )
            return true
        } catch {
            errorMessage = readableProfileError(error)
            return false
        }
    }

    func updateLeaderboardVisibility(_ visible: Bool) async {
        guard let supabase else { return }
        guard let user else { return }
        guard let accessToken = await ensureValidSession() else { return }
        do {
            try await supabase.updateLeaderboardVisibility(id: user.id, visible: visible, accessToken: accessToken)
        } catch {
            AuthLog.warn("updateLeaderboardVisibility failed (best-effort): \(error.localizedDescription)")
        }
    }

    func updateProfilePhoto(photoData: Data) async -> Bool {
        guard let supabase else { return false }
        guard let accessToken = await ensureValidSession() else {
            errorMessage = "Session expired. Please sign in again."
            return false
        }
        guard let user else { return false }

        let timestamp = Int(Date().timeIntervalSince1970)
        let path = "avatars/\(user.id)/\(timestamp).jpg"

        do {
            let publicURL = try await supabase.uploadProfilePhoto(
                data: photoData,
                path: path,
                accessToken: accessToken
            )
            try await supabase.updateUserAvatarURL(publicURL, accessToken: accessToken)
            self.user = SupabaseUser(
                id: user.id,
                email: user.email,
                displayName: user.displayName,
                preferences: user.preferences,
                authProviders: user.authProviders,
                avatarURL: publicURL,
                isProSubscriber: user.isProSubscriber,
                analysisQuotaRemaining: user.analysisQuotaRemaining,
                analysisQuotaMonth: user.analysisQuotaMonth,
                signedInMonthlyQuotaLimit: user.signedInMonthlyQuotaLimit
            )
            return true
        } catch {
            errorMessage = "Profile photo upload failed."
            return false
        }
    }

    func updatePhotoStorageEnabled(_ enabled: Bool) {
        guard let supabase else { return }
        guard let accessToken = session?.accessToken else { return }
        guard isAdmin else { return }
        let previous = photoStorageEnabled
        photoStorageEnabled = enabled
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await supabase.upsertAppSettings(photoStorageEnabled: enabled, accessToken: accessToken)
                self.photoStorageEnabled = enabled
            } catch {
                self.photoStorageEnabled = previous
                self.errorMessage = "Failed to update settings."
            }
        }
    }

    func submitImpact(entry: HistoryEntry, history: HistoryStore) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let supabase else { return }
            guard let accessToken = await ensureValidSession() else { return }
            guard let user = user else { return }

            let imagePath = await self.uploadImpactImageIfNeeded(
                entry: entry,
                accessToken: accessToken,
                userId: user.id,
                history: history
            )
            let points = carbonLeaderboardPoints(for: entry)
            let payload = ImpactPayload(
                user_id: user.id,
                item_key: ImpactKey.itemKey(item: entry.item, material: entry.material, bin: entry.bin),
                day_key: ImpactKey.dayKey(for: entry.date),
                item: entry.item,
                material: entry.material,
                recyclable: entry.recyclable,
                bin: entry.bin,
                notes: entry.notes,
                scanned_at: isoTimestamp(entry.date),
                points: points,
                scan_count: entry.scanCount,
                image_path: imagePath,
                source: entry.source.rawValue
            )

            let synced = await self.insertImpactWithRetry(payload: payload, accessToken: accessToken, supabase: supabase)
            if !synced {
                self.errorMessage = "Sync failed. Try again."
            }
        }
    }

    func syncImpact(entries: [HistoryEntry], history: HistoryStore) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let supabase else { return }
            guard let accessToken = await ensureValidSession() else { return }
            guard let user = user else { return }

            var hadFailure = false
            for entry in bestEntriesForSync(entries) {
                let imagePath = await self.uploadImpactImageIfNeeded(
                    entry: entry,
                    accessToken: accessToken,
                    userId: user.id,
                    history: history
                )
                let points = carbonLeaderboardPoints(for: entry)
                let payload = ImpactPayload(
                    user_id: user.id,
                    item_key: ImpactKey.itemKey(item: entry.item, material: entry.material, bin: entry.bin),
                    day_key: ImpactKey.dayKey(for: entry.date),
                    item: entry.item,
                    material: entry.material,
                    recyclable: entry.recyclable,
                    bin: entry.bin,
                    notes: entry.notes,
                    scanned_at: isoTimestamp(entry.date),
                    points: points,
                    scan_count: entry.scanCount,
                    image_path: imagePath,
                    source: entry.source.rawValue
                )
                let synced = await self.insertImpactWithRetry(payload: payload, accessToken: accessToken, supabase: supabase)
                if !synced {
                    hadFailure = true
                }
            }
            if hadFailure {
                self.errorMessage = "Some impact entries failed to sync. Try again."
            }
            await self.loadUserAndProfile()
        }
    }

    func deleteImpact(entry: HistoryEntry) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let supabase else { return }
            guard let accessToken = await ensureValidSession() else { return }
            guard let user = user else { return }

            do {
                try await supabase.deleteImpactEntry(
                    userId: user.id,
                    itemKey: ImpactKey.itemKey(item: entry.item, material: entry.material, bin: entry.bin),
                    dayKey: ImpactKey.dayKey(for: entry.date),
                    accessToken: accessToken
                )
            } catch {
                self.errorMessage = "Failed to delete impact. Try again."
            }
        }
    }

    func deleteImpactEntries(_ entries: [HistoryEntry]) {
        let dedupedEntries = bestEntriesForSync(entries)
        guard !dedupedEntries.isEmpty else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let supabase else { return }
            guard let accessToken = await ensureValidSession() else { return }
            guard let user = user else { return }

            var hadFailure = false
            for entry in dedupedEntries {
                do {
                    try await supabase.deleteImpactEntry(
                        userId: user.id,
                        itemKey: ImpactKey.itemKey(item: entry.item, material: entry.material, bin: entry.bin),
                        dayKey: ImpactKey.dayKey(for: entry.date),
                        accessToken: accessToken
                    )
                } catch {
                    hadFailure = true
                }
            }

            if hadFailure {
                self.errorMessage = "Some impacts failed to delete. Try again."
            }
        }
    }

    private func bestEntriesForSync(_ entries: [HistoryEntry]) -> [HistoryEntry] {
        var bestByKey: [String: HistoryEntry] = [:]
        for candidate in entries {
            let key = "\(ImpactKey.dayKey(for: candidate.date))|\(ImpactKey.itemKey(item: candidate.item, material: candidate.material, bin: candidate.bin))"
            if let existing = bestByKey[key] {
                bestByKey[key] = preferredSyncEntry(existing, candidate)
            } else {
                bestByKey[key] = candidate
            }
        }
        return bestByKey.values.sorted { $0.date > $1.date }
    }

    private func carbonLeaderboardPoints(for entry: HistoryEntry) -> Int {
        guard entry.recyclable, entry.recycleStatus == .recycled else { return 0 }
        let grams = Int((max(0, entry.carbonSavedKg) * 1000).rounded())
        return max(1, grams)
    }

    private func preferredSyncEntry(_ lhs: HistoryEntry, _ rhs: HistoryEntry) -> HistoryEntry {
        let lhsStatusRank = lhs.recycleStatus == .recycled ? 1 : 0
        let rhsStatusRank = rhs.recycleStatus == .recycled ? 1 : 0
        if lhsStatusRank != rhsStatusRank {
            return lhsStatusRank > rhsStatusRank ? lhs : rhs
        }
        let lhsSourceRank = lhs.source == .photo ? 1 : 0
        let rhsSourceRank = rhs.source == .photo ? 1 : 0
        if lhsSourceRank != rhsSourceRank {
            return lhsSourceRank > rhsSourceRank ? lhs : rhs
        }
        if lhs.scanCount != rhs.scanCount {
            return lhs.scanCount > rhs.scanCount ? lhs : rhs
        }
        if lhs.date != rhs.date {
            return lhs.date > rhs.date ? lhs : rhs
        }
        let lhsHasImage = lhs.localImagePath != nil || lhs.remoteImagePath != nil
        let rhsHasImage = rhs.localImagePath != nil || rhs.remoteImagePath != nil
        if lhsHasImage != rhsHasImage {
            return lhsHasImage ? lhs : rhs
        }
        return lhs
    }

    func refreshImpactFromServer(history: HistoryStore, limit: Int = 500) async {
        guard let supabase else { return }
        guard let accessToken = await ensureValidSession() else { return }
        do {
            let rows = try await supabase.fetchImpactEntries(accessToken: accessToken, limit: limit)
            history.mergeRemoteImpact(rows)
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load impact from server."
            }
        }
    }

    func accessTokenForAPI() async -> String? {
        await ensureValidSession()
    }

    func refreshSignedInUserState() async {
        await loadUserAndProfile()
    }

    @discardableResult
    func refreshStoreKitSubscriptionState() async -> Bool? {
        await reconcileStoreKitSubscriptionState()
    }

    private func restoreSession() {
        guard let data = KeychainStore.read(service: sessionKey, account: "default"),
              let stored = try? JSONDecoder().decode(SupabaseSession.self, from: data)
        else { return }
        session = stored
        didResolveSubscriptionState = false
        needsProfileRefresh = true
        if supabase != nil {
            needsProfileRefresh = false
            Task { @MainActor [weak self] in
                await self?.loadUserAndProfile()
            }
        }
    }

    private func saveSession(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        _ = KeychainStore.save(data, service: sessionKey, account: "default")
    }

    private func clearSession() {
        session = nil
        user = nil
        switchPreferencesScope(to: .guest)
        lastKnownSignedInUserID = nil
        UserDefaults.standard.removeObject(forKey: lastSignedInUserIDKey)
        lastMirroredSubscriptionState = nil
        errorMessage = nil
        isAdmin = false
        guestQuota = nil
        clearSignedInQuotaState()
        _ = KeychainStore.delete(service: sessionKey, account: "default")
    }

    private func ensureValidSession() async -> String? {
        guard let supabase, let session else { return nil }
        let refreshBuffer: TimeInterval = 60
        if session.expiresAt.timeIntervalSinceNow > refreshBuffer {
            return session.accessToken
        }
        do {
            let refreshed = try await supabase.refreshSession(refreshToken: session.refreshToken)
            await MainActor.run {
                self.session = refreshed
                self.saveSession(refreshed)
            }
            return refreshed.accessToken
        } catch {
            await MainActor.run { self.clearSession() }
            return nil
        }
    }

    private func loadUserAndProfile() async {
        if isSignedIn {
            didResolveSubscriptionState = false
        }
        guard let supabase, let accessToken = await ensureValidSession() else {
            if isSignedIn {
                didResolveSubscriptionState = true
            }
            return
        }
        let profile: SupabaseUser
        do {
            profile = try await supabase.fetchUser(accessToken: accessToken)
            let previousAppearanceMode = self.preferences.appearanceMode
            await MainActor.run {
                self.user = profile
                self.switchPreferencesScope(to: .user(profile.id))
                // Preserve the current runtime appearance unless cloud preferences explicitly define it.
                // This prevents sign-in/signup from forcing a stale locally cached mode.
                if profile.preferences?.appearanceMode == nil,
                   self.preferences.appearanceMode != previousAppearanceMode {
                    var preserved = self.preferences
                    preserved.appearanceMode = previousAppearanceMode
                    self.applyPreferences(preserved, sync: false)
                }
                self.lastKnownSignedInUserID = profile.id
                UserDefaults.standard.set(profile.id, forKey: self.lastSignedInUserIDKey)
            }
            syncPreferencesIfNeeded(remote: profile.preferences)
        } catch {
            await MainActor.run {
                self.errorMessage = readableProfileError(error)
                self.didResolveSubscriptionState = true
            }
            return
        }

        do {
            try await supabase.upsertProfile(user: profile, accessToken: accessToken)
        } catch {
            await MainActor.run { self.errorMessage = readableProfileError(error) }
        }

        do {
            let adminProfile = try await supabase.fetchProfile(id: profile.id, accessToken: accessToken)
            await MainActor.run { self.isAdmin = adminProfile?.isAdmin ?? false }
        } catch {
            await MainActor.run { self.isAdmin = false }
        }

        let localStoreKitIsActive = await currentStoreKitEntitlementState()

        var didResolve = false
        await MainActor.run {
            if localStoreKitIsActive == true {
                self.applyVerifiedSubscriptionState(true)
                didResolve = true
            } else {
                self.applyCloudSubscriptionState(from: profile, authoritativeIsPro: nil)
                let hasDefinitiveSubscriptionState =
                    profile.isProSubscriber != nil ||
                    profile.analysisQuotaRemaining != nil ||
                    profile.signedInMonthlyQuotaLimit != nil
                self.didResolveSubscriptionState = hasDefinitiveSubscriptionState
                didResolve = hasDefinitiveSubscriptionState
            }
        }

        let resolvedStoreKitState: Bool?
        if let localStoreKitIsActive {
            resolvedStoreKitState = localStoreKitIsActive
        } else {
            resolvedStoreKitState = await reconcileStoreKitSubscriptionState(accessToken: accessToken)
        }

        if let storeKitIsActive = resolvedStoreKitState {
            await MainActor.run {
                self.didResolveSubscriptionState = true
                didResolve = true
                self.applyVerifiedSubscriptionState(storeKitIsActive)
            }
        }

        if let authoritativeIsPro = try? await supabase.fetchSubscriptionState(userId: profile.id, accessToken: accessToken) {
            await MainActor.run {
                if localStoreKitIsActive == true {
                    self.applyVerifiedSubscriptionState(true)
                } else {
                    self.applyCloudSubscriptionState(from: profile, authoritativeIsPro: authoritativeIsPro)
                }
                self.didResolveSubscriptionState = true
                didResolve = true
            }
            let refreshedStoreKitState: Bool?
            if let localStoreKitIsActive {
                refreshedStoreKitState = localStoreKitIsActive
            } else {
                refreshedStoreKitState = await currentStoreKitEntitlementState()
            }

            if let storeKitIsActive = refreshedStoreKitState {
                await MainActor.run {
                    self.applyVerifiedSubscriptionState(storeKitIsActive)
                }
            }
        }

        if !hasActiveSubscription {
            let monthKey = currentUTCMonthKey()
            if let used = try? await supabase.fetchSignedInMonthlyUsageCount(
                userId: profile.id,
                monthKey: monthKey,
                accessToken: accessToken
            ) {
                await MainActor.run {
                    let limit = max(1, self.signedInFreeQuotaLimit)
                    self.signedInQuotaRemaining = max(0, limit - used)
                    self.didResolveSubscriptionState = true
                    didResolve = true
                }
            }
        }

        if !didResolve {
            await MainActor.run {
                self.didResolveSubscriptionState = true
            }
        }

        refreshAppSettings()
    }

    private func currentUTCMonthKey(_ date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let utc = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents(in: utc, from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        return String(format: "%04d-%02d", year, month)
    }

    private func logout(accessToken: String, supabase: SupabaseService) async throws {
        let endpoint = supabase.baseURL.appendingPathComponent("auth/v1/logout")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabase.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    private func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func uploadImpactImageIfNeeded(
        entry: HistoryEntry,
        accessToken: String,
        userId: String,
        history: HistoryStore
    ) async -> String? {
        // Photo uploads are disabled for now; keep images local only.
        return nil
    }

    private func insertImpactWithRetry(
        payload: ImpactPayload,
        accessToken: String,
        supabase: SupabaseService,
        maxAttempts: Int = 3
    ) async -> Bool {
        var lastError: Error?
        var token = accessToken

        for attempt in 1...maxAttempts {
            do {
                _ = try await supabase.insertImpact(payload: payload, accessToken: token)
                if attempt > 1 {
                    AuthLog.info("Impact sync recovered after retry attempt \(attempt).")
                }
                return true
            } catch {
                lastError = error
                AuthLog.warn("Impact sync attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < maxAttempts {
                    if let refreshed = await ensureValidSession() {
                        token = refreshed
                    }
                    let delayNanos = UInt64(250_000_000 * attempt)
                    try? await Task.sleep(nanoseconds: delayNanos)
                }
            }
        }

        if let lastError {
            AuthLog.error("Impact sync failed after retries: \(lastError.localizedDescription)")
        }
        return false
    }

    private func completeIDTokenSignIn(provider: String, idToken: String, nonce: String?) async {
        guard let supabase else { return }
        do {
            let newSession = try await supabase.signInWithIDToken(provider: provider, idToken: idToken, nonce: nonce)
            self.session = newSession
            self.saveSession(newSession)
            self.guestQuota = nil
            await self.loadUserAndProfile()
        } catch {
            self.errorMessage = readableAuthError(error, provider: provider)
        }
    }

    private func passwordRecoveryRedirectURL() -> URL? {
        guard let scheme = registeredAppScheme() else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "auth"
        components.path = "/reset-password"
        return components.url
    }

    private func registeredAppScheme() -> String? {
        guard let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] else {
            return nil
        }
        for urlType in urlTypes {
            guard let schemes = urlType["CFBundleURLSchemes"] as? [String] else { continue }
            if let appScheme = schemes.first(where: { !$0.hasPrefix("com.googleusercontent.apps.") }) {
                return appScheme
            }
        }
        return nil
    }

    private func incomingURLItems(_ url: URL) -> [String: String] {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = components?.query ?? ""
        let fragment = components?.fragment ?? ""
        return parseURLItems(query + "&" + fragment)
    }

    private func parseURLItems(_ input: String) -> [String: String] {
        input
            .split(separator: "&")
            .reduce(into: [String: String]()) { result, rawPair in
                let parts = rawPair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let rawKey = parts.first else { return }
                let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
                let value = parts.count > 1
                    ? (String(parts[1]).removingPercentEncoding ?? String(parts[1]))
                    : ""
                result[key] = value
            }
    }

    private func readableAuthError(_ error: Error, provider: String) -> String {
        if let serviceError = error as? SupabaseService.ServiceError {
            switch serviceError {
            case .httpError(let code, let body):
                let message = parseSupabaseErrorMessage(body)
                if provider == "email" {
                    let lowercased = message.lowercased()
                    if lowercased.contains("already registered")
                        || lowercased.contains("already exists")
                        || lowercased.contains("user exists")
                        || lowercased.contains("has already been registered") {
                        return "This email has already been used. Please sign in instead."
                    }
                }
                if provider == "google", message.lowercased().contains("nonce") {
                    return "Supabase HTTP \(code): Nonce mismatch. Enable Skip nonce check for iOS in Supabase Auth > Providers > Google."
                }
                return "Supabase HTTP \(code): \(message)"
            case .emailAlreadyRegistered:
                return "This email has already been used. Please sign in instead."
            case .invalidResponse:
                return "Supabase returned an invalid response."
            case .invalidCallback:
                return "Supabase callback was invalid."
            case .missingConfig:
                let diag = SupabaseConfig.diagnostics()
                return "Supabase config missing: \(diag.short)."
            }
        }
        let nsError = error as NSError
        return nsError.localizedDescription
    }

    private func parseSupabaseErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return body.isEmpty ? "Unknown error." : body
        }
        let message =
            (json["msg"] as? String) ??
            (json["message"] as? String) ??
            (json["error_description"] as? String) ??
            (json["error"] as? String)
        return message ?? (body.isEmpty ? "Unknown error." : body)
    }

    private func readableProfileError(_ error: Error) -> String {
        if let serviceError = error as? SupabaseService.ServiceError {
            switch serviceError {
            case .httpError(let code, let body):
                let message = parseSupabaseErrorMessage(body)
                return "Profile sync failed (HTTP \(code)): \(message)"
            case .invalidResponse:
                return "Profile sync failed: invalid response."
            case .invalidCallback:
                return "Profile sync failed: invalid request."
            case .missingConfig:
                let diag = SupabaseConfig.diagnostics()
                return "Profile sync failed: Supabase config missing (\(diag.short))."
            case .emailAlreadyRegistered:
                return "Profile sync failed: email already registered."
            }
        }
        let nsError = error as NSError
        return "Profile sync failed: \(nsError.localizedDescription)"
    }

    private func startTransactionUpdatesListener() {
        transactionUpdatesTask?.cancel()
        transactionUpdatesTask = Task.detached(priority: .background) { [weak self] in
            for await update in StoreKit.Transaction.updates {
                guard let self else { return }
                await self.handleTransactionUpdate(update)
            }
        }
    }

    private func handleTransactionUpdate(_ update: VerificationResult<StoreKit.Transaction>) async {
        guard let productID = BootstrapConfig.appStoreSubscriptionProductID else { return }
        switch update {
        case .verified(let transaction):
            guard transaction.productID == productID else { return }
            await transaction.finish()
            _ = await reconcileStoreKitSubscriptionState()
        case .unverified(let transaction, let error):
            guard transaction.productID == productID else { return }
            AuthLog.warn("Ignoring unverified App Store transaction for \(productID): \(error.localizedDescription)")
        }
    }

    private func currentStoreKitEntitlementState() async -> Bool? {
        guard let productID = BootstrapConfig.appStoreSubscriptionProductID else { return nil }
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            switch entitlement {
            case .verified(let transaction):
                guard transaction.productID == productID else { continue }
                if isTransactionEntitled(transaction) {
                    return true
                }
            case .unverified(let transaction, let error):
                guard transaction.productID == productID else { continue }
                AuthLog.warn("Ignoring unverified entitlement for \(productID): \(error.localizedDescription)")
            }
        }
        return false
    }

    @discardableResult
    private func reconcileStoreKitSubscriptionState(
        accessToken: String? = nil,
        syncToSupabase: Bool = true
    ) async -> Bool? {
        guard let isActive = await currentStoreKitEntitlementState() else { return nil }
        applyVerifiedSubscriptionState(isActive)
        guard syncToSupabase else { return isActive }
        await mirrorVerifiedEntitlementToSupabase(isActive: isActive, accessToken: accessToken)
        return isActive
    }

    private func applyVerifiedSubscriptionState(_ isActive: Bool) {
        hasActiveSubscription = isActive
        didResolveSubscriptionState = true
        if isActive {
            signedInQuotaRemaining = nil
        }
        guard isSignedIn, let user else { return }
        self.user = SupabaseUser(
            id: user.id,
            email: user.email,
            displayName: user.displayName,
            preferences: user.preferences,
            authProviders: user.authProviders,
            avatarURL: user.avatarURL,
            isProSubscriber: isActive,
            analysisQuotaRemaining: user.analysisQuotaRemaining,
            analysisQuotaMonth: user.analysisQuotaMonth,
            signedInMonthlyQuotaLimit: user.signedInMonthlyQuotaLimit
        )
    }

    private func mirrorVerifiedEntitlementToSupabase(isActive: Bool, accessToken: String?) async {
        guard let supabase, let userID = user?.id else { return }
        if let lastMirroredSubscriptionState,
           lastMirroredSubscriptionState.userID == userID,
           lastMirroredSubscriptionState.isActive == isActive {
            return
        }
        let resolvedToken: String?
        if let at = accessToken {
            resolvedToken = at
        } else {
            resolvedToken = await ensureValidSession()
        }
        guard let token = resolvedToken else { return }
        do {
            try await supabase.updateUserSubscriptionStatus(isActive: isActive, accessToken: token)
            lastMirroredSubscriptionState = (userID, isActive)
            applyVerifiedSubscriptionState(isActive)
        } catch {
            AuthLog.warn("Failed to mirror App Store entitlement to Supabase: \(error.localizedDescription)")
        }
    }

    private func verifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(_, let error):
            throw StoreSubscriptionError.unverifiedTransaction(error.localizedDescription)
        }
    }

    private func fetchSubscriptionProduct(productID: String) async throws -> Product {
        do {
            let initialProducts = try await Product.products(for: [productID])
            if let product = initialProducts.first(where: { $0.id == productID }) {
                return try validatedSubscriptionProduct(product, expectedProductID: productID)
            }

            try? await Task.sleep(nanoseconds: 450_000_000)

            let retryProducts = try await Product.products(for: [productID])
            if let retryProduct = retryProducts.first(where: { $0.id == productID }) {
                return try validatedSubscriptionProduct(retryProduct, expectedProductID: productID)
            }

            AuthLog.warn("App Store product not found for id \(productID) after quiet retry.")
            throw StoreSubscriptionError.productLookupFailed(
                productID: productID,
                reason: "StoreKit returned zero matching products after two lookup attempts.",
                code: "IAP-PRODUCT-NOT-FOUND"
            )
        } catch {
            if let subscriptionError = error as? StoreSubscriptionError {
                throw subscriptionError
            }

            AuthLog.warn("App Store product fetch failed for \(productID): \(error.localizedDescription)")
            throw StoreSubscriptionError.productLookupFailed(
                productID: productID,
                reason: error.localizedDescription,
                code: "IAP-STOREKIT-REQUEST-FAILED"
            )
        }
    }

    private func isTransactionEntitled(_ transaction: StoreKit.Transaction) -> Bool {
        if transaction.revocationDate != nil {
            return false
        }
        if transaction.isUpgraded {
            return false
        }
        if let expirationDate = transaction.expirationDate {
            return expirationDate > Date()
        }
        return true
    }

    private enum StoreSubscriptionError: LocalizedError {
        case missingProductConfiguration
        case productLookupFailed(productID: String, reason: String, code: String)
        case invalidProductType(productID: String, actualType: String)
        case pending
        case userCancelled
        case inactiveEntitlement
        case noActiveSubscriptionToRestore
        case unverifiedTransaction(String)
        case unknown

        var errorDescription: String? {
            switch self {
            case .missingProductConfiguration:
                return "[IAP-CONFIG-MISSING] The app is missing `APP_STORE_SUBSCRIPTION_PRODUCT_ID` in its bundle configuration."
            case .productLookupFailed(let productID, let reason, let code):
                return "[\(code)] Unable to load App Store product `\(productID)`. \(reason) If this is a TestFlight build, verify the subscription is attached to this app, available for this bundle ID, and reachable in sandbox/TestFlight."
            case .invalidProductType(let productID, let actualType):
                return "[IAP-PRODUCT-TYPE-MISMATCH] App Store product `\(productID)` resolved as `\(actualType)` instead of an auto-renewable subscription."
            case .pending:
                return "Your App Store purchase is pending approval."
            case .userCancelled:
                return "The App Store purchase was canceled."
            case .inactiveEntitlement:
                return "The App Store purchase completed, but no active ReVive Pro entitlement was found."
            case .noActiveSubscriptionToRestore:
                return "No active ReVive Pro subscription was found to restore."
            case .unverifiedTransaction(let message):
                return "The App Store transaction could not be verified. \(message)"
            case .unknown:
                return "The App Store purchase could not be completed."
            }
        }
    }

    private func validatedSubscriptionProduct(_ product: Product, expectedProductID: String) throws -> Product {
        guard product.id == expectedProductID else {
            throw StoreSubscriptionError.productLookupFailed(
                productID: expectedProductID,
                reason: "StoreKit returned a different product identifier: \(product.id).",
                code: "IAP-PRODUCT-ID-MISMATCH"
            )
        }
        guard product.type == .autoRenewable else {
            throw StoreSubscriptionError.invalidProductType(
                productID: expectedProductID,
                actualType: String(describing: product.type)
            )
        }
        return product
    }

    private func configureGoogleSignIn(reportErrors: Bool) -> Bool {
        let clientID = Secrets.googleIOSClientID
        let serverClientID = Secrets.googleWebClientID
        if clientID.isEmpty {
            if reportErrors {
                errorMessage = "Missing Google client ID from Supabase config."
            }
            return false
        }
        let serverID = serverClientID.isEmpty ? nil : serverClientID
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverID)
        return true
    }

    private func isIgnorableGoogleRestoreError(_ error: NSError) -> Bool {
        error.domain == "com.google.GIDSignIn" && error.code == -4
    }

    private func isUserCancelledGoogleSignIn(_ error: NSError) -> Bool {
        error.domain == "com.google.GIDSignIn" && error.code == -5
    }

    private func isUserCancelledAppleSignIn(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == ASAuthorizationError.errorDomain &&
            nsError.code == ASAuthorizationError.Code.canceled.rawValue
    }

    deinit {
        transactionUpdatesTask?.cancel()
        for token in notificationObservers {
            NotificationCenter.default.removeObserver(token)
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce.")
            }
            randoms.forEach { value in
                if remaining == 0 { return }
                if Int(value) < charset.count {
                    result.append(charset[Int(value)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hashed = SHA256.hash(data: data)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func normalizedNonce(from idToken: String) -> String? {
        let nonce = nonceFromIDToken(idToken)
        guard let nonce, !nonce.isEmpty else { return nil }
        return nonce
    }

    private func nonceFromIDToken(_ idToken: String) -> String? {
        struct TokenPayload: Decodable {
            let nonce: String?
        }

        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        guard let data = decodeBase64URL(String(parts[1])) else { return nil }
        if let payload = try? JSONDecoder().decode(TokenPayload.self, from: data) {
            return payload.nonce
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json["nonce"] as? String
        }
        return nil
    }

    private func decodeBase64URL(_ value: String) -> Data? {
        var output = value.replacingOccurrences(of: "-", with: "+")
        output = output.replacingOccurrences(of: "_", with: "/")
        let padding = output.count % 4
        if padding != 0 {
            output += String(repeating: "=", count: 4 - padding)
        }
        return Data(base64Encoded: output, options: [.ignoreUnknownCharacters])
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            isLoading = false
            errorMessage = "Apple sign-in failed."
            return
        }
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            isLoading = false
            errorMessage = "Missing Apple identity token."
            return
        }
        let nonce = currentNonce
        currentNonce = nil
        Task { @MainActor [weak self] in
            await self?.completeIDTokenSignIn(provider: "apple", idToken: idToken, nonce: nonce)
            self?.isLoading = false
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        isLoading = false
        currentNonce = nil
        if isUserCancelledAppleSignIn(error) {
            return
        }
        errorMessage = error.localizedDescription
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let window = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) {
            return window
        }
        if let scene = scenes.first {
            return UIWindow(windowScene: scene)
        }
        // Unreachable in iOS 13+ (app always has at least one window scene)
        return UIWindow()
    }
}
