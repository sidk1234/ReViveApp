//
//  MainTabView.swift
//  Recyclability
//

import SwiftUI
import Combine
import UIKit

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var showGuestPopup = false
    @State private var guestDismissTask: Task<Void, Never>?
    @State private var hasShownLaunchGuestPopup = false
    @State private var showResumeOverlay = false
    @State private var wasBackgrounded = false
    @State private var showTutorialOffer = false
    @State private var showTutorialOverlay = false
    @State private var guestPopupDragOffsetY: CGFloat = 0
    @State private var tabButtonFrames: [Tab: CGRect] = [:]

    var body: some View {
        AnyView(baseView)
            .alert(isPresented: $showTutorialOffer) {
                Alert(
                    title: Text(tutorialAlertTitle),
                    message: Text(tutorialAlertMessage),
                    primaryButton: .default(Text("Start")) {
                        auth.consumeTutorialOffer()
                        showTutorialOverlay = true
                    },
                    secondaryButton: .cancel(Text("Later")) {
                        auth.consumeTutorialOffer()
                    }
                )
            }
    }

    private var baseView: some View {
        mainContent
            .animation(.easeInOut(duration: 0.22), value: showGuestPopup)
            .animation(.easeInOut(duration: 0.2), value: showResumeOverlay)
            .animation(.easeInOut(duration: 0.2), value: showTutorialOverlay)
            .tint(AppTheme.mint)
            .task {
                await performInitialGuestQuotaFetch()
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .reviveGuestQuotaUpdated)
                    .receive(on: RunLoop.main)
            ) { note in
                handleGuestQuotaUpdated(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveRequestSignIn)) { note in
                handleRequestSignInNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenHome)) { note in
                handleOpenHomeNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenCapture)) { note in
                handleOpenCaptureNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenBin)) { note in
                handleOpenBinNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveRequestUpgrade)) { note in
                handleRequestUpgradeNotification(note)
            }
            .onReceive(NotificationCenter.default.publisher(for: .reviveOpenTutorial)) { note in
                handleOpenTutorialNotification(note)
            }
            .onChange(of: showTutorialOverlay) { _, isVisible in
                handleTutorialVisibilityChange(isVisible)
            }
            .onChange(of: selection) { _, newValue in
                handleSelectionChange(newValue)
            }
            .onChange(of: auth.isSignedIn) { _, newValue in
                handleAuthSignInChange(newValue)
            }
            .onChange(of: auth.user?.id ?? "") { _, newValue in
                handleUserIDChange(newValue)
            }
            .onAppear {
                handleOnAppear()
            }
            .onChange(of: history.entries) { _, entries in
                handleHistoryEntriesChange(entries)
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
    }

    private let tutorialAlertTitle = "Take a quick tutorial?"
    private let tutorialAlertMessage = "Learn Capture, result details, and how to mark items as recycled in under a minute."

    private var mainContent: some View {
        ZStack(alignment: .top) {
            TabView(selection: $selection) {
                NavigationStack {
                    BinView()
                }
                .tabItem {
                    Label("Bin", systemImage: "trash.fill")
                }
                .tag(Tab.bin)

                CameraScreen(guestHeaderInset: guestControlInset)
                    .tabItem {
                        Label("Capture", systemImage: "camera.fill")
                    }
                .tag(Tab.camera)

                NavigationStack {
                    HomeFeedView()
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

                LeaderboardView {
                    selection = .account
                }
                .tabItem {
                    Label("Ranks", systemImage: "trophy.fill")
                }
                .tag(Tab.leaderboard)

                AccountView(guestHeaderInset: guestControlInset)
                    .tabItem {
                        Label("Account", systemImage: "person.crop.circle.fill")
                    }
                    .tag(Tab.account)
            }

            TabBarCentersReader(tabOrder: [.bin, .camera, .home, .leaderboard, .account]) { frames in
                tabButtonFrames = frames
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)

            if showGuestPopup, !showTutorialOverlay, !auth.isSignedIn {
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
                    onClose: dismissTutorialOverlay
                )
                .transition(.opacity)
                .zIndex(300)
            }
        }
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
        showTutorialOverlay = true
    }

    private func handleTutorialVisibilityChange(_ isVisible: Bool) {
        NotificationCenter.default.post(
            name: .reviveMainTutorialVisibilityChanged,
            object: isVisible
        )
    }

    private func handleSelectionChange(_ newValue: Tab) {
        handleGuestPopup(for: newValue)
    }

    private func handleAuthSignInChange(_ isSignedIn: Bool) {
        if isSignedIn {
            dismissGuestPopup()
            if auth.shouldOfferTutorialAfterSignup {
                showTutorialOffer = true
            }
            return
        }

        hasShownLaunchGuestPopup = false
        Task { @MainActor in
            _ = await auth.fetchGuestQuota()
            presentLaunchGuestPopupIfNeeded()
        }
    }

    private func handleUserIDChange(_ userID: String) {
        guard !userID.isEmpty else { return }
        Task { @MainActor in
            await auth.refreshImpactFromServer(history: history)
            if auth.autoSyncImpactEnabled {
                auth.syncImpact(entries: history.entries, history: history)
            }
        }
    }

    private func handleOnAppear() {
        syncBinReminder(for: history.entries)
        presentLaunchGuestPopupIfNeeded()
    }

    private func handleHistoryEntriesChange(_ entries: [HistoryEntry]) {
        syncBinReminder(for: entries)
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            wasBackgrounded = true
        case .active:
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

    private func handleGuestSignInTap() {
        dismissGuestPopup()
        selection = .account
    }

    private func presentLaunchGuestPopupIfNeeded() {
        guard !auth.isSignedIn else {
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
        withAnimation(.easeInOut(duration: 0.2)) {
            showTutorialOverlay = false
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

    private var guestControlInset: CGFloat {
        guard showGuestPopup, !showTutorialOverlay, !auth.isSignedIn else { return 0 }
        let baseInset: CGFloat = 102
        let dragLift = min(0, guestPopupDragOffsetY)
        return max(0, baseInset + dragLift)
    }
}

private struct GuestSignInPopup: View {
    let remaining: Int?
    let limit: Int
    let onDragOffsetChanged: (CGFloat) -> Void
    let onDismiss: () -> Void
    let onSignIn: () -> Void
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
        .frame(maxWidth: 430, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
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
    let onClose: () -> Void

    @State private var stepIndex: Int = 0

    private let steps: [BeginnerTipStep] = [
        BeginnerTipStep(
            title: "Bin Tab",
            message: "Go to Bin after a scan. Tap an item to mark it recycled.",
            targetTab: .bin
        ),
        BeginnerTipStep(
            title: "Capture Tab",
            message: "Tap Capture to scan an item and run analysis.",
            targetTab: .camera
        ),
        BeginnerTipStep(
            title: "Home Tab",
            message: "Open Home for today's recycling tip, stats, recent scans, and Challenges to earn XP.",
            targetTab: .home
        ),
        BeginnerTipStep(
            title: "Leaderboard Tab",
            message: "Open Ranks to compare your CO2e impact with top recyclers.",
            targetTab: .leaderboard
        ),
        BeginnerTipStep(
            title: "Account Tab",
            message: "Use Account to sign in, manage settings, and access Help. Go to Settings > Help to replay this tutorial anytime.",
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
                    .padding(.bottom, max(18, safeBottom + 70))
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

private struct TabBarCentersReader: UIViewRepresentable {
    let tabOrder: [MainTabView.Tab]
    let onUpdate: ([MainTabView.Tab: CGRect]) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.configure(hostView: view, tabOrder: tabOrder, onUpdate: onUpdate)
        context.coordinator.scheduleRefresh()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.configure(hostView: uiView, tabOrder: tabOrder, onUpdate: onUpdate)
        context.coordinator.scheduleRefresh()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private weak var hostView: UIView?
        private var tabOrder: [MainTabView.Tab] = []
        private var onUpdate: (([MainTabView.Tab: CGRect]) -> Void)?
        private var lastFrames: [MainTabView.Tab: CGRect] = [:]

        func configure(
            hostView: UIView,
            tabOrder: [MainTabView.Tab],
            onUpdate: @escaping ([MainTabView.Tab: CGRect]) -> Void
        ) {
            self.hostView = hostView
            self.tabOrder = tabOrder
            self.onUpdate = onUpdate
        }

        func scheduleRefresh() {
            DispatchQueue.main.async { [weak self] in
                self?.refresh()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.refresh()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.refresh()
            }
        }

        private func refresh() {
            guard let hostView, let onUpdate else { return }
            guard let tabBar = findTabBar(from: hostView) else { return }

            let buttons = tabBar.subviews
                .filter { NSStringFromClass(type(of: $0)).contains("UITabBarButton") }
                .sorted { $0.frame.minX < $1.frame.minX }

            guard buttons.count >= tabOrder.count else { return }

            var frames: [MainTabView.Tab: CGRect] = [:]
            for (index, tab) in tabOrder.enumerated() {
                let button = buttons[index]
                let rect = button.convert(button.bounds, to: hostView)
                let normalizedRect = CGRect(
                    x: rounded(rect.origin.x),
                    y: rounded(rect.origin.y),
                    width: rounded(rect.size.width),
                    height: rounded(rect.size.height)
                )
                frames[tab] = normalizedRect
            }

            guard !frames.isEmpty, frames != lastFrames else { return }
            lastFrames = frames
            onUpdate(frames)
        }

        private func rounded(_ value: CGFloat) -> CGFloat {
            (value * 100).rounded() / 100
        }

        private func findTabBar(from view: UIView) -> UITabBar? {
            if let tabBar = findTabBar(in: view) {
                return tabBar
            }
            guard let window = view.window else { return nil }
            return findTabBar(in: window)
        }

        private func findTabBar(in root: UIView) -> UITabBar? {
            if let tabBar = root as? UITabBar {
                return tabBar
            }
            for subview in root.subviews {
                if let tabBar = findTabBar(in: subview) {
                    return tabBar
                }
            }
            return nil
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(HistoryStore())
        .environmentObject(AuthStore())
}
