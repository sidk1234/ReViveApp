//
//  MainTabView.swift
//  Recyclability
//

import SwiftUI
import Combine

struct MainTabView: View {
    enum Tab: Int, CaseIterable {
        case bin
        case camera
        case home
        case leaderboard
        case account
    }

    @State private var selection: Tab = .home
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var leaderboard: LeaderboardStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var tabSelectionNamespace
    @State private var showGuestPopup = false
    @State private var guestDismissTask: Task<Void, Never>?
    @State private var hasShownLaunchGuestPopup = false
    @State private var showResumeOverlay = false
    @State private var wasBackgrounded = false
    @State private var showTutorialOverlay = false
    @State private var guestPopupDragOffsetY: CGFloat = 0
    @State private var tabButtonFrames: [Tab: CGRect] = [:]
    @State private var lastPrimarySelection: Tab = .home
    @State private var didRunInitialSignedInImpactSync = false
    @State private var tutorialShouldReturnHomeOnDismiss = false
    @State private var isCapturedPhotoActive = false
    @AppStorage("revive.tutorial.mainTabs.didShowMandatory") private var didShowMandatoryMainTabsTutorial = false
    @AppStorage("revive.tutorial.mainTabs.overlayVisible") private var isMainTutorialOverlayActive = false
    @State private var isKeyboardVisible = false
    @State private var isCaptureTextEntryActive = false
    @State private var isCaptureTextResultActive = false

    var body: some View {
        baseView
    }

    private var baseView: some View {
        MainTabEventHandlers(
            showGuestPopup: $showGuestPopup,
            showResumeOverlay: $showResumeOverlay,
            showTutorialOverlay: $showTutorialOverlay,
            selection: $selection,
            auth: auth,
            history: history,
            leaderboard: leaderboard,
            scenePhase: scenePhase,
            onPerformInitialGuestQuotaFetch: performInitialGuestQuotaFetch,
            onGuestQuotaUpdated: handleGuestQuotaUpdated,
            onRequestSignIn: handleRequestSignInNotification,
            onOpenHome: handleOpenHomeNotification,
            onOpenCapture: handleOpenCaptureNotification,
            onOpenBin: handleOpenBinNotification,
            onRequestUpgrade: handleRequestUpgradeNotification,
            onOpenTutorial: handleOpenTutorialNotification,
            onTutorialVisibilityChange: handleTutorialVisibilityChange,
            onSelectionChange: handleSelectionChange,
            onAuthSignInChange: handleAuthSignInChange,
            onUserIDChange: handleUserIDChange,
            onAccessTokenChange: handleAccessTokenChange,
            onCapturePhotoVisibilityChange: handleCapturePhotoVisibilityChange,
            onAppear: handleOnAppear,
            onHistoryEntriesChange: handleHistoryEntriesChange,
            onScenePhaseChange: handleScenePhaseChange
        ) {
            mainContent
        }
    }

    private var mainContent: some View {
        ZStack(alignment: .top) {
            MainTabPages(
                selection: $selection,
                guestControlInset: guestControlInset,
                tabButtonFrames: $tabButtonFrames,
                shouldShowFloatingTabBar: shouldShowFloatingTabBar,
                onTextEntryActiveChange: { newValue in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        isCaptureTextEntryActive = newValue
                    }
                },
                onTextResultActiveChange: { newValue in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        isCaptureTextResultActive = newValue
                    }
                },
                floatingTabBar: { floatingTabBar }
            )

            if shouldRenderGuestPopup {
                GuestSignInPopup(
                    remaining: auth.guestQuota?.remaining,
                    limit: auth.guestQuota?.limit ?? auth.guestQuotaLimit,
                    onDragOffsetChanged: { offsetY in
                        guestPopupDragOffsetY = offsetY
                    },
                    onDismiss: dismissGuestPopup,
                    onSignIn: handleGuestSignInTap
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }

            if showResumeOverlay {
                AppResumeOverlay()
                    .transition(.opacity)
                    .zIndex(200)
            }

            if showTutorialOverlay {
                BeginnerTipsOverlay(
                    currentTab: $selection,
                    tabFrames: tabButtonFrames,
                    bottomClearance: 138,
                    onClose: dismissTutorialOverlay
                )
                .transition(.opacity)
                .zIndex(300)
            }
        }
        .coordinateSpace(name: "mainTabSpace")
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = false }
        }
    }

    private var shouldShowFloatingTabBar: Bool {
        !(selection == .camera && isCapturedPhotoActive) && !isKeyboardVisible && !isCaptureTextEntryActive && !isCaptureTextResultActive
    }

    private func performInitialGuestQuotaFetch() async {
        guard !auth.isSignedIn else { return }
        for _ in 0..<3 {
            if await auth.fetchGuestQuota() != nil {
                break
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
    }

    private func handleGuestQuotaUpdated(_ note: Notification) {
        guard !auth.isSignedIn else { return }
        guard let quota = note.object as? GuestQuota else { return }
        auth.applyGuestQuotaUpdate(quota)
    }

    private func handleRequestSignInNotification(_ note: Notification) {
        dismissGuestPopup()
        selection = .account
    }

    private func handleOpenHomeNotification(_ note: Notification) {
        selection = .home
        dismissGuestPopup()
    }

    private func handleOpenCaptureNotification(_ note: Notification) {
        selection = .camera
        dismissGuestPopup()
    }

    private func handleOpenBinNotification(_ note: Notification) {
        selection = .bin
        dismissGuestPopup()
    }

    private func handleRequestUpgradeNotification(_ note: Notification) {
        dismissGuestPopup()
        selection = .account
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .reviveOpenSubscription, object: nil)
        }
    }

    private func handleOpenTutorialNotification(_ note: Notification) {
        tutorialShouldReturnHomeOnDismiss = false
        isMainTutorialOverlayActive = true
        showTutorialOverlay = true
    }

    private func handleTutorialVisibilityChange(_ isVisible: Bool) {
        isMainTutorialOverlayActive = isVisible
        NotificationCenter.default.post(
            name: .reviveMainTutorialVisibilityChanged,
            object: isVisible
        )
    }

    private func handleSelectionChange(_ newValue: Tab) {
        if newValue != .camera {
            lastPrimarySelection = newValue
            isCapturedPhotoActive = false
        }
        handleGuestPopup(for: newValue)
    }

    private func handleCapturePhotoVisibilityChange(_ isVisible: Bool) {
        guard selection == .camera else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isCapturedPhotoActive = isVisible
        }
    }

    private func handleAuthSignInChange(_ isSignedIn: Bool) {
        leaderboard.setAccessToken(auth.session?.accessToken)
        if isSignedIn {
            dismissGuestPopup()
            applyHistoryStorageScope()
            performInitialSignedInImpactSyncIfNeeded()
            presentTutorialOfferIfNeeded()
            return
        }

        applyHistoryStorageScope()
        didRunInitialSignedInImpactSync = false
        hasShownLaunchGuestPopup = false
        Task { @MainActor in
            _ = await auth.fetchGuestQuota()
            presentLaunchGuestPopupIfNeeded()
        }
    }

    private func handleUserIDChange(_ userID: String) {
        guard !userID.isEmpty else { return }
        applyHistoryStorageScope()
        performInitialSignedInImpactSyncIfNeeded(force: true)
    }

    private func handleOnAppear() {
        if !auth.isSignedIn, selection == .home {
            resetGuestPopupStateImmediately()
        }
        isMainTutorialOverlayActive = showTutorialOverlay
        leaderboard.setAccessToken(auth.session?.accessToken)
        leaderboard.startPassiveRefresh()
        applyHistoryStorageScope()
        syncBinReminder(for: history.entries)
        presentLaunchGuestPopupIfNeeded()
        performInitialSignedInImpactSyncIfNeeded()
        presentTutorialOfferIfNeeded()
    }

    private func handleHistoryEntriesChange(_ entries: [HistoryEntry]) {
        syncBinReminder(for: entries)
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            wasBackgrounded = true
            leaderboard.stopPassiveRefresh()
        case .active:
            leaderboard.setAccessToken(auth.session?.accessToken)
            leaderboard.startPassiveRefresh()
            leaderboard.refreshNow()
            if wasBackgrounded {
                wasBackgrounded = false
                playReopenAnimation()
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func handleAccessTokenChange(_ token: String) {
        let resolvedToken = token.isEmpty ? nil : token
        leaderboard.setAccessToken(resolvedToken)
        leaderboard.refreshNow()
    }

    private func handleGuestSignInTap() {
        dismissGuestPopup()
        selection = .account
    }

    private func performInitialSignedInImpactSyncIfNeeded(force: Bool = false) {
        guard auth.isSignedIn else { return }
        if !force, didRunInitialSignedInImpactSync { return }
        didRunInitialSignedInImpactSync = true
        Task { @MainActor in
            await auth.refreshImpactFromServer(history: history)
            if auth.autoSyncImpactEnabled {
                auth.syncImpact(entries: history.entries, history: history)
            }
        }
    }

    private func applyHistoryStorageScope() {
        guard auth.isSignedIn else {
            history.setStorageScope(userID: nil)
            return
        }

        guard let scopedUserID = resolvedSignedInUserIDForHistoryScope() else {
            history.setStorageScope(userID: nil)
            return
        }

        if let loadedUserID = auth.user?.id,
           !loadedUserID.isEmpty,
           loadedUserID == scopedUserID {
            history.transferGuestEntriesToUserIfNeeded(userID: loadedUserID)
        }
        history.setStorageScope(userID: scopedUserID)
    }

    private func resolvedSignedInUserIDForHistoryScope() -> String? {
        if let liveUserID = auth.user?.id.trimmingCharacters(in: .whitespacesAndNewlines),
           !liveUserID.isEmpty {
            return liveUserID
        }

        if let cachedUserID = auth.lastKnownSignedInUserID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cachedUserID.isEmpty {
            return cachedUserID
        }

        return nil
    }

    private func presentTutorialOfferIfNeeded() {
        guard !showTutorialOverlay else { return }

        if !didShowMandatoryMainTabsTutorial {
            didShowMandatoryMainTabsTutorial = true
        }

        guard auth.isSignedIn else { return }
        guard auth.shouldOfferTutorialAfterSignup else { return }

        tutorialShouldReturnHomeOnDismiss = false
        auth.consumeTutorialOffer()
        dismissGuestPopup()
        isMainTutorialOverlayActive = true
        withAnimation(.easeInOut(duration: 0.2)) {
            showTutorialOverlay = true
        }
    }

    private func presentLaunchGuestPopupIfNeeded() {
        guard !auth.isSignedIn else {
            dismissGuestPopup()
            return
        }
        guard selection != .home else {
            dismissGuestPopup()
            return
        }
        guard !hasShownLaunchGuestPopup else { return }
        hasShownLaunchGuestPopup = true
        presentGuestPopup()
    }

    private func handleGuestPopup(for tab: Tab) {
        guard !showTutorialOverlay else {
            dismissGuestPopup()
            return
        }
        guard !auth.isSignedIn else {
            dismissGuestPopup()
            return
        }
        if tab == .camera {
            presentGuestPopup()
        } else {
            dismissGuestPopup()
        }
    }

    private func presentGuestPopup() {
        guard !showTutorialOverlay else { return }
        guestDismissTask?.cancel()
        guestPopupDragOffsetY = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            showGuestPopup = true
        }
        guestDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            guestPopupDragOffsetY = 0
            withAnimation(.easeInOut(duration: 0.2)) {
                showGuestPopup = false
            }
        }
    }

    private func dismissGuestPopup() {
        guestDismissTask?.cancel()
        guestDismissTask = nil
        guestPopupDragOffsetY = 0
        withAnimation(.easeInOut(duration: 0.2)) {
            showGuestPopup = false
        }
    }

    private func resetGuestPopupStateImmediately() {
        guestDismissTask?.cancel()
        guestDismissTask = nil
        guestPopupDragOffsetY = 0
        showGuestPopup = false
    }

    private func playReopenAnimation() {
        selection = .home
        showResumeOverlay = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 420_000_000)
            showResumeOverlay = false
        }
    }

    private func dismissTutorialOverlay() {
        auth.consumeTutorialOffer()
        dismissGuestPopup()
        let shouldReturnHome = tutorialShouldReturnHomeOnDismiss
        tutorialShouldReturnHomeOnDismiss = false
        isMainTutorialOverlayActive = false
        withAnimation(.easeInOut(duration: 0.2)) {
            showTutorialOverlay = false
        }
        if shouldReturnHome {
            selection = .home
        }
    }

    private func syncBinReminder(for entries: [HistoryEntry]) {
        let markedCount = markedForRecycleCount(in: entries)
        BinReminderNotificationManager.shared.syncPendingBinReminder(markedCount: markedCount)
    }

    private func markedForRecycleCount(in entries: [HistoryEntry]) -> Int {
        var count = 0
        for entry in entries where entry.recycleStatus == .markedForRecycle {
            count += 1
        }
        return count
    }

    private var shouldRenderGuestPopup: Bool {
        showGuestPopup
            && !showTutorialOverlay
            && !auth.isSignedIn
    }

    private var guestControlInset: CGFloat {
        guard shouldRenderGuestPopup else { return 0 }
        let baseInset: CGFloat = 102
        let dragLift = min(0, guestPopupDragOffsetY)
        return max(0, baseInset + dragLift)
    }

    private var dockTabs: [DockTabItem] {
        [
            DockTabItem(tab: .home, title: "Home", icon: "house.fill"),
            DockTabItem(tab: .bin, title: "Bin", icon: "trash.fill"),
            DockTabItem(tab: .leaderboard, title: "Ranks", icon: "trophy.fill"),
            DockTabItem(tab: .account, title: "Account", icon: "person.crop.circle.fill")
        ]
    }

    private var floatingTabBarShellShape: FloatingTabBarShellShape {
        FloatingTabBarShellShape(
            collapseProgress: 0,
            minimumTopWidth: 188,
            cornerRadius: 34
        )
    }

    private var floatingTabBarRowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
    }

    private var floatingTabBarItemShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var floatingTabBarShellTint: Color {
        colorScheme == .light ? AppTheme.night.opacity(0.10) : AppTheme.night.opacity(0.24)
    }

    private var floatingTabBarRowTint: Color {
        colorScheme == .light ? AppTheme.night.opacity(0.08) : AppTheme.night.opacity(0.20)
    }

    private func floatingTabBarItemTint(isSelected: Bool) -> Color {
        if colorScheme == .light {
            return isSelected ? Color.white.opacity(0.26) : AppTheme.night.opacity(0.06)
        }
        return isSelected ? Color.white.opacity(0.10) : AppTheme.night.opacity(0.18)
    }

    private var activeTabSelectionBubble: some View {
        floatingTabBarItemShape
            .fill(Color.white.opacity(colorScheme == .light ? 0.26 : 0.15))
            .overlay(
                floatingTabBarItemShape
                    .fill(Color.black.opacity(colorScheme == .light ? 0.06 : 0.12))
            )
            .overlay(
                floatingTabBarItemShape
                    .stroke(Color.white.opacity(colorScheme == .light ? 0.58 : 0.28), lineWidth: 1)
            )
            .liquidGlassBackground(
                in: floatingTabBarItemShape,
                interactive: true,
                tint: floatingTabBarItemTint(isSelected: true)
            )
            .shadow(color: Color.black.opacity(colorScheme == .light ? 0.12 : 0.30), radius: 10, x: 0, y: 6)
    }

    private var inactiveCaptureBubble: some View {
        floatingTabBarItemShape
            .fill(Color.white.opacity(0.12))
            .overlay(
                floatingTabBarItemShape
                    .fill(Color.black.opacity(0.10))
            )
            .overlay(
                floatingTabBarItemShape
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .liquidGlassBackground(
                in: floatingTabBarItemShape,
                interactive: true,
                tint: floatingTabBarItemTint(isSelected: false)
            )
    }

    private var floatingTabBar: some View {
        VStack(spacing: 6) {
            if selection == .camera && auth.showCaptureInstructions && !isCapturedPhotoActive {
                Text("Press capture to scan or hold to type an item")
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            VStack(spacing: 8) {
                // Full camera controls — only visible on camera tab
                if selection == .camera {
                    captureActionRow
                        .transition(.opacity)
                }

                // Nav row — compact 5-button row on non-camera, 4-button row on camera
                HStack(spacing: 8) {
                    primaryTabButton(dockTabs[0]) // Home
                    primaryTabButton(dockTabs[1]) // Bin
                    if selection != .camera {
                        compactCaptureNavButton
                            .transition(.opacity)
                    }
                    primaryTabButton(dockTabs[2]) // Ranks
                    primaryTabButton(dockTabs[3]) // Account
                }
                .padding(.horizontal, 8)
            }
            .animation(.easeInOut(duration: 0.2), value: selection == .camera)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .background(
                floatingTabBarShellShape
                    .fill(.ultraThinMaterial)
                    .overlay(
                        floatingTabBarShellShape
                            .fill(Color.black.opacity(colorScheme == .light ? 0.18 : 0.35))
                    )
                    .liquidGlassBackground(
                        in: floatingTabBarShellShape,
                        tint: floatingTabBarShellTint
                    )
            )
            .overlay(
                floatingTabBarShellShape
                    .stroke(Color.white.opacity(colorScheme == .light ? 0.32 : 0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .light ? 0.18 : 0.38), radius: 16, x: 0, y: 10)
        }
    }

    private var compactCaptureNavButton: some View {
        Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                selection = .camera
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Capture")
                    .font(AppType.body(13))
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(tabFrameReporter(for: .camera))
    }

    private var captureActionRow: some View {
        ZStack {
            HStack {
                captureContextButton(
                    systemName: "photo.on.rectangle",
                    label: "Library",
                    action: {
                        NotificationCenter.default.post(name: .reviveOpenCaptureLibrary, object: nil)
                    }
                )

                Spacer(minLength: 0)

                captureContextButton(
                    systemName: "arrow.triangle.2.circlepath",
                    label: "Flip camera",
                    action: {
                        NotificationCenter.default.post(name: .reviveSwitchCaptureCamera, object: nil)
                    }
                )
            }
            .padding(.horizontal, 4)

            captureTabButton
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 52)
    }

    private func captureContextButton(
        systemName: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        let isVisible = selection == .camera

        return Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .frame(width: 46, height: 46)
                .liquidGlassButton(in: Circle(), interactive: isVisible)
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.92)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel(label)
        .animation(.easeInOut(duration: 0.18), value: isVisible)
    }

    private var captureTabButton: some View {
        let isSelected = selection == .camera
        let tap = TapGesture().onEnded {
            if isSelected {
                NotificationCenter.default.post(name: .reviveTriggerCaptureShutter, object: nil)
            } else {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    selection = .camera
                }
            }
        }
        let longPress = LongPressGesture(minimumDuration: 0.45, maximumDistance: 50).onEnded { _ in
            if isSelected {
                // Defer so the gesture cycle fully completes before triggering state changes
                // that remove this view from the hierarchy (keyboard/tab bar interaction).
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .reviveTriggerCaptureTextEntry, object: nil)
                }
            } else {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                    selection = .camera
                }
            }
        }
        let gesture = longPress.exclusively(before: tap)

        return HStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.system(size: 14, weight: .semibold))

            Text("Capture")
                .font(AppType.title(16))
        }
        .foregroundStyle(.white.opacity(isSelected ? 1 : 0.9))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            if isSelected {
                activeTabSelectionBubble
                    .matchedGeometryEffect(id: "main.tab.selection", in: tabSelectionNamespace)
            } else {
                inactiveCaptureBubble
            }
        }
        .contentShape(Capsule(style: .continuous))
        .gesture(gesture)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Capture")
        .accessibilityHint("Tap to take a photo. Hold to type an item.")
        .background(tabFrameReporter(for: .camera))
    }

    private func primaryTabButton(_ item: DockTabItem) -> some View {
        let isSelected = selection == item.tab

        return Button {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                selection = item.tab
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(item.title)
                    .font(AppType.body(13))
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background {
                if isSelected {
                    activeTabSelectionBubble
                        .matchedGeometryEffect(id: "main.tab.selection", in: tabSelectionNamespace)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .background(tabFrameReporter(for: item.tab))
    }

    private func tabFrameReporter(for tab: Tab) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: CustomTabFramePreferenceKey.self,
                value: [tab: proxy.frame(in: .named("mainTabSpace"))]
            )
        }
    }
}


private struct MainTabPages<FloatingBar: View>: View {
    @Binding var selection: MainTabView.Tab
    let guestControlInset: CGFloat
    @Binding var tabButtonFrames: [MainTabView.Tab: CGRect]
    let shouldShowFloatingTabBar: Bool
    let onTextEntryActiveChange: (Bool) -> Void
    let onTextResultActiveChange: (Bool) -> Void
    @ViewBuilder let floatingTabBar: () -> FloatingBar

    var body: some View {
        TabView(selection: $selection) {
            CameraScreen(
                guestHeaderInset: guestControlInset,
                hideNativeBottomControls: true,
                onTextEntryActiveChange: onTextEntryActiveChange,
                onTextResultActiveChange: onTextResultActiveChange
            )
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Capture", systemImage: "camera.fill") }
                .tag(MainTabView.Tab.camera)

            NavigationStack { BinView() }
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Bin", systemImage: "trash.fill") }
                .tag(MainTabView.Tab.bin)

            NavigationStack { HomeFeedView() }
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(MainTabView.Tab.home)

            LeaderboardView { selection = .account }
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Ranks", systemImage: "trophy.fill") }
                .tag(MainTabView.Tab.leaderboard)

            AccountView(guestHeaderInset: guestControlInset)
                .toolbar(.hidden, for: .tabBar)
                .tabItem { Label("Account", systemImage: "person.crop.circle.fill") }
                .tag(MainTabView.Tab.account)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if shouldShowFloatingTabBar {
                floatingTabBar()
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 0)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(CustomTabFramePreferenceKey.self) { frames in
            guard !frames.isEmpty else { return }
            tabButtonFrames = frames
        }
    }
}

private struct MainTabEventHandlers<Content: View>: View {
    @Binding var showGuestPopup: Bool
    @Binding var showResumeOverlay: Bool
    @Binding var showTutorialOverlay: Bool
    @Binding var selection: MainTabView.Tab

    let auth: AuthStore
    let history: HistoryStore
    let leaderboard: LeaderboardStore
    let scenePhase: ScenePhase

    let onPerformInitialGuestQuotaFetch: () async -> Void
    let onGuestQuotaUpdated: (Notification) -> Void
    let onRequestSignIn: (Notification) -> Void
    let onOpenHome: (Notification) -> Void
    let onOpenCapture: (Notification) -> Void
    let onOpenBin: (Notification) -> Void
    let onRequestUpgrade: (Notification) -> Void
    let onOpenTutorial: (Notification) -> Void
    let onTutorialVisibilityChange: (Bool) -> Void
    let onSelectionChange: (MainTabView.Tab) -> Void
    let onAuthSignInChange: (Bool) -> Void
    let onUserIDChange: (String) -> Void
    let onAccessTokenChange: (String) -> Void
    let onCapturePhotoVisibilityChange: (Bool) -> Void
    let onAppear: () -> Void
    let onHistoryEntriesChange: ([HistoryEntry]) -> Void
    let onScenePhaseChange: (ScenePhase) -> Void

    @ViewBuilder var content: () -> Content

    var body: some View {
        let base = content()
            .animation(.easeInOut(duration: 0.22), value: showGuestPopup)
            .animation(.easeInOut(duration: 0.2), value: showResumeOverlay)
            .animation(.easeInOut(duration: 0.2), value: showTutorialOverlay)
            .tint(AppTheme.mint)
            .task { await onPerformInitialGuestQuotaFetch() }
        let withNotifications = base
            .onReceive(
                NotificationCenter.default.publisher(for: .reviveGuestQuotaUpdated)
                    .receive(on: RunLoop.main)
            ) { note in onGuestQuotaUpdated(note) }
            .onReceive(NotificationCenter.default.publisher(for: .reviveRequestSignIn)) { note in onRequestSignIn(note) }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenHome)) { note in onOpenHome(note) }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenCapture)) { note in onOpenCapture(note) }
            .onReceive(NotificationCenter.default.publisher(for: .reviveCapturePhotoVisibilityChanged)) { note in
                onCapturePhotoVisibilityChange((note.object as? Bool) ?? false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenBin)) { note in onOpenBin(note) }
            .onReceive(NotificationCenter.default.publisher(for: .reviveRequestUpgrade)) { note in onRequestUpgrade(note) }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenTutorial)) { note in onOpenTutorial(note) }
        return withNotifications
            .onChange(of: showTutorialOverlay) { _, isVisible in onTutorialVisibilityChange(isVisible) }
            .onChange(of: selection) { _, newValue in onSelectionChange(newValue) }
            .onChange(of: auth.isSignedIn) { _, newValue in onAuthSignInChange(newValue) }
            .onChange(of: auth.user?.id ?? "") { _, newValue in onUserIDChange(newValue) }
            .onChange(of: auth.session?.accessToken ?? "") { _, token in onAccessTokenChange(token) }
            .onChange(of: auth.user?.displayName ?? "") { _, _ in leaderboard.refreshNow() }
            .onAppear { onAppear() }
            .onChange(of: history.entries) { _, entries in onHistoryEntriesChange(entries) }
            .onChange(of: scenePhase) { _, newPhase in onScenePhaseChange(newPhase) }
    }
}

private struct GuestSignInPopup: View {
    let remaining: Int?
    let limit: Int
    let onDragOffsetChanged: (CGFloat) -> Void
    let onDismiss: () -> Void
    let onSignIn: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("You're browsing as a guest")
                    .font(AppType.title(16))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)

                Text("Sign in to earn points and track your recycling impact.")
                    .font(AppType.body(13))
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 8) {
                Text("\(remainingText) / \(max(1, limit)) left")
                    .font(AppType.body(12))
                    .foregroundStyle(AppTheme.mint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .lineLimit(1)

                Button("Sign In") {
                    onSignIn()
                }
                .font(AppType.title(15))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(AppTheme.mint))
                .buttonStyle(.plain)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 16)
        .padding(.trailing, 44)
        .padding(.vertical, 12)
        .frame(maxWidth: horizontalSizeClass == .regular ? 620 : 430, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(guestPopupBorderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .liquidGlassButton(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .offset(y: dragOffset.height)
        .gesture(
            DragGesture(minimumDistance: 8)
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation
                        onDragOffsetChanged(value.translation.height)
                    } else {
                        dragOffset = .zero
                        onDragOffsetChanged(0)
                    }
                }
                .onEnded { value in
                    if value.translation.height < -24 {
                        onDragOffsetChanged(0)
                        onDismiss()
                        return
                    }
                    dragOffset = .zero
                    onDragOffsetChanged(0)
                }
        )
        .onAppear {
            onDragOffsetChanged(0)
        }
        .onDisappear {
            onDragOffsetChanged(0)
        }
    }

    private var remainingText: String {
        guard let remaining else { return "--" }
        return "\(max(0, remaining))"
    }

    private var guestPopupBorderColor: Color {
        colorScheme == .light ? Color.white.opacity(0.92) : Color.primary.opacity(0.18)
    }
}

private struct AppResumeOverlay: View {
    @State private var logoScale: CGFloat = 0.94
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image("LandscapeLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 170, height: 54)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.32)) {
                logoOpacity = 1
                logoScale = 1
            }
        }
    }
}

private struct BeginnerTipsOverlay: View {
    @Binding var currentTab: MainTabView.Tab
    let tabFrames: [MainTabView.Tab: CGRect]
    let bottomClearance: CGFloat
    let onClose: () -> Void

    @State private var stepIndex: Int = 0

    private let steps: [BeginnerTipStep] = [
        BeginnerTipStep(
            title: "Capture Tab",
            message: "Tap Capture to scan an item and run analysis.",
            targetTab: .camera
        ),
        BeginnerTipStep(
            title: "Bin Tab",
            message: "Go to Bin after a scan. Tap an item to mark it recycled.",
            targetTab: .bin
        ),
        BeginnerTipStep(
            title: "Home Tab",
            message: "Open Home for quick Scan Now access, today's recycling tip, stats, and Challenges to earn XP.",
            targetTab: .home
        ),
        BeginnerTipStep(
            title: "Leaderboard Tab",
            message: "Open Ranks to compare your CO2e impact with top recyclers.",
            targetTab: .leaderboard
        ),
        BeginnerTipStep(
            title: "Account Tab",
            message: "Use Account to sign in and manage settings. Open Home and tap the top-right question mark for Help and tutorial replays.",
            targetTab: .account
        )
    ]

    var body: some View {
        GeometryReader { proxy in
            let step = steps[stepIndex]
            let safeBottom = proxy.safeAreaInsets.bottom
            let highlightedRect = tabFrames[step.targetTab]

            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()

                if let highlightedRect {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(AppTheme.mint, lineWidth: 4)
                        .frame(width: highlightedRect.width + 8, height: highlightedRect.height + 8)
                        .position(x: highlightedRect.midX, y: highlightedRect.midY)
                        .shadow(color: AppTheme.mint.opacity(0.55), radius: 12, x: 0, y: 0)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        if stepIndex < steps.count - 1 {
                            Button("Skip") {
                                onClose()
                            }
                            .font(AppType.body(15))
                            .foregroundStyle(.white.opacity(0.95))
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    Spacer()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Beginner Tips")
                            .font(AppType.title(18))
                            .foregroundStyle(AppTheme.mint)

                        Text(step.title)
                            .font(AppType.display(30))
                            .foregroundStyle(.white)

                        Text(step.message)
                            .font(AppType.body(17))
                            .foregroundStyle(.white.opacity(0.95))
                            .fixedSize(horizontal: false, vertical: true)

                        Button(stepIndex == steps.count - 1 ? "Done" : "Next Step") {
                            if stepIndex == steps.count - 1 {
                                onClose()
                            } else {
                                stepIndex += 1
                            }
                        }
                        .font(AppType.title(15))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.mint))
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.black.opacity(0.55))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 14)
                    .padding(.bottom, max(18, safeBottom + bottomClearance))
                }
            }
            .onAppear {
                currentTab = step.targetTab
            }
            .onChange(of: stepIndex) { _, newValue in
                guard steps.indices.contains(newValue) else { return }
                currentTab = steps[newValue].targetTab
            }
        }
        .allowsHitTesting(true)
    }
}

private struct BeginnerTipStep {
    let title: String
    let message: String
    let targetTab: MainTabView.Tab
}

private struct DockTabItem: Identifiable {
    let tab: MainTabView.Tab
    let title: String
    let icon: String

    var id: MainTabView.Tab { tab }
}

private struct FloatingTabBarShellShape: Shape {
    var collapseProgress: CGFloat
    var minimumTopWidth: CGFloat
    var cornerRadius: CGFloat

    var animatableData: CGFloat {
        get { collapseProgress }
        set { collapseProgress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let safeMinimumTopWidth = max(0, min(minimumTopWidth, rect.width - 24))
        let topInset = max(0, ((rect.width - safeMinimumTopWidth) * 0.5) * collapseProgress)
        let topLeftX = rect.minX + topInset
        let topRightX = rect.maxX - topInset
        let bottomRadius = min(cornerRadius, min(rect.width, rect.height) * 0.5)
        let topRadius = min(bottomRadius, (topRightX - topLeftX) * 0.5)
        let shoulderRadius = min(bottomRadius, topInset)
        let shoulderStartFraction: CGFloat = 0.22
        let minimumShoulderClearance: CGFloat = 1
        let shoulderY = min(
            rect.maxY - bottomRadius - shoulderRadius - 6,
            max(rect.minY + topRadius + shoulderRadius + minimumShoulderClearance, rect.minY + (rect.height * shoulderStartFraction))
        )

        var path = Path()
        path.move(to: CGPoint(x: topLeftX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: topRightX - topRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: topRightX, y: rect.minY + topRadius),
            control: CGPoint(x: topRightX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: topRightX, y: shoulderY - shoulderRadius))
        path.addQuadCurve(
            to: CGPoint(x: topRightX + shoulderRadius, y: shoulderY),
            control: CGPoint(x: topRightX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - shoulderRadius, y: shoulderY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: shoulderY + shoulderRadius),
            control: CGPoint(x: rect.maxX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: shoulderY + shoulderRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + shoulderRadius, y: shoulderY),
            control: CGPoint(x: rect.minX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: topLeftX - shoulderRadius, y: shoulderY))
        path.addQuadCurve(
            to: CGPoint(x: topLeftX, y: shoulderY - shoulderRadius),
            control: CGPoint(x: topLeftX, y: shoulderY)
        )
        path.addLine(to: CGPoint(x: topLeftX, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: topLeftX + topRadius, y: rect.minY),
            control: CGPoint(x: topLeftX, y: rect.minY)
        )
        return path
    }
}

private struct CustomTabFramePreferenceKey: PreferenceKey {
    static var defaultValue: [MainTabView.Tab: CGRect] = [:]

    static func reduce(value: inout [MainTabView.Tab: CGRect], nextValue: () -> [MainTabView.Tab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct IdentityModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

#Preview {
    MainTabView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
        .environmentObject(LeaderboardStore())
}
