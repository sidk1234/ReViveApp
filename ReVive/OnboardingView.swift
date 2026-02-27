import SwiftUI

struct OnboardingView: View {
    private let tagline = "One Scan At A Time."

    let onContinue: () -> Void
    @State private var typedCharacters = 0
    @State private var showCursor = true
    @State private var typingTask: Task<Void, Never>?
    @State private var cursorTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let compact = proxy.size.height < 760
            let titleSize: CGFloat = compact ? 24 : 29
            let stepHeight = compact ? proxy.size.height * 0.43 : proxy.size.height * 0.46

            ZStack {
                AppTheme.heroGradient
                    .ignoresSafeArea()

                VStack(spacing: compact ? 14 : 26) {
                    reviveEarthBrand(
                        isCompact: compact,
                        horizontalOffset: 0,
                        boxed: false,
                        emphasize: true
                    )
                        .padding(.top, safeTop + (compact ? 8 : 14))
                        .layoutPriority(2)

                    taglineText(titleSize: titleSize, isCompact: compact)
                        .padding(.horizontal, 8)
                        .frame(minHeight: compact ? 38 : 44)

                    recycleLoopSteps(isCompact: compact)
                        .frame(maxWidth: min(360, proxy.size.width - 32))
                        .frame(height: stepHeight)
                        .padding(.top, compact ? 10 : 14)

                    Spacer(minLength: compact ? 4 : 8)

                    Button(action: onContinue) {
                        reviveEarthBrand(
                            isCompact: compact,
                            horizontalOffset: -10,
                            boxed: true,
                            emphasize: false
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, safeBottom + (compact ? 4 : 8))
                }
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            startTypewriterAnimation()
            startCursorBlink()
        }
        .onDisappear {
            typingTask?.cancel()
            cursorTask?.cancel()
            typingTask = nil
            cursorTask = nil
        }
    }

    // MARK: - Brand + Tagline

    @ViewBuilder
    private func taglineText(titleSize: CGFloat, isCompact: Bool) -> some View {
        let visibleCount = min(typedCharacters, tagline.count)
        let typedText = String(tagline.prefix(visibleCount))
        (Text(typedText).foregroundStyle(.white)
            + Text(showCursor ? "|" : " ").foregroundStyle(.white.opacity(0.95))
        )
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
    let boxed: Bool

    func body(content: Content) -> some View {
        if boxed {
            content
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
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
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.28), radius: 10, x: 0, y: 6)
        } else {
            content
                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
        }
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
