//
//  HomeFeedView.swift
//  Recyclability
//

import SwiftUI
import UIKit

struct HomeFeedView: View {
    @EnvironmentObject private var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("revive.tutorial.mainTabs.overlayVisible") private var isMainTutorialOverlayActive = false

    @State private var showChallengeMenu = false
    @State private var challengeXP = ChallengeProgression.currentXP()
    @State private var completedChallengeIDs: Set<String> = ChallengeProgression.completedChallengeIDs()
    @State private var streakStats = RecycleStreakStats(
        currentDays: 0,
        longestDays: 0,
        isRecordedToday: false,
        lastRecycledDay: nil,
        nextMilestoneDays: 3,
        nextMilestoneXP: 50
    )
    @State private var homeChallengeTutorialStep: HomeChallengeTutorialStep?
    @State private var queueLevelTutorialAfterChallengeSheet = false
    @State private var hasUserScrolledTowardChallenges = false
    @State private var shouldTrackHomeChallengeTutorial = false
    @State private var showStreakMenu = false
    @State private var streakRewardQueue: [StreakMilestoneReward] = []
    @State private var activeStreakReward: StreakMilestoneReward?
    @State private var showStreakCompletionToast = false
    @State private var streakToastProgress: CGFloat = 0
    @State private var streakToastShowsCheck = false
    @State private var showChallengeConfetti = false
    @State private var challengeCompletionQueue: [String] = []
    @State private var activeChallengeCompletionTitle: String?
    @State private var showChallengeCompletionToast = false
    @State private var challengeToastProgress: CGFloat = 0
    @State private var challengeToastShowsCheck = false
    @State private var challengeToastTask: Task<Void, Never>?
    @State private var streakToastTask: Task<Void, Never>?
    @State private var isPreparingHomeChallengeTutorial = false
    @State private var isHomeScrollDragging = false
    @State private var shouldTriggerChallengeTutorialAfterDragEnds = false
    @State private var activeInsightCardID: String?
    @State private var isChallengesCardMostlyVisible = false

    private let homeChallengeTutorialKey = "revive.tutorial.home.challengeFlow"
    private let homeChallengeReplayPendingKey = "revive.tutorial.home.challengeFlow.replayPending"
    private let homeChallengeReplayRequestedAtKey = "revive.tutorial.home.challengeFlow.replayRequestedAt"
    private let homeTopAnchorID = "revive.home.scroll.top"
    private let homeChallengesCardID = "revive.home.feed.challenge.card"

    private let dailyTips = [
        "Rinse food residue from bottles and jars before recycling.",
        "Keep paper and cardboard dry to protect fiber quality.",
        "Flatten cardboard boxes to save bin space.",
        "Remove plastic film and tape from cardboard when possible.",
        "Recycle metal cans empty and dry.",
        "Place caps back on plastic bottles only if local rules allow.",
        "Do not bag recyclables unless your city asks for it.",
        "Keep plastic bags out of curbside bins.",
        "Return plastic bags to grocery store drop bins.",
        "Compost food scraps instead of putting them in landfill.",
        "Use a reusable bottle to reduce single-use plastic.",
        "Break down shipping boxes before bin day.",
        "Donate clean clothing and textiles before discarding.",
        "Recycle glass bottles and jars without ceramic contamination.",
        "Keep shattered glass out of curbside recycling.",
        "Reuse sturdy jars for storage before recycling.",
        "Check local rules for black plastic items.",
        "Keep battery terminals taped before drop-off.",
        "Take rechargeable batteries to proper battery collection sites.",
        "Recycle e-waste at certified collection centers.",
        "Remove food from pizza boxes before recycling clean sections.",
        "Compost greasy pizza box bottoms if accepted locally.",
        "Empty aerosol cans completely before recycling where allowed.",
        "Keep propane tanks out of household recycling bins.",
        "Use refill packs to reduce packaging waste.",
        "Choose products with recycled-content packaging.",
        "Avoid wish-cycling; when in doubt check local guidance.",
        "Keep hoses, cords, and wires out of curbside carts.",
        "Recycle aluminum foil only when clean and balled up.",
        "Rinse peanut butter jars to prevent contamination.",
        "Do not place diapers in recycling bins.",
        "Recycle newspapers and mail without plastic sleeves.",
        "Remove plastic windows from envelopes if required locally.",
        "Keep Styrofoam out unless your area accepts it.",
        "Recycle cartons only if your local program accepts them.",
        "Drain liquids fully from containers before recycling.",
        "Skip shredding paper when possible; intact paper recycles better.",
        "Bring reusable bags for shopping trips.",
        "Repair items before replacing them.",
        "Donate furniture in usable condition.",
        "Keep light bulbs separated; many need special drop-off.",
        "Return ink cartridges through retailer take-back programs.",
        "Remove pumps from lotion bottles when possible.",
        "Bundle small metal lids inside a larger can if allowed.",
        "Keep yard waste separate from mixed trash.",
        "Leave recyclables loose in the cart for easier sorting.",
        "Rinse takeout containers before recycling clean plastic.",
        "Compost coffee grounds and paper filters.",
        "Recycle steel food cans after a quick rinse.",
        "Remove food-soiled paper towels from recycling streams.",
        "Choose durable goods over disposable alternatives.",
        "Avoid mixed-material packaging when shopping.",
        "Prefer glass or metal containers that are widely recyclable.",
        "Keep hazardous chemicals out of household trash.",
        "Bring old paint to household hazardous waste events.",
        "Return used motor oil to approved collection sites.",
        "Store recyclables dry indoors before pickup day.",
        "Break apart nested items so sorters can separate materials.",
        "Keep receipts out of paper recycling when they are thermal paper.",
        "Use both sides of paper before recycling.",
        "Recycle holiday lights at specialty drop-offs.",
        "Donate working electronics before recycling them.",
        "Remove batteries from electronics before disposal.",
        "Compost fruit and vegetable scraps when possible.",
        "Use reusable food containers for leftovers.",
        "Recycle empty detergent bottles after rinsing.",
        "Keep cups with wax or plastic lining out unless accepted.",
        "Rinse pet food cans before recycling.",
        "Choose concentrated cleaning products to reduce packaging.",
        "Refill soap dispensers instead of buying new bottles.",
        "Avoid contaminants like food, liquids, and grease in recycling.",
        "Place glass in designated bins where curbside does not accept it.",
        "Recycle scrap metal at local metal yards when possible.",
        "Check resin numbers on plastics, then confirm local acceptance.",
        "Keep syringes and medical sharps out of household bins.",
        "Use approved sharps disposal programs for medical waste.",
        "Compost leaves and grass clippings to enrich soil.",
        "Avoid buying single-use partyware when reusable options exist.",
        "Recycle empty spray cleaner bottles after removing trigger if required.",
        "Keep rubber items out of recycling unless a specialty program exists.",
        "Return shoe boxes and paperboard packaging to recycling.",
        "Donate books in good condition before recycling paperbacks.",
        "Remove plastic wrap from multipack bottles before recycling.",
        "Save packing peanuts for reuse or take-back programs.",
        "Recycle tin cans and lids according to local guidance.",
        "Keep ceramics and cookware out of glass recycling.",
        "Bring reusable cups for coffee to reduce waste.",
        "Choose bar soaps with minimal packaging.",
        "Wash and dry reusable straws and utensils for repeated use.",
        "Recycle clean aluminum trays and pie tins.",
        "Compost biodegradable tea bags when plastic-free.",
        "Keep napkins and tissues out of paper recycling.",
        "Use municipal drop-off centers for oversized recyclables.",
        "Keep mirrors and window glass out of bottle glass streams.",
        "Recycle printer paper separately if your office has a dedicated bin.",
        "Flatten milk and juice cartons where accepted.",
        "Place bottle caps and lids according to your city's rule.",
        "Keep construction debris out of household recycling.",
        "Plan meals to reduce food waste and compost scraps.",
        "Set up labeled bins at home to reduce sorting mistakes.",
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

    private var metrics: HomeFeedMetrics {
        HomeFeedMetrics(entries: history.entries)
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
                id: "recycling-myth",
                title: "Recycling Myth",
                body: strippedLeadingLabel(from: todayMythFact.myth, label: "Myth:"),
                symbol: "exclamationmark.triangle.fill",
                tint: Color.orange
            ),
            HomeFeedCardData(
                id: "recycling-fact",
                title: "Recycling Fact",
                body: strippedLeadingLabel(from: todayMythFact.fact, label: "Fact:"),
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

    private var challengeCard: HomeFeedCardData? {
        feedCards.first(where: \.opensChallengeMenu)
    }

    private var insightCards: [HomeFeedCardData] {
        feedCards.filter { !$0.opensChallengeMenu }
    }

    var body: some View {
        ZStack {
            AppTheme.backgroundGradient(colorScheme)
                .ignoresSafeArea()

            GeometryReader { pageGeo in
                ScrollViewReader { _ in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            Group {
                                Color.clear
                                    .frame(height: 0)
                            }
                            .id(homeTopAnchorID)

                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Home")
                                        .font(AppType.display(30))
                                        .foregroundStyle(.primary)

                                }

                                Spacer(minLength: 8)

                                NavigationLink {
                                    HelpCenterView()
                                } label: {
                                    Image(systemName: "questionmark")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(.primary)
                                        .frame(width: 40, height: 40)
                                        .liquidGlassButton(in: Circle(), interactive: true)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Open help")
                            }

                            streakHeroCard
                            scanNowHeroButton

                            statsRow
                            dailyTipCard
                            challengeSection()
                            insightsSection(cardWidth: min(320, pageGeo.size.width - 84))
                        }
                        .padding(.horizontal, AppLayout.pageHorizontalPadding(for: pageGeo.size.width))
                        .padding(.top, AppLayout.pageTopPadding(for: pageGeo.size.width))
                        .padding(.bottom, AppLayout.pageBottomPadding(for: pageGeo.size.width))
                        .adaptivePageFrame(width: pageGeo.size.width)
                    }
                    .simultaneousGesture(homeChallengeTutorialDragGesture())
                    .overlayPreferenceValue(HomeTutorialTargetPreferenceKey.self) { anchors in
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear {
                                    let visible = challengesCardIsMostlyVisible(in: proxy, anchors: anchors)
                                    updateChallengesCardVisibility(visible)
                                }
                                .onChange(of: challengesCardIsMostlyVisible(in: proxy, anchors: anchors)) { _, visible in
                                    updateChallengesCardVisibility(visible)
                                }

                            if shouldTrackHomeChallengeTutorial,
                               let step = homeChallengeTutorialStep,
                               !showChallengeMenu,
                               let anchor = anchors[step.target] {
                                TargetTutorialOverlay(
                                    targetRect: proxy[anchor],
                                    title: step.title,
                                    message: step.message,
                                    buttonTitle: step.buttonTitle,
                                    onDone: step.showsCardButton ? {
                                        handleHomeChallengeTutorialAction(step)
                                    } : nil,
                                    highlightStyle: step.highlightStyle,
                                    showDirectionalArrow: step.showDirectionalArrow,
                                    showPressIndicator: step.showPressIndicator,
                                    onTargetTap: step.targetIsTappable ? {
                                        handleHomeChallengeTutorialAction(step)
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
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                homeChallengeTutorialStep = .level
                            }
                        }
                    }
                    .onAppear {
                        consumePendingHomeChallengeReplayIfNeeded()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .reviveOpenHome)) { _ in
                        consumePendingHomeChallengeReplayIfNeeded()
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .reviveReplayHomeChallengeTutorial)) { _ in
                        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: homeChallengeReplayRequestedAtKey)
                        UserDefaults.standard.set(true, forKey: homeChallengeReplayPendingKey)
                        consumePendingHomeChallengeReplayIfNeeded()
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

            if showStreakCompletionToast, let reward = activeStreakReward {
                VStack {
                    StreakCompletionToast(
                        reward: reward,
                        progress: streakToastProgress,
                        showsCheck: streakToastShowsCheck
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, showChallengeCompletionToast ? 68 : 12)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(340)
            }
        }
        .sheet(isPresented: $showChallengeMenu) {
            ChallengeMenuView(
                xp: challengeXP,
                completedIDs: completedChallengeIDs,
                entries: history.entries
            )
        }
        .sheet(isPresented: $showStreakMenu) {
            StreakMenuView(
                streak: streakStats,
                recycledDays: recycledStreakDays,
                milestones: ChallengeProgression.streakMilestones(),
                claimedMilestoneDays: ChallengeProgression.claimedStreakMilestoneDays(),
                onScanNow: {
                    showStreakMenu = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        openCapture()
                    }
                }
            )
        }
        .animation(.easeInOut(duration: 0.22), value: showChallengeConfetti)
        .animation(.easeInOut(duration: 0.2), value: showChallengeCompletionToast)
        .animation(.easeInOut(duration: 0.2), value: showStreakCompletionToast)
        .onAppear {
            shouldTrackHomeChallengeTutorial = !UserDefaults.standard.bool(forKey: homeChallengeTutorialKey)
            refreshProgressionState()
            refreshStreakStateAndRewards()
            autoCompleteEligibleChallenges()
        }
        .onChange(of: history.entries) { _, _ in
            refreshStreakStateAndRewards()
            autoCompleteEligibleChallenges()
        }
        .onReceive(NotificationCenter.default.publisher(for: .reviveChallengeProgressUpdated)) { _ in
            refreshProgressionState()
        }
        .onDisappear {
            challengeToastTask?.cancel()
            challengeToastTask = nil
            streakToastTask?.cancel()
            streakToastTask = nil
            isHomeScrollDragging = false
            shouldTriggerChallengeTutorialAfterDragEnds = false
        }
    }

    private var dailyTipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(AppTheme.mint)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.mint.opacity(0.15), in: Circle())

                Text("Today's Tip")
                    .font(AppType.title(16))
                    .foregroundStyle(.primary)
            }

            Text(todayTip)
                .font(AppType.body(15))
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            Text(encouragementText)
                .font(AppType.body(12))
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 22)
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

    private var streakHeroCard: some View {
        Button {
            showStreakMenu = true
        } label: {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Streak")
                        .font(AppType.body(13))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(streakStats.currentDays)")
                            .font(AppType.display(48))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                        Text("days")
                            .font(AppType.title(20))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                    }

                    Text(streakHeadlineText)
                        .font(AppType.body(14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    if let nextDays = streakStats.nextMilestoneDays,
                       let nextXP = streakStats.nextMilestoneXP {
                        Text("Next milestone: \(nextDays)d (+\(nextXP) XP)")
                            .font(AppType.body(12))
                            .foregroundStyle(AppTheme.mint)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 16)

                VStack(alignment: .trailing, spacing: 8) {
                    StreakFlameBadge(currentDays: streakStats.currentDays, size: 64)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .staticCard(cornerRadius: 22)
        }
        .buttonStyle(.plain)
    }

    private var streakHeadlineText: String {
        if streakStats.currentDays == 0 {
            return "Start today and build your streak."
        }
        if streakStats.isRecordedToday {
            return "Great work. Today's recycle is locked in."
        }
        return "Recycle today to keep your streak alive."
    }

    private var recycledStreakDays: Set<Date> {
        let calendar = Calendar.current
        return Set(
            history.entries
                .filter { $0.recycleStatus == .recycled }
                .map { calendar.startOfDay(for: $0.date) }
        )
    }

    private var scanNowHeroButton: some View {
        Button {
            openCapture()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .bold))
                Text("Scan Now")
                    .font(AppType.title(20))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(AppTheme.mint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: AppTheme.mint.opacity(colorScheme == .light ? 0.28 : 0.40), radius: 20, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func challengeSection() -> some View {
        if let challengeCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Challenges")
                        .font(AppType.title(19))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button("View All") {
                        openChallengeMenu()
                    }
                    .font(AppType.body(13))
                    .foregroundStyle(AppTheme.mint)
                    .buttonStyle(.plain)
                }

                if shouldTrackHomeChallengeTutorial {
                    Button {
                        openChallengeMenu()
                    } label: {
                        HomeFeedCard(data: challengeCard)
                    }
                    .buttonStyle(.plain)
                    .id(homeChallengesCardID)
                    .anchorPreference(key: HomeTutorialTargetPreferenceKey.self, value: .bounds) { anchor in
                        [.challenges: anchor]
                    }
                } else {
                    Button {
                        openChallengeMenu()
                    } label: {
                        HomeFeedCard(data: challengeCard)
                    }
                    .buttonStyle(.plain)
                    .id(homeChallengesCardID)
                }
            }
        }
    }

    private func insightsSection(cardWidth: CGFloat) -> some View {
        let insightCardHeight: CGFloat = 144

        return VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(AppType.title(19))
                .foregroundStyle(.primary)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(insightCards) { card in
                        HomeFeedCard(data: card, bodyLineLimit: 3, isCompact: true)
                            .frame(width: cardWidth, height: insightCardHeight, alignment: .topLeading)
                            .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $activeInsightCardID)
            .onAppear {
                if activeInsightCardID == nil {
                    activeInsightCardID = insightCards.first?.id
                }
            }

            if !insightCards.isEmpty {
                HStack(spacing: 8) {
                    ForEach(insightCards) { card in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                activeInsightCardID = card.id
                            }
                        } label: {
                            Capsule(style: .continuous)
                                .fill(
                                    activeInsightCardID == card.id
                                    ? AppTheme.mint
                                    : Color.primary.opacity(0.22)
                                )
                                .frame(width: activeInsightCardID == card.id ? 20 : 8, height: 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: activeInsightCardID)
            }
        }
    }

    private func openCapture() {
        NotificationCenter.default.post(name: .reviveOpenCapture, object: nil)
    }

    private func refreshProgressionState() {
        challengeXP = ChallengeProgression.currentXP()
        completedChallengeIDs = ChallengeProgression.completedChallengeIDs()
    }

    private func refreshStreakStateAndRewards() {
        streakStats = ChallengeProgression.streakStats(entries: history.entries)
        let rewards = ChallengeProgression.claimStreakMilestones(entries: history.entries)
        guard !rewards.isEmpty else { return }
        refreshProgressionState()
        triggerChallengeConfetti()
        enqueueStreakRewards(rewards)
    }

    private func enqueueStreakRewards(_ rewards: [StreakMilestoneReward]) {
        guard !rewards.isEmpty else { return }
        streakRewardQueue.append(contentsOf: rewards)
        presentNextStreakRewardIfNeeded()
    }

    private func presentNextStreakRewardIfNeeded() {
        guard activeStreakReward == nil else { return }
        guard !streakRewardQueue.isEmpty else { return }
        let reward = streakRewardQueue.removeFirst()
        activeStreakReward = reward
        streakToastProgress = 0
        streakToastShowsCheck = false

        withAnimation(.spring(response: 0.3, dampingFraction: 0.92)) {
            showStreakCompletionToast = true
        }

        streakToastTask?.cancel()
        streakToastTask = Task { @MainActor in
            withAnimation(.linear(duration: 0.55)) {
                streakToastProgress = 1
            }

            try? await Task.sleep(nanoseconds: 560_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeOut(duration: 0.12)) {
                streakToastShowsCheck = true
            }

            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.2)) {
                showStreakCompletionToast = false
            }

            try? await Task.sleep(nanoseconds: 230_000_000)
            guard !Task.isCancelled else { return }

            activeStreakReward = nil
            streakToastProgress = 0
            streakToastShowsCheck = false
            presentNextStreakRewardIfNeeded()
        }
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

    private func consumePendingHomeChallengeReplayIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: homeChallengeReplayPendingKey) else { return }

        let requestedAt = defaults.double(forKey: homeChallengeReplayRequestedAtKey)
        let requestAge = Date().timeIntervalSince1970 - requestedAt
        let isRecentReplayRequest = requestedAt > 0 && requestAge <= 30
        guard isRecentReplayRequest else {
            defaults.set(false, forKey: homeChallengeReplayPendingKey)
            defaults.removeObject(forKey: homeChallengeReplayRequestedAtKey)
            return
        }

        defaults.set(false, forKey: homeChallengeReplayPendingKey)
        defaults.removeObject(forKey: homeChallengeReplayRequestedAtKey)
        restartHomeChallengeTutorialReplay()
    }

    private func restartHomeChallengeTutorialReplay() {
        UserDefaults.standard.removeObject(forKey: homeChallengeTutorialKey)
        shouldTrackHomeChallengeTutorial = true
        hasUserScrolledTowardChallenges = true
        queueLevelTutorialAfterChallengeSheet = false
        withAnimation(.easeInOut(duration: 0.2)) {
            homeChallengeTutorialStep = nil
        }
        showChallengeMenu = false
        isPreparingHomeChallengeTutorial = false
        shouldTriggerChallengeTutorialAfterDragEnds = false
        isHomeScrollDragging = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            triggerHomeChallengeTutorialIfNeeded()
        }
    }

    private func triggerHomeChallengeTutorialIfNeeded() {
        guard !isMainTutorialOverlayActive else { return }
        guard shouldTrackHomeChallengeTutorial else { return }
        guard hasUserScrolledTowardChallenges else { return }
        guard isChallengesCardMostlyVisible else { return }
        guard !UserDefaults.standard.bool(forKey: homeChallengeTutorialKey) else { return }
        guard homeChallengeTutorialStep == nil else { return }
        guard !showChallengeMenu else { return }
        guard !isPreparingHomeChallengeTutorial else { return }
        guard !isHomeScrollDragging else {
            shouldTriggerChallengeTutorialAfterDragEnds = true
            return
        }

        isPreparingHomeChallengeTutorial = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard !isMainTutorialOverlayActive else {
                isPreparingHomeChallengeTutorial = false
                return
            }
            guard shouldTrackHomeChallengeTutorial else {
                isPreparingHomeChallengeTutorial = false
                return
            }
            guard !UserDefaults.standard.bool(forKey: homeChallengeTutorialKey) else {
                isPreparingHomeChallengeTutorial = false
                return
            }
            guard homeChallengeTutorialStep == nil else {
                isPreparingHomeChallengeTutorial = false
                return
            }
            guard !showChallengeMenu else {
                isPreparingHomeChallengeTutorial = false
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                homeChallengeTutorialStep = .challenges
            }
            shouldTriggerChallengeTutorialAfterDragEnds = false
            isPreparingHomeChallengeTutorial = false
        }
    }

    private func homeChallengeTutorialDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !isHomeScrollDragging {
                    isHomeScrollDragging = true
                }
            }
            .onEnded { value in
                isHomeScrollDragging = false
                let didScroll = abs(value.translation.height) > 12 || abs(value.translation.width) > 12
                if didScroll {
                    hasUserScrolledTowardChallenges = true
                    triggerHomeChallengeTutorialIfNeeded()
                }
                guard shouldTriggerChallengeTutorialAfterDragEnds else { return }
                shouldTriggerChallengeTutorialAfterDragEnds = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    triggerHomeChallengeTutorialIfNeeded()
                }
            }
    }

    private func challengesCardIsMostlyVisible(
        in proxy: GeometryProxy,
        anchors: [HomeTutorialTarget: Anchor<CGRect>]
    ) -> Bool {
        guard let anchor = anchors[.challenges] else { return false }
        let rect = proxy[anchor]
        guard rect.height > 0 else { return false }

        let viewport = CGRect(origin: .zero, size: proxy.size)
        let visibleHeight = viewport.intersection(rect).height
        let visibleRatio = visibleHeight / rect.height
        return visibleRatio >= 0.8
    }

    private func updateChallengesCardVisibility(_ visible: Bool) {
        if visible != isChallengesCardMostlyVisible {
            isChallengesCardMostlyVisible = visible
        }
        if visible {
            triggerHomeChallengeTutorialIfNeeded()
        }
    }

    private func strippedLeadingLabel(from text: String, label: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix(label.lowercased()) else { return trimmed }
        return String(trimmed.dropFirst(label.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleHomeChallengeTutorialAction(_ step: HomeChallengeTutorialStep) {
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

    init() {}

    init(entries: [HistoryEntry], now: Date = Date(), calendar: Calendar = .current) {
        recycledCount = 0
        markedCount = 0
        totalCarbonSavedKg = 0
        todayRecycledCount = 0

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

private struct StreakCompletionToast: View {
    let reward: StreakMilestoneReward
    let progress: CGFloat
    let showsCheck: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Streak Milestone")
                    .font(AppType.body(11))
                    .foregroundStyle(AppTheme.mint.opacity(0.92))
                Text("\(reward.days)-day streak • +\(reward.xpReward) XP")
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

private struct HomeStatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(AppType.display(34))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(AppType.body(11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 16)
    }
}

private struct HomeProgressCard: View {
    let level: Int
    let carbonSavedKg: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Lvl \(level)")
                .font(AppType.display(34))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(formatCarbon(carbonSavedKg) + " CO2e")
                .font(AppType.body(11))
                .foregroundStyle(AppTheme.mint)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    var bodyLineLimit: Int? = nil
    var isCompact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            HStack(spacing: isCompact ? 8 : 10) {
                Image(systemName: data.symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(data.tint)
                    .frame(width: isCompact ? 24 : 26, height: isCompact ? 24 : 26)
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

            Group {
                if let bodyLineLimit {
                    Text(data.body)
                        .lineLimit(bodyLineLimit)
                } else {
                    Text(data.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(AppType.body(14))
            .foregroundStyle(.primary.opacity(0.86))
            .lineSpacing(2)
            .padding(.vertical, 1)

            Spacer(minLength: 0)
        }
        .padding(isCompact ? 14 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: isCompact ? 20 : 22)
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

private struct StreakMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let streak: RecycleStreakStats
    let recycledDays: Set<Date>
    let milestones: [StreakMilestoneReward]
    let claimedMilestoneDays: Set<Int>
    let onScanNow: () -> Void

    private var calendar: Calendar {
        Calendar.current
    }

    private var monthAnchor: Date {
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var monthGridDates: [Date?] {
        guard let dayRange = calendar.range(of: .day, in: .month, for: monthAnchor) else { return [] }

        let firstWeekday = calendar.component(.weekday, from: monthAnchor)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        var values = Array<Date?>(repeating: nil, count: leadingBlanks)
        for day in dayRange {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthAnchor) {
                values.append(date)
            }
        }

        while values.count % 7 != 0 {
            values.append(nil)
        }

        return values
    }

    private var recycledDaysThisMonth: Int {
        recycledDays.filter { calendar.isDate($0, equalTo: monthAnchor, toGranularity: .month) }.count
    }

    private var streakStatusText: String {
        if streak.currentDays == 0 {
            return "No active streak yet."
        }
        if streak.isRecordedToday {
            return "Today's recycle is recorded."
        }
        return "Recycle today to keep the streak alive."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.backgroundGradient(colorScheme)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .center, spacing: 18) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Current Streak")
                                    .font(AppType.body(12))
                                    .foregroundStyle(.primary.opacity(0.7))

                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(streak.currentDays)")
                                        .font(AppType.display(54))
                                        .foregroundStyle(.primary)
                                        .monospacedDigit()
                                    Text("days")
                                        .font(AppType.title(24))
                                        .foregroundStyle(.primary.opacity(0.9))
                                }

                                Text(streakStatusText)
                                    .font(AppType.body(13))
                                    .foregroundStyle(.primary.opacity(0.82))
                            }

                            Spacer(minLength: 12)

                            StreakFlameBadge(currentDays: streak.currentDays, size: 132)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .staticCard(cornerRadius: 22)

                        HStack(spacing: 10) {
                            streakStatTile(title: "Longest", value: "\(streak.longestDays) days")
                            streakStatTile(
                                title: "Next Reward",
                                value: nextRewardLabel
                            )
                        }

                        streakCalendarCard

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Milestones")
                                .font(AppType.title(18))
                                .foregroundStyle(.primary)

                            ForEach(milestones) { milestone in
                                streakMilestoneRow(milestone)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                }
            }
            .navigationTitle("Streak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Scan Now") {
                        onScanNow()
                    }
                    .foregroundStyle(AppTheme.mint)
                }
            }
        }
    }

    private var nextRewardLabel: String {
        if let days = streak.nextMilestoneDays, let xp = streak.nextMilestoneXP {
            return "\(days)d (+\(xp) XP)"
        }
        return "All unlocked"
    }

    private var streakCalendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Calendar")
                        .font(AppType.title(18))
                        .foregroundStyle(.primary)
                    Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                        .font(AppType.body(12))
                        .foregroundStyle(.primary.opacity(0.66))
                }

                Spacer()

                Text(recycledDaysThisMonth == 1 ? "1 recycle day" : "\(recycledDaysThisMonth) recycle days")
                    .font(AppType.body(12))
                    .foregroundStyle(AppTheme.mint.opacity(0.92))
            }

            LazyVGrid(columns: calendarColumns, spacing: 10) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(AppType.body(11))
                        .foregroundStyle(.primary.opacity(0.52))
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthGridDates.enumerated()), id: \.offset) { _, date in
                    streakCalendarDayCell(date)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 16)
    }

    private func streakStatTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(AppType.body(10))
                .foregroundStyle(.primary.opacity(0.58))
            Text(value)
                .font(AppType.title(15))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 16)
    }

    @ViewBuilder
    private func streakCalendarDayCell(_ date: Date?) -> some View {
        if let date {
            let normalizedDate = calendar.startOfDay(for: date)
            let isRecycled = recycledDays.contains(normalizedDate)
            let isToday = calendar.isDateInToday(date)

            ZStack {
                if isRecycled {
                    Circle()
                        .fill(AppTheme.mint)
                } else if isToday {
                    Circle()
                        .stroke(AppTheme.mint.opacity(0.7), lineWidth: 1.5)
                }

                Text("\(calendar.component(.day, from: date))")
                    .font(AppType.body(12))
                    .fontWeight(isRecycled || isToday ? .bold : .regular)
                    .foregroundStyle(isRecycled ? Color.black : .primary.opacity(0.88))
            }
            .frame(height: 34)
        } else {
            Color.clear
                .frame(height: 34)
        }
    }

    private func streakMilestoneRow(_ milestone: StreakMilestoneReward) -> some View {
        let claimed = claimedMilestoneDays.contains(milestone.days)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(milestone.days)-Day Streak")
                    .font(AppType.title(15))
                    .foregroundStyle(.primary)
                Text("+\(milestone.xpReward) XP")
                    .font(AppType.body(12))
                    .foregroundStyle(AppTheme.mint.opacity(0.92))
            }
            Spacer()
            Text(claimed ? "Claimed" : "Locked")
                .font(AppType.body(12))
                .foregroundStyle(claimed ? .black : .primary.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(claimed ? AppTheme.mint : Color.white.opacity(0.14))
                )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .staticCard(cornerRadius: 16)
    }
}

private struct StreakFlameBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let currentDays: Int
    let size: CGFloat

    private var cappedDays: Double {
        min(Double(max(currentDays, 0)), 100)
    }

    private var intensity: Double {
        min(cappedDays / 30, 1)
    }

    private var flameScale: CGFloat {
        CGFloat(0.92 + (intensity * 0.58))
    }

    private var coreOpacity: Double {
        0.38 + (intensity * 0.5)
    }

    private var glowOpacity: Double {
        if currentDays == 0 {
            return colorScheme == .light ? 0.12 : 0.18
        }
        return colorScheme == .light ? 0.20 + (intensity * 0.18) : 0.24 + (intensity * 0.34)
    }

    private var emberCount: Int {
        if currentDays == 0 {
            return 0
        }
        switch currentDays {
        case ..<3: return 1
        case ..<7: return 2
        case ..<14: return 3
        default: return 4
        }
    }

    private var accentColors: [Color] {
        let ember = Color(red: 1.0, green: 0.73, blue: 0.25)
        let flame = Color(red: 1.0, green: 0.46, blue: 0.18)
        let blaze = Color(red: 1.0, green: 0.24, blue: 0.12)
        if currentDays == 0 {
            return [
                Color(red: 0.42, green: 0.42, blue: 0.46),
                Color(red: 0.14, green: 0.14, blue: 0.16)
            ]
        }
        return intensity > 0.6 ? [ember, flame, blaze] : [ember, flame]
    }

    private var flameGradient: LinearGradient {
        LinearGradient(
            colors: accentColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.66, weight: .heavy))
                .foregroundStyle(flameGradient)
                .scaleEffect(x: flameScale * 1.2, y: flameScale * 1.32)
                .opacity(coreOpacity * 0.28)
                .offset(y: size * 0.03)
                .blur(radius: size * 0.07)

            if currentDays >= 3 {
                Image(systemName: "flame.fill")
                    .font(.system(size: size * 0.66, weight: .heavy))
                    .foregroundStyle(flameGradient)
                    .scaleEffect(x: flameScale * 1.14, y: flameScale * 1.24)
                    .opacity(coreOpacity * 0.45)
                    .offset(y: size * 0.02)
                    .blur(radius: size * 0.03)
            }

            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.62, weight: .heavy))
                .foregroundStyle(flameGradient)
                .scaleEffect(x: flameScale, y: flameScale + CGFloat(intensity * 0.16))
                .shadow(color: accentColors[0].opacity(glowOpacity), radius: size * 0.12, x: 0, y: size * 0.03)

            ForEach(0..<emberCount, id: \.self) { index in
                let orbitAngle = Double(index) * (360.0 / Double(max(emberCount, 1))) - 24
                let radians = orbitAngle * .pi / 180
                let orbitRadius = size * (0.16 + CGFloat(index) * 0.055)
                let x = CGFloat(cos(radians)) * orbitRadius
                let y = (CGFloat(sin(radians)) * orbitRadius) - (size * 0.08)

                Circle()
                    .fill(accentColors[min(index, accentColors.count - 1)].opacity(0.55 + (intensity * 0.24)))
                    .frame(width: size * 0.05, height: size * 0.05)
                    .blur(radius: size * 0.01)
                    .offset(x: x, y: y)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack {
        HomeFeedView()
            .environmentObject(HistoryStore())
            .environmentObject(AuthStore())
    }
}
