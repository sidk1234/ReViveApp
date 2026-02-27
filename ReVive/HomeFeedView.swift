//
//  HomeFeedView.swift
//  Recyclability
//

import SwiftUI
import UIKit

struct HomeFeedView: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showChallengeMenu = false
    @State private var challengeXP = ChallengeProgression.currentXP()
    @State private var completedChallengeIDs: Set<String> = ChallengeProgression.completedChallengeIDs()
    @State private var metrics = HomeFeedMetrics()
    @State private var homeChallengeTutorialStep: HomeChallengeTutorialStep?
    @State private var queueLevelTutorialAfterChallengeSheet = false
    @State private var hasUserScrolledTowardChallenges = false
    @State private var shouldTrackHomeChallengeTutorial = false
    @State private var showChallengeConfetti = false
    @State private var challengeCompletionQueue: [String] = []
    @State private var activeChallengeCompletionTitle: String?
    @State private var showChallengeCompletionToast = false
    @State private var challengeToastProgress: CGFloat = 0
    @State private var challengeToastShowsCheck = false
    @State private var challengeToastTask: Task<Void, Never>?

    private let homeChallengeTutorialKey = "revive.tutorial.home.challengeFlow"
    private let homeTopAnchorID = "revive.home.scroll.top"

    private let dailyTips = [
        "Rinse containers before recycling to prevent contamination.",
        "Plastic bags do not belong in curbside bins; return them to store drop-offs.",
        "Flatten cardboard to save space in recycling bins.",
        "Keep food-soiled paper out of paper recycling to avoid contamination.",
        "Empty and dry metal cans before putting them in recycling.",
    ]

    private let mythFactPairs: [(myth: String, fact: String)] = [
        (
            "Myth: If it has the recycling symbol, it is always recyclable.",
            "Fact: Local rules still decide what is accepted."
        ),
        (
            "Myth: Small plastics are always recyclable.",
            "Fact: Many programs reject small pieces because sorting systems miss them."
        ),
        (
            "Myth: You should bag recyclables before placing them in the bin.",
            "Fact: Loose recyclables are usually required for proper sorting."
        ),
    ]

    private var todayTip: String {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = dayOfYear % dailyTips.count
        return dailyTips[index]
    }

    private var todayMythFact: (myth: String, fact: String) {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let index = dayOfYear % mythFactPairs.count
        return mythFactPairs[index]
    }

    private var recycledCount: Int {
        metrics.recycledCount
    }

    private var markedCount: Int {
        metrics.markedCount
    }

    private var totalCarbonSavedKg: Double {
        metrics.totalCarbonSavedKg
    }

    private var recentEntries: [HistoryEntry] {
        metrics.recentEntries
    }

    private var challengeLevel: Int {
        ChallengeProgression.level(for: challengeXP)
    }

    private var encouragementText: String {
        let todayRecycledCount = metrics.todayRecycledCount
        if todayRecycledCount == 0 {
            return "Start with one recycled item today to build your streak."
        }
        if todayRecycledCount == 1 {
            return "Great start. Recycle one more item today to keep momentum."
        }
        return "Strong progress today. Keep marking items in Bin to grow your impact."
    }

    private var feedCards: [HomeFeedCardData] {
        [
            HomeFeedCardData(
                id: "eco-fact",
                title: "Eco Fact",
                body: "Recycling one aluminum can saves enough energy to run a TV for about three hours.",
                symbol: "bolt.fill",
                tint: AppTheme.sky
            ),
            HomeFeedCardData(
                id: "myth-fact",
                title: "Myth vs Fact",
                body: "\(todayMythFact.myth)\n\(todayMythFact.fact)",
                symbol: "checkmark.seal.fill",
                tint: AppTheme.mint
            ),
            HomeFeedCardData(
                id: "community-milestone",
                title: "Community Milestone",
                body: recycledCount == 0
                    ? "Scan your first recyclable item to start contributing to community impact."
                    : "You have recycled \(recycledCount) item\(recycledCount == 1 ? "" : "s"). Keep it going.",
                symbol: "person.3.fill",
                tint: AppTheme.emerald
            ),
            HomeFeedCardData(
                id: "challenge",
                title: "Challenge",
                body: "Open the challenge board to complete daily, weekly, monthly, and seasonal goals for XP.",
                symbol: "flag.checkered",
                tint: Color(red: 0.98, green: 0.84, blue: 0.35),
                opensChallengeMenu: true
            ),
        ]
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Group {
                            Color.clear
                                .frame(height: 0)
                        }
                        .id(homeTopAnchorID)

                        Text("Home")
                            .font(AppType.display(30))
                            .foregroundStyle(.primary)

                        Text("Daily tips, impact snapshots, and progress-driven challenges.")
                            .font(AppType.body(15))
                            .foregroundStyle(.primary.opacity(0.75))

                        dailyTipCard
                        statsRow
                        recentScansCard

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Feed")
                                .font(AppType.title(18))
                                .foregroundStyle(.primary)

                            LazyVStack(spacing: 10) {
                                ForEach(feedCards) { card in
                                    if card.opensChallengeMenu {
                                        if shouldTrackHomeChallengeTutorial {
                                            Button {
                                                openChallengeMenu()
                                            } label: {
                                                HomeFeedCard(data: card)
                                            }
                                            .buttonStyle(.plain)
                                            .anchorPreference(key: HomeTutorialTargetPreferenceKey.self, value: .bounds) { anchor in
                                                [.challenges: anchor]
                                            }
                                            .onAppear {
                                                hasUserScrolledTowardChallenges = true
                                                triggerHomeChallengeTutorialIfNeeded()
                                            }
                                        } else {
                                            Button {
                                                openChallengeMenu()
                                            } label: {
                                                HomeFeedCard(data: card)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    } else {
                                        HomeFeedCard(data: card)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                }
                .overlayPreferenceValue(HomeTutorialTargetPreferenceKey.self) { anchors in
                    if shouldTrackHomeChallengeTutorial,
                       let step = homeChallengeTutorialStep,
                       !showChallengeMenu,
                       let anchor = anchors[step.target] {
                        GeometryReader { proxy in
                            TargetTutorialOverlay(
                                targetRect: proxy[anchor],
                                title: step.title,
                                message: step.message,
                                buttonTitle: step.buttonTitle,
                                onDone: step.showsCardButton ? {
                                    handleHomeChallengeTutorialAction(step, scrollProxy: scrollProxy)
                                } : nil,
                                highlightStyle: step.highlightStyle,
                                showDirectionalArrow: step.showDirectionalArrow,
                                showPressIndicator: step.showPressIndicator,
                                onTargetTap: step.targetIsTappable ? {
                                    handleHomeChallengeTutorialAction(step, scrollProxy: scrollProxy)
                                } : nil
                            )
                            .transition(.opacity)
                            .zIndex(400)
                        }
                    }
                }
                .onChange(of: showChallengeMenu) { _, isPresented in
                    guard !isPresented, queueLevelTutorialAfterChallengeSheet else { return }
                    queueLevelTutorialAfterChallengeSheet = false
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scrollProxy.scrollTo(homeTopAnchorID, anchor: .top)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            homeChallengeTutorialStep = .level
                        }
                    }
                }
            }

            if showChallengeConfetti {
                ChallengeConfettiView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .zIndex(320)
            }

            if showChallengeCompletionToast, let title = activeChallengeCompletionTitle {
                VStack {
                    ChallengeCompletionToast(
                        title: title,
                        progress: challengeToastProgress,
                        showsCheck: challengeToastShowsCheck
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(330)
            }
        }
        .sheet(isPresented: $showChallengeMenu) {
            ChallengeMenuView(
                xp: challengeXP,
                completedIDs: completedChallengeIDs,
                entries: history.entries
            )
        }
        .animation(.easeInOut(duration: 0.22), value: showChallengeConfetti)
        .animation(.easeInOut(duration: 0.2), value: showChallengeCompletionToast)
        .onAppear {
            shouldTrackHomeChallengeTutorial = !UserDefaults.standard.bool(forKey: homeChallengeTutorialKey)
            refreshHomeMetrics()
            refreshProgressionState()
            autoCompleteEligibleChallenges()
        }
        .onChange(of: history.entries) { _, _ in
            refreshHomeMetrics()
            autoCompleteEligibleChallenges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveChallengeProgressUpdated)) { _ in
            refreshProgressionState()
        }
        .onDisappear {
            challengeToastTask?.cancel()
            challengeToastTask = nil
        }
    }

    private var dailyTipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(AppTheme.mint)

                Text("Today's Recycling Tip")
                    .font(AppType.title(18))
                    .foregroundStyle(.primary)
            }

            Text(todayTip)
                .font(AppType.body(15))
                .foregroundStyle(.primary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            Text(encouragementText)
                .font(AppType.body(12))
                .foregroundStyle(AppTheme.mint.opacity(0.92))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppTheme.deepTeal.opacity(0.85), AppTheme.night.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.mint.opacity(0.4), lineWidth: 1)
        )
        .shadow(color: AppTheme.mint.opacity(0.18), radius: 14, x: 0, y: 8)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            HomeStatCard(title: "Recycled", value: "\(recycledCount)")
            HomeStatCard(title: "In Bin", value: "\(markedCount)")
            if shouldTrackHomeChallengeTutorial {
                HomeProgressCard(level: challengeLevel, carbonSavedKg: totalCarbonSavedKg)
                    .anchorPreference(key: HomeTutorialTargetPreferenceKey.self, value: .bounds) { anchor in
                        [.level: anchor]
                    }
            } else {
                HomeProgressCard(level: challengeLevel, carbonSavedKg: totalCarbonSavedKg)
            }
        }
    }

    private var recentScansCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Scans")
                .font(AppType.title(17))
                .foregroundStyle(.primary)

            if recentEntries.isEmpty {
                Text("No scans yet. Use Capture to analyze your first item.")
                    .font(AppType.body(13))
                    .foregroundStyle(.primary.opacity(0.72))
            } else {
                ForEach(recentEntries) { entry in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(entry.recycleStatus == .recycled ? AppTheme.mint : Color.white.opacity(0.24))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.item.isEmpty ? "Item" : entry.item)
                                .font(AppType.title(14))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text("\(entry.bin) • \(statusLabel(for: entry.recycleStatus))")
                                .font(AppType.body(12))
                                .foregroundStyle(.primary.opacity(0.72))
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(formatCarbon(entry.carbonSavedKg))
                            .font(AppType.body(12))
                            .foregroundStyle(AppTheme.mint.opacity(0.92))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 22)
    }

    private func statusLabel(for status: RecycleEntryStatus) -> String {
        switch status {
        case .markedForRecycle:
            return "Marked"
        case .recycled:
            return "Recycled"
        case .nonRecyclable:
            return "Not recyclable"
        }
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg", clamped)
        }
        return String(format: "%.1f kg", clamped)
    }

    private func refreshProgressionState() {
        challengeXP = ChallengeProgression.currentXP()
        completedChallengeIDs = ChallengeProgression.completedChallengeIDs()
    }

    private func refreshHomeMetrics() {
        metrics = HomeFeedMetrics(entries: history.entries)
    }

    private func openChallengeMenu(fromTutorial: Bool = false) {
        refreshProgressionState()
        if fromTutorial {
            queueLevelTutorialAfterChallengeSheet = true
            withAnimation(.easeInOut(duration: 0.2)) {
                homeChallengeTutorialStep = nil
            }
        }
        showChallengeMenu = true
    }

    private func triggerHomeChallengeTutorialIfNeeded() {
        guard shouldTrackHomeChallengeTutorial else { return }
        guard hasUserScrolledTowardChallenges else { return }
        guard !UserDefaults.standard.bool(forKey: homeChallengeTutorialKey) else { return }
        guard homeChallengeTutorialStep == nil else { return }
        guard !showChallengeMenu else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            homeChallengeTutorialStep = .challenges
        }
    }

    private func handleHomeChallengeTutorialAction(_ step: HomeChallengeTutorialStep, scrollProxy: ScrollViewProxy) {
        switch step {
        case .challenges:
            openChallengeMenu(fromTutorial: true)
        case .level:
            UserDefaults.standard.set(true, forKey: homeChallengeTutorialKey)
            queueLevelTutorialAfterChallengeSheet = false
            shouldTrackHomeChallengeTutorial = false
            withAnimation(.easeInOut(duration: 0.2)) {
                homeChallengeTutorialStep = nil
            }
            withAnimation(.easeInOut(duration: 0.25)) {
                scrollProxy.scrollTo(homeTopAnchorID, anchor: .top)
            }
        }
    }

    private func autoCompleteEligibleChallenges() {
        let activeChallenges = ChallengeCadence.allCases.flatMap { cadence in
            ChallengeProgression.challenges(for: cadence)
        }

        var newlyCompleted: [ActiveChallenge] = []
        for challenge in activeChallenges {
            if ChallengeProgression.complete(challenge, entries: history.entries) {
                newlyCompleted.append(challenge)
            }
        }

        guard !newlyCompleted.isEmpty else { return }
        refreshProgressionState()
        celebrateChallengeCompletions(newlyCompleted)
    }

    private func celebrateChallengeCompletions(_ challenges: [ActiveChallenge]) {
        challengeCompletionQueue.append(contentsOf: challenges.map(\.title))
        triggerChallengeConfetti()
        presentNextChallengeToastIfNeeded()
    }

    private func triggerChallengeConfetti() {
        showChallengeConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeOut(duration: 0.3)) {
                showChallengeConfetti = false
            }
        }
    }

    private func presentNextChallengeToastIfNeeded() {
        guard !showChallengeCompletionToast else { return }
        guard activeChallengeCompletionTitle == nil else { return }
        guard !challengeCompletionQueue.isEmpty else { return }

        let nextTitle = challengeCompletionQueue.removeFirst()
        activeChallengeCompletionTitle = nextTitle
        challengeToastProgress = 0
        challengeToastShowsCheck = false

        withAnimation(.spring(response: 0.3, dampingFraction: 0.92)) {
            showChallengeCompletionToast = true
        }

        challengeToastTask?.cancel()
        challengeToastTask = Task { @MainActor in
            withAnimation(.linear(duration: 0.55)) {
                challengeToastProgress = 1
            }

            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.12)) {
                challengeToastShowsCheck = true
            }

            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showChallengeCompletionToast = false
            }

            try? await Task.sleep(nanoseconds: 230_000_000)
            guard !Task.isCancelled else { return }

            activeChallengeCompletionTitle = nil
            challengeToastProgress = 0
            challengeToastShowsCheck = false
            presentNextChallengeToastIfNeeded()
        }
    }
}

private enum HomeChallengeTutorialStep {
    case challenges
    case level

    var target: HomeTutorialTarget {
        switch self {
        case .challenges:
            return .challenges
        case .level:
            return .level
        }
    }

    var title: String {
        switch self {
        case .challenges:
            return "Challenges"
        case .level:
            return "Level Progress"
        }
    }

    var message: String {
        switch self {
        case .challenges:
            return "Tap the highlighted Challenge card to open goals and start earning XP."
        case .level:
            return "Your level updates from earned XP. Keep completing eligible challenges to level up faster."
        }
    }

    var buttonTitle: String? {
        switch self {
        case .challenges:
            return nil
        case .level:
            return "Done"
        }
    }

    var showsCardButton: Bool {
        buttonTitle != nil
    }

    var targetIsTappable: Bool {
        switch self {
        case .challenges:
            return true
        case .level:
            return false
        }
    }

    var showPressIndicator: Bool {
        switch self {
        case .challenges:
            return true
        case .level:
            return false
        }
    }

    var showDirectionalArrow: Bool {
        switch self {
        case .challenges:
            return false
        case .level:
            return true
        }
    }

    var highlightStyle: TargetTutorialOverlay.HighlightStyle {
        switch self {
        case .challenges:
            return .roundedRect(cornerRadius: 22, padding: 10)
        case .level:
            return .roundedRect(cornerRadius: 16, padding: 8)
        }
    }
}

private enum HomeTutorialTarget: Hashable {
    case challenges
    case level
}

private struct HomeTutorialTargetPreferenceKey: PreferenceKey {
    static var defaultValue: [HomeTutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [HomeTutorialTarget: Anchor<CGRect>],
        nextValue: () -> [HomeTutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct HomeFeedMetrics {
    var recycledCount: Int = 0
    var markedCount: Int = 0
    var totalCarbonSavedKg: Double = 0
    var todayRecycledCount: Int = 0
    var recentEntries: [HistoryEntry] = []

    init() {}

    init(entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current) {
        recycledCount = 0
        markedCount = 0
        totalCarbonSavedKg = 0
        todayRecycledCount = 0
        recentEntries = Array(entries.prefix(4))

        for entry in entries {
            switch entry.recycleStatus {
            case .markedForRecycle:
                markedCount += 1
            case .recycled:
                recycledCount += 1
                totalCarbonSavedKg += max(0, entry.carbonSavedKg)
                if calendar.isDate(entry.date, inSameDayAs: now) {
                    todayRecycledCount += 1
                }
            case .nonRecyclable:
                continue
            }
        }
    }
}

private struct ChallengeCompletionToast: View {
    let title: String
    let progress: CGFloat
    let showsCheck: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Challenge Completed")
                    .font(AppType.body(11))
                    .foregroundStyle(AppTheme.mint.opacity(0.92))
                Text(title)
                    .font(AppType.title(14))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(showsCheck ? AppTheme.mint : Color.white.opacity(0.05))

                Circle()
                    .trim(from: 0, to: showsCheck ? 1 : max(0, min(1, progress)))
                    .stroke(AppTheme.mint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                if showsCheck {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 24, height: 24)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ChallengeConfettiView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = ChallengeConfettiEmitterView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear

        let colors: [UIColor] = [
            UIColor(red: 0.2, green: 0.9, blue: 0.55, alpha: 1.0),
            UIColor(red: 0.2, green: 0.6, blue: 1.0, alpha: 1.0),
            UIColor(red: 0.95, green: 0.78, blue: 0.2, alpha: 1.0),
            UIColor(red: 0.95, green: 0.35, blue: 0.45, alpha: 1.0),
        ]

        view.emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.birthRate = 60
            cell.lifetime = 3.6
            cell.velocity = 320
            cell.velocityRange = 200
            cell.emissionLongitude = .pi
            cell.emissionRange = .pi / 1.8
            cell.spin = 6
            cell.spinRange = 8
            cell.scale = 0.035
            cell.scaleRange = 0.06
            cell.color = color.cgColor
            cell.contents = makeConfettiImage(color: color).cgImage
            return cell
        }

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private func makeConfettiImage(color: UIColor) -> UIImage {
        let size = CGSize(width: 16, height: 10)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let ctx = UIGraphicsGetCurrentContext()
        ctx?.setFillColor(color.cgColor)
        ctx?.fill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}

private final class ChallengeConfettiEmitterView: UIView {
    let emitter = CAEmitterLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        emitter.emitterShape = .line
        emitter.renderMode = .additive
        layer.addSublayer(emitter)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        emitter.emitterShape = .line
        emitter.renderMode = .additive
        layer.addSublayer(emitter)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitter.frame = bounds
        emitter.emitterPosition = CGPoint(x: bounds.midX, y: -10)
        emitter.emitterSize = CGSize(width: bounds.width, height: 1)
    }
}

private let homeStatsCardHeight: CGFloat = 64

private struct HomeStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(AppType.body(11))
                .foregroundStyle(.primary.opacity(0.58))
            Text(value)
                .font(AppType.title(16))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: homeStatsCardHeight, maxHeight: homeStatsCardHeight, alignment: .leading)
        .staticCard(cornerRadius: 16)
    }
}

private struct HomeProgressCard: View {
    let level: Int
    let carbonSavedKg: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("PROGRESS")
                .font(AppType.body(10))
                .foregroundStyle(.primary.opacity(0.58))
            Text("Lvl \(level)")
                .font(AppType.title(15))
                .foregroundStyle(.primary)
            Text("\(formatCarbon(carbonSavedKg)) CO2e")
                .font(AppType.body(10))
                .foregroundStyle(AppTheme.mint.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: homeStatsCardHeight, maxHeight: homeStatsCardHeight, alignment: .leading)
        .staticCard(cornerRadius: 16)
    }

    private func formatCarbon(_ value: Double) -> String {
        let clamped = max(0, value)
        if clamped < 1 {
            return String(format: "%.2f kg", clamped)
        }
        return String(format: "%.1f kg", clamped)
    }
}

private struct HomeFeedCardData: Identifiable {
    let id: String
    let title: String
    let body: String
    let symbol: String
    let tint: Color
    var opensChallengeMenu: Bool = false
}

private struct HomeFeedCard: View {
    let data: HomeFeedCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: data.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(data.tint)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle()
                            .fill(data.tint.opacity(0.18))
                    )

                Text(data.title)
                    .font(AppType.title(15))
                    .foregroundStyle(.primary)

                Spacer()

                if data.opensChallengeMenu {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.6))
                }
            }

            Text(data.body)
                .font(AppType.body(14))
                .foregroundStyle(.primary.opacity(0.86))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 22)
    }
}

private struct ChallengeMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let xp: Int
    let completedIDs: Set<String>
    let entries: [HistoryEntry]

    private var levelProgress: (level: Int, current: Int, target: Int) {
        ChallengeProgression.levelProgress(for: xp)
    }

    private var progressFraction: Double {
        guard levelProgress.target > 0 else { return 0 }
        return min(1, max(0, Double(levelProgress.current) / Double(levelProgress.target)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient(colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        progressHeader

                        ForEach(ChallengeCadence.allCases) { cadence in
                            let challenges = ChallengeProgression.challenges(for: cadence)
                            VStack(alignment: .leading, spacing: 10) {
                                Text(cadence.title + " Challenges")
                                    .font(AppType.title(17))
                                    .foregroundStyle(.primary)

                                ForEach(challenges) { challenge in
                                    let isCompleted = completedIDs.contains(challenge.id)
                                    let isEligible = ChallengeProgression.isEligible(challenge, entries: entries)
                                    let progressText = ChallengeProgression.progressText(for: challenge, entries: entries)
                                    ChallengeRow(
                                        challenge: challenge,
                                        isCompleted: isCompleted,
                                        isEligible: isEligible,
                                        progressText: progressText
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Level \(levelProgress.level)")
                .font(AppType.title(22))
                .foregroundStyle(.primary)

            Text("\(xp) XP total")
                .font(AppType.body(13))
                .foregroundStyle(.primary.opacity(0.75))

            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(AppTheme.mint.opacity(0.9))
                            .frame(width: width * progressFraction)
                    }
                }
                .frame(height: 8)

                Text("\(levelProgress.current) / \(levelProgress.target) XP to next level")
                    .font(AppType.body(11))
                    .foregroundStyle(.primary.opacity(0.65))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 20)
    }
}

private struct ChallengeRow: View {
    let challenge: ActiveChallenge
    let isCompleted: Bool
    let isEligible: Bool
    let progressText: String

    private var statusTitle: String {
        if isCompleted { return "Completed" }
        return isEligible ? "Ready" : "In progress"
    }

    private var statusForeground: Color {
        if isCompleted { return .black }
        return isEligible ? .black : Color.primary.opacity(0.82)
    }

    private var statusBackground: Color {
        if isCompleted { return AppTheme.mint }
        return isEligible ? Color(red: 0.98, green: 0.84, blue: 0.35) : Color.white.opacity(0.12)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(challenge.title)
                    .font(AppType.title(15))
                    .foregroundStyle(.primary)

                Text(challenge.detail)
                    .font(AppType.body(12))
                    .foregroundStyle(.primary.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                Text("+\(challenge.xpReward) XP")
                    .font(AppType.body(11))
                    .foregroundStyle(AppTheme.mint.opacity(0.9))

                Text(progressText)
                    .font(AppType.body(11))
                    .foregroundStyle(.primary.opacity(0.62))
            }

            Spacer(minLength: 10)

            Text(statusTitle)
                .font(AppType.body(12))
                .foregroundStyle(statusForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(statusBackground)
                )
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 18)
    }
}

#Preview {
    NavigationStack {
        HomeFeedView()
            .environmentObject(HistoryStore())
            .environmentObject(AuthStore())
    }
}
