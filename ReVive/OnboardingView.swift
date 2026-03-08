import SwiftUI

private enum OnboardingStep: Int, CaseIterable, Hashable {
    case intro
    case scanRecycle
    case levelUp
}

struct OnboardingView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let tagline = "One Scan At A Time."
    private let laterPageVerticalLift: CGFloat = -110

    let onContinue: () -> Void
    @State private var navigationPath: [OnboardingStep] = []
    @State private var typedCharacters = 0
    @State private var showCursor = true
    @State private var typingTask: Task<Void, Never>?
    @State private var cursorTask: Task<Void, Never>?

    private var currentStep: OnboardingStep {
        navigationPath.last ?? .intro
    }

    private var introTaglineColor: Color {
        colorScheme == .light
            ? Color(red: 0.03, green: 0.19, blue: 0.23)
            : .white
    }

    private var pagePrimaryTextColor: Color {
        colorScheme == .light
            ? Color(red: 0.03, green: 0.18, blue: 0.22)
            : .white
    }

    private var pageSecondaryTextColor: Color {
        colorScheme == .light
            ? Color(red: 0.10, green: 0.22, blue: 0.27).opacity(0.9)
            : Color.white.opacity(0.88)
    }

    private var progressTrackColor: Color {
        colorScheme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.18)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            onboardingStepScreen(for: .intro)
                .navigationDestination(for: OnboardingStep.self) { step in
                    onboardingStepScreen(for: step)
                }
        }
        .onAppear {
            startTypewriterAnimation()
            startCursorBlink()
        }
        .onChange(of: currentStep) { _, newValue in
            if newValue == .intro {
                startTypewriterAnimation()
            } else {
                typingTask?.cancel()
                typedCharacters = tagline.count
            }
        }
        .onDisappear {
            typingTask?.cancel()
            cursorTask?.cancel()
            typingTask = nil
            cursorTask = nil
        }
    }

    private func onboardingStepScreen(for step: OnboardingStep) -> some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let compact = proxy.size.height < 760
            let stepHeight = compact ? proxy.size.height * 0.43 : proxy.size.height * 0.46

            ZStack {
                onboardingBackground(for: step)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    switch step {
                    case .intro:
                        introPage(
                            isCompact: compact,
                            safeTop: safeTop,
                            safeBottom: safeBottom,
                            stepHeight: stepHeight,
                            width: proxy.size.width
                        )
                    case .scanRecycle:
                        scanRecyclePage(
                            isCompact: compact,
                            safeTop: safeTop,
                            safeBottom: safeBottom
                        )
                    case .levelUp:
                        levelUpPage(
                            isCompact: compact,
                            safeTop: safeTop,
                            safeBottom: safeBottom
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(step == .intro ? .hidden : .visible, for: .navigationBar)
    }

    // MARK: - Step Layout

    private func onboardingBackground(for step: OnboardingStep) -> LinearGradient {
        _ = step
        return AppTheme.backgroundGradient(colorScheme)
    }

    private func introPage(
        isCompact: Bool,
        safeTop: CGFloat,
        safeBottom: CGFloat,
        stepHeight: CGFloat,
        width: CGFloat
    ) -> some View {
        let titleSize: CGFloat = isCompact ? 24 : 29

        return VStack(spacing: isCompact ? 14 : 26) {
            reviveEarthBrand(
                isCompact: isCompact,
                horizontalOffset: 0,
                boxed: false,
                emphasize: true
            )
            .padding(.top, safeTop + (isCompact ? 8 : 14))
            .layoutPriority(2)

            taglineText(titleSize: titleSize, isCompact: isCompact)
                .padding(.horizontal, 8)
                .frame(minHeight: isCompact ? 38 : 44)

            recycleLoopSteps(isCompact: isCompact)
                .frame(maxWidth: min(360, width - 32))
                .frame(height: stepHeight)
                .padding(.top, isCompact ? 10 : 14)

            Spacer(minLength: isCompact ? 4 : 8)

            footerButton(isCompact: isCompact)
                .padding(.horizontal, 24)
                .padding(.bottom, safeBottom + (isCompact ? 4 : 8))
        }
    }

    private func scanRecyclePage(
        isCompact: Bool,
        safeTop: CGFloat,
        safeBottom: CGFloat
    ) -> some View {
        let sectionSpacing: CGFloat = isCompact ? 14 : 18
        let titleToContentGap: CGFloat = isCompact ? 76 : 98
        let bottomContentInset: CGFloat = safeBottom + (isCompact ? 96 : 114)

        return VStack(spacing: sectionSpacing) {
            Text("Scan & Recycle")
                .font(AppType.display(isCompact ? 36 : 40))
                .foregroundStyle(pagePrimaryTextColor)
                .padding(.top, safeTop + (isCompact ? 2 : 6))

            Color.clear
                .frame(height: titleToContentGap)

            scanPhoneOnAnalyzeStack(isCompact: isCompact)

            Text("Build your streak and track\nyour impact.")
                .font(AppType.body(isCompact ? 16 : 17))
                .foregroundStyle(pageSecondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: advanceStep) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.46, green: 0.97, blue: 0.79),
                                    Color(red: 0.34, green: 0.90, blue: 0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: isCompact ? 56 : 60, height: isCompact ? 56 : 60)
                        .overlay(Circle().stroke(Color.white.opacity(0.26), lineWidth: 1))
                        .overlay {
                            Image(systemName: "arrow.right")
                                .font(.system(size: isCompact ? 23 : 24, weight: .bold))
                                .foregroundStyle(Color(red: 0.03, green: 0.20, blue: 0.15))
                        }
                        .shadow(color: Color.black.opacity(0.32), radius: 9, x: 0, y: 5)

                    Text("Next")
                        .font(AppType.title(isCompact ? 18 : 19))
                        .foregroundStyle(pagePrimaryTextColor.opacity(0.95))
                }
            }
            .buttonStyle(.plain)

            Color.clear
                .frame(height: bottomContentInset)
        }
        .offset(y: laterPageVerticalLift)
    }

    private func levelUpPage(
        isCompact: Bool,
        safeTop: CGFloat,
        safeBottom: CGFloat
    ) -> some View {
        let sectionSpacing: CGFloat = isCompact ? 44 : 56
        let bottomInset: CGFloat = safeBottom + (isCompact ? 84 : 110)

        return VStack(spacing: sectionSpacing) {
            Text("Track Impact\n& Level Up")
                .font(AppType.display(isCompact ? 32 : 36))
                .foregroundStyle(pagePrimaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.top, safeTop + (isCompact ? 34 : 50))
                .padding(.bottom, isCompact ? 18 : 24)

            levelProgressHeader(isCompact: isCompact)
                .padding(.horizontal, 6)

            impactOverviewCard(isCompact: isCompact)
                .padding(.horizontal, 10)

            impactStatsRow(isCompact: isCompact)
                .padding(.horizontal, 10)

            Text("See your real-world progress as each scan cuts\nCO2e and grows your recycling level.")
                .font(AppType.body(isCompact ? 16 : 17))
                .foregroundStyle(pageSecondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onContinue) {
                reviveEarthBrand(
                    isCompact: isCompact,
                    horizontalOffset: -10,
                    boxed: true,
                    emphasize: false
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)

            Color.clear
                .frame(height: bottomInset)
        }
        .offset(y: laterPageVerticalLift)
    }

    @ViewBuilder
    private func footerButton(isCompact: Bool) -> some View {
        Button(action: advanceStep) {
            HStack(spacing: 10) {
                Text("Next")
                    .font(AppType.title(isCompact ? 17 : 19))
                Image(systemName: "arrow.right")
                    .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
            }
            .foregroundStyle(colorScheme == .light ? Color.white : Color.white.opacity(0.96))
            .frame(maxWidth: .infinity)
            .padding(.vertical, isCompact ? 14 : 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .light
                            ? [
                                Color(red: 0.08, green: 0.57, blue: 0.44),
                                Color(red: 0.14, green: 0.72, blue: 0.54)
                            ]
                            : [
                                Color(red: 0.10, green: 0.70, blue: 0.52),
                                Color(red: 0.18, green: 0.84, blue: 0.63)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .light ? 0.26 : 0.34), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .light ? 0.16 : 0.3),
                radius: isCompact ? 8 : 10,
                x: 0,
                y: 5
            )
        }
        .buttonStyle(.plain)
    }

    private func advanceStep() {
        switch currentStep {
        case .intro:
            navigationPath.append(.scanRecycle)
        case .scanRecycle:
            navigationPath.append(.levelUp)
        case .levelUp:
            return
        }
    }

    // MARK: - Scan Mockup

    private func scanPhoneOnAnalyzeStack(isCompact: Bool) -> some View {
        let stackHeight = isCompact ? 388.0 : 430.0
        let analyzeButtonHeight = isCompact ? 72.0 : 78.0
        let overlap = analyzeButtonHeight

        return ZStack(alignment: .bottom) {
            Button(action: {}) {
                analyzeSelectionMockupButton(isCompact: isCompact, expanded: true)
            }
            .buttonStyle(.plain)

            scanMockPhone(isCompact: isCompact)
                .offset(y: -overlap)
        }
        .frame(height: stackHeight)
    }

    private func scanMockPhone(isCompact: Bool) -> some View {
        Image("phone mockup")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: isCompact ? 280 : 312)
            .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 6)
    }

    private func analyzeSelectionMockupButton(isCompact: Bool, expanded: Bool = false) -> some View {
        let width: CGFloat = expanded ? (isCompact ? 308 : 340) : (isCompact ? 232 : 240)
        let height: CGFloat = expanded ? (isCompact ? 72 : 78) : (isCompact ? 56 : 60)
        let fontSize: CGFloat = expanded ? (isCompact ? 20 : 21) : (isCompact ? 15 : 16)
        let iconSize: CGFloat = expanded ? (isCompact ? 15 : 16) : (isCompact ? 13 : 14)
        let radius: CGFloat = expanded ? 24 : 22
        let frostedOpacity: Double = 0.75

        return HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: iconSize, weight: .bold))
            Text("Analyze selection")
                .font(AppType.title(fontSize))
        }
        .foregroundStyle(AppTheme.accentGradient)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color(uiColor: .systemBackground).opacity(0.75), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 9, x: 0, y: 5)
        .opacity(frostedOpacity)
    }

    // MARK: - Level Up

    private func levelProgressHeader(isCompact: Bool) -> some View {
        VStack(spacing: 9) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(progressTrackColor)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.48, green: 0.97, blue: 0.79),
                                    Color(red: 0.34, green: 0.90, blue: 0.72)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: proxy.size.width * 0.60)
                        .shadow(
                            color: Color(red: 0.44, green: 0.96, blue: 0.78)
                                .opacity(colorScheme == .light ? 0.35 : 0.58),
                            radius: isCompact ? 8 : 10,
                            x: 0,
                            y: 0
                        )
                        .shadow(
                            color: Color(red: 0.44, green: 0.96, blue: 0.78)
                                .opacity(colorScheme == .light ? 0.18 : 0.32),
                            radius: isCompact ? 14 : 18,
                            x: 0,
                            y: 0
                        )
                }
            }
            .frame(height: isCompact ? 17 : 19)

            HStack {
                Text("Level 1")
                Spacer()
                Image(systemName: "arrow.right")
                Spacer()
                Text("Level 2")
            }
            .font(AppType.title(isCompact ? 15 : 16))
            .foregroundStyle(pageSecondaryTextColor)
        }
        .padding(.horizontal, 6)
    }

    private func impactOverviewCard(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 6 : 8) {
            Text("Estimated CO2e Saved")
                .font(AppType.body(isCompact ? 14 : 15))
                .foregroundStyle(pageSecondaryTextColor)

            Text("4.8 kg")
                .font(AppType.display(isCompact ? 42 : 48))
                .foregroundStyle(pagePrimaryTextColor)

            Text("from 28 recycled items this month")
                .font(AppType.body(isCompact ? 13 : 14))
                .foregroundStyle(pageSecondaryTextColor.opacity(0.92))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 20 : 24)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    colorScheme == .light
                    ? Color.white.opacity(0.62)
                    : Color.white.opacity(0.10)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    colorScheme == .light
                    ? Color.white.opacity(0.72)
                    : Color.white.opacity(0.18),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .light ? 0.08 : 0.24),
            radius: 10,
            x: 0,
            y: 6
        )
    }

    private func impactStatsRow(isCompact: Bool) -> some View {
        HStack(spacing: isCompact ? 10 : 12) {
            impactStatChip(
                title: "Streak",
                value: "12 Days",
                icon: "calendar.badge.clock",
                isCompact: isCompact
            )
            impactStatChip(
                title: "Landfill Avoided",
                value: "9.4 lb",
                icon: "leaf.fill",
                isCompact: isCompact
            )
        }
    }

    private func impactStatChip(title: String, value: String, icon: String, isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(AppTheme.mint)

                Text(title)
                    .font(AppType.body(isCompact ? 12 : 13))
                    .foregroundStyle(pageSecondaryTextColor)
            }

            Text(value)
                .font(AppType.title(isCompact ? 17 : 18))
                .foregroundStyle(pagePrimaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, isCompact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    colorScheme == .light
                    ? Color.white.opacity(0.54)
                    : Color.white.opacity(0.08)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    colorScheme == .light
                    ? Color.white.opacity(0.62)
                    : Color.white.opacity(0.14),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Brand + Tagline

    @ViewBuilder
    private func taglineText(titleSize: CGFloat, isCompact: Bool) -> some View {
        let visibleCount = min(typedCharacters, tagline.count)
        let typedText = String(tagline.prefix(visibleCount))
        return Text("\(typedText)\(showCursor ? "|" : " ")")
            .foregroundStyle(introTaglineColor)
            .font(AppType.display(titleSize))
            .lineLimit(1)
            .minimumScaleFactor(isCompact ? 0.7 : 0.8)
            .multilineTextAlignment(.center)
    }

    private func reviveEarthBrand(
        isCompact: Bool,
        horizontalOffset: CGFloat,
        boxed: Bool,
        emphasize: Bool
    ) -> some View {
        let logoWidth: CGFloat = emphasize ? (isCompact ? 138 : 170) : (isCompact ? 84 : 96)
        let logoHeight: CGFloat = emphasize ? (isCompact ? 42 : 52) : (isCompact ? 26 : 30)
        let earthSize: CGFloat = emphasize ? (isCompact ? 44 : 54) : (isCompact ? 24 : 26)
        let contentSpacing: CGFloat = -5
        let earthVerticalOffset: CGFloat = emphasize ? 4.5 : 3.5

        return HStack(spacing: contentSpacing) {
            Image("LandscapeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: logoWidth, height: logoHeight)

            Text("Earth")
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.22, green: 0.75, blue: 0.86),
                            Color(red: 0.92, green: 0.80, blue: 0.27)
                        ],
                        startPoint: .bottomLeading,
                        endPoint: .trailing
                    )
                )
                .font(AppType.title(earthSize))
                .offset(y: earthVerticalOffset)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .offset(x: horizontalOffset)
        .padding(.vertical, boxed ? (isCompact ? 12 : 14) : 0)
        .modifier(ReViveEarthBrandShell(boxed: boxed))
    }

    private func startTypewriterAnimation() {
        typingTask?.cancel()
        typedCharacters = 0
        typingTask = Task { @MainActor in
            for count in 0...tagline.count {
                guard !Task.isCancelled else { break }
                typedCharacters = count
                try? await Task.sleep(for: .milliseconds(count == 0 ? 250 : 70))
            }
            typingTask = nil
        }
    }

    private func startCursorBlink() {
        cursorTask?.cancel()
        showCursor = true
        cursorTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { break }
                showCursor.toggle()
            }
            cursorTask = nil
        }
    }

    // MARK: - Loop layout

    private func recycleLoopSteps(isCompact: Bool) -> some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let cx = W / 2
            let cy = H / 2

            let cardWidth:  CGFloat = min(isCompact ? 148 : 168, W * 0.44)
            let cardHeight: CGFloat = isCompact ? 76 : 88

            // Circle radius — just large enough that cards at 120° apart don't overlap
            let radius: CGFloat = min(W, H) * (isCompact ? 0.33 : 0.35)
            let strokeW: CGFloat = isCompact ? 11 : 13

            // Card centres at 120° intervals: top-left, top-right, bottom
            let a1 = CGFloat(-150) * .pi / 180   // card 1  (top-left)
            let a2 = CGFloat( -30) * .pi / 180   // card 2  (top-right)
            let a3 = CGFloat(  90) * .pi / 180   // card 3  (bottom)

            let p1 = CGPoint(x: cx + cos(a1) * radius, y: cy + sin(a1) * radius)
            let p2 = CGPoint(x: cx + cos(a2) * radius, y: cy + sin(a2) * radius)
            let p3 = CGPoint(x: cx + cos(a3) * radius, y: cy + sin(a3) * radius)

            // Arrow heads: place them at arc midpoints for 1→2→3→1 flow.
            let arrowRadius = radius - strokeW * 0.25
            let arrow1 = CGPoint(x: cx + cos(-90 * .pi / 180) * arrowRadius + 47,
                                 y: cy + sin(-90 * .pi / 180) * arrowRadius + 5)
            let arrow2 = CGPoint(x: cx + cos(30 * .pi / 180) * arrowRadius - 12,
                                 y: cy + sin(30 * .pi / 180) * arrowRadius + 25)
            let arrow3 = CGPoint(x: cx + cos(150 * .pi / 180) * arrowRadius - 20,
                                 y: cy + sin(150 * .pi / 180) * arrowRadius - 60)
            let cut1 = offsetPoint(arrow1, angleDegrees: 35, distance: strokeW * 1.2)
            let cut2 = offsetPoint(arrow2, angleDegrees: 140, distance: strokeW * 1.2)
            let cut3 = offsetPoint(arrow3, angleDegrees: 275, distance: strokeW * 1.2)

            ZStack {
                // ── Circle (stroke only) ──
                Circle()
                    .stroke(Color(red: 0.24, green: 0.75, blue: 0.42), lineWidth: strokeW)
                    .frame(width: radius * 2, height: radius * 2)
                    .position(x: cx, y: cy)
                    .shadow(color: Color(red: 0.20, green: 0.62, blue: 0.34).opacity(0.25),
                            radius: 4, x: 0, y: 2)
                    .overlay {
                        ZStack {
                            Circle().frame(width: strokeW * 3.0, height: strokeW * 3.0).position(cut1)
                            Circle().frame(width: strokeW * 3.8, height: strokeW * 3.8).position(cut2)
                            Circle().frame(width: strokeW * 3.0, height: strokeW * 3.0).position(cut3)
                        }
                        .foregroundStyle(.black)
                        .blendMode(.destinationOut)
                    }
                    .compositingGroup()

                // ── Cards (on top of circle) ──
                stepCard(text: "1) Scan item and analyze.", icon: "viewfinder.circle.fill",
                         width: cardWidth, height: cardHeight, isCompact: isCompact, iconOnRight: true)
                    .position(p1)

                stepCard(text: "2) Recycle", icon: "gift.fill",
                         width: cardWidth, height: cardHeight, isCompact: isCompact, iconOnRight: true)
                    .position(p2)

                stepCard(text: "3) Mark as recycled.", icon: "checkmark.seal.fill",
                         width: cardWidth, height: cardHeight, isCompact: isCompact, iconOnRight: false)
                    .position(p3)

                // ── Arrow heads on the circle ──
                // Drawn above cards so they don't appear clipped at overlaps.
                // Arc 1→2 midpoint: angle -90° (top of circle), travelling rightward
                arrowHead(strokeW: strokeW)
                    .rotationEffect(.degrees(35))   // pointing right
                    .position(arrow1)
                    .zIndex(2)

                arrowHead(strokeW: strokeW)
                    .rotationEffect(.degrees(140))
                    .position(arrow2)
                    .zIndex(2)

                arrowHead(strokeW: strokeW)
                    .rotationEffect(.degrees(275))
                    .position(arrow3)
                    .zIndex(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A simple filled arrowhead chevron pointing rightward by default.
    private func arrowHead(strokeW: CGFloat) -> some View {
        let size = strokeW * 3.8
        return Image(systemName: "arrowtriangle.right.fill")
            .font(.system(size: size))
            .foregroundStyle(Color(red: 0.24, green: 0.75, blue: 0.42))
    }

    private func offsetPoint(_ point: CGPoint, angleDegrees: CGFloat, distance: CGFloat) -> CGPoint {
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: point.x + cos(radians) * distance,
            y: point.y + sin(radians) * distance
        )
    }

    // MARK: - Cards

    @ViewBuilder
    private func stepCard(
        text: String, icon: String,
        width: CGFloat, height: CGFloat,
        isCompact: Bool, iconOnRight: Bool
    ) -> some View {
        let textBlock = Text(text)
            .font(AppType.title(isCompact ? 12 : 14))
            .foregroundStyle(Color(red: 0.04, green: 0.10, blue: 0.13))
            .lineLimit(2)
            .minimumScaleFactor(0.82)

        let iconBlock = Image(systemName: icon)
            .font(.system(size: isCompact ? 26 : 30, weight: .semibold))
            .foregroundStyle(Color(red: 0.18, green: 0.60, blue: 0.34))
            .frame(width: isCompact ? 32 : 38)

        Group {
            if iconOnRight {
                HStack(spacing: 10) { textBlock; Spacer(minLength: 0); iconBlock }
            } else {
                VStack(spacing: 8) { textBlock; iconBlock }
            }
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color(red: 0.24, green: 0.63, blue: 0.38), lineWidth: 2.5))
        .shadow(color: Color.black.opacity(0.14), radius: 7, x: 0, y: 4)
    }

}

private struct ReViveEarthBrandShell: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let boxed: Bool

    func body(content: Content) -> some View {
        if boxed {
            content
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .light
                                ? [
                                    Color(red: 0.10, green: 0.46, blue: 0.49),
                                    Color(red: 0.10, green: 0.58, blue: 0.44)
                                ]
                                : [
                                    Color(red: 0.02, green: 0.24, blue: 0.29),
                                    Color(red: 0.03, green: 0.38, blue: 0.28)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(colorScheme == .light ? 0.34 : 0.24), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(colorScheme == .light ? 0.17 : 0.28), radius: 10, x: 0, y: 6)
        } else {
            content
                .shadow(color: Color.black.opacity(colorScheme == .light ? 0.15 : 0.25), radius: 6, x: 0, y: 4)
        }
    }
}

#Preview {
    Group {
        OnboardingView(onContinue: {})
            .preferredColorScheme(.dark)
        OnboardingView(onContinue: {})
            .preferredColorScheme(.light)
    }
}
