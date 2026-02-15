import SwiftUI

struct OnboardingView: View {
    private enum StepsMode: String {
        case loop = "Loop"
        case linear = "Flow"
    }

    let onContinue: () -> Void
    @State private var stepsMode: StepsMode = .loop

    var body: some View {
        GeometryReader { proxy in
            let safeTop = proxy.safeAreaInsets.top
            let safeBottom = proxy.safeAreaInsets.bottom
            let compact = proxy.size.height < 760
            let logoWidth = compact ? min(180, proxy.size.width * 0.50) : min(220, proxy.size.width * 0.58)
            let logoHeight: CGFloat = compact ? 56 : 68
            let titleSize: CGFloat = compact ? 29 : 34
            let stepHeight = compact ? proxy.size.height * 0.43 : proxy.size.height * 0.46

            ZStack {
                AppTheme.heroGradient
                    .ignoresSafeArea()

                VStack(spacing: compact ? 14 : 26) {
                    Image("LandscapeLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoWidth, height: logoHeight)
                        .padding(.top, safeTop + (compact ? 8 : 14))
                        .layoutPriority(2)

                    Text("How It Works")
                        .font(AppType.display(titleSize))
                        .foregroundStyle(.white)

                    stepsModeToggle
                        .padding(.top, compact ? -8 : -10)

                    recycleSteps(isCompact: compact)
                        .frame(maxWidth: min(360, proxy.size.width - 32))
                        .frame(height: stepHeight)
                        .padding(.top, compact ? 10 : 14)

                    Spacer(minLength: compact ? 4 : 8)

                    Button(action: onContinue) {
                        Text("Get Started")
                            .font(AppType.title(compact ? 16 : 17))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, compact ? 12 : 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(AppTheme.mint)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, safeBottom + (compact ? 4 : 8))
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func recycleSteps(isCompact: Bool) -> some View {
        Group {
            switch stepsMode {
            case .loop:
                recycleLoopSteps(isCompact: isCompact)
            case .linear:
                recycleLinearSteps(isCompact: isCompact)
            }
        }
    }

    private func recycleLoopSteps(isCompact: Bool) -> some View {
        GeometryReader { geo in
            let cardWidth = min(isCompact ? 152 : 178, geo.size.width * 0.46)
            let cardHeight: CGFloat = isCompact ? 78 : 90
            let topY = geo.size.height * (isCompact ? 0.25 : 0.24)
            let bottomY = geo.size.height * (isCompact ? 0.77 : 0.75)
            let topGapExtra: CGFloat = isCompact ? 22 : 28
            let baseGap = max(8, geo.size.width - (cardWidth * 2) - 20)
            let topGap = baseGap + topGapExtra
            let leftX = (geo.size.width - topGap) / 2 - cardWidth / 2
            let rightX = (geo.size.width + topGap) / 2 + cardWidth / 2
            let middleX = geo.size.width / 2
            let arrowWidth: CGFloat = isCompact ? 11 : 13
            let topArrowY = topY - cardHeight * (isCompact ? 0.52 : 0.54)

            ZStack {
                // 1 -> 2
                connectorArrow(
                    from: CGPoint(x: leftX - cardWidth * 0.10, y: topY + cardHeight * 0.50),
                    to: CGPoint(x: middleX - cardWidth * 0.50, y: bottomY - cardHeight * 0.12),
                    control: CGPoint(x: middleX - cardWidth * 0.90, y: geo.size.height * 0.52),
                    lineWidth: arrowWidth
                )
                .foregroundStyle(Color(red: 0.24, green: 0.75, blue: 0.42))

                // 2 -> 3
                connectorArrow(
                    from: CGPoint(x: middleX + cardWidth * 0.50, y: bottomY - cardHeight * 0.12),
                    to: CGPoint(x: rightX + cardWidth * 0.10, y: topY + cardHeight * 0.50),
                    control: CGPoint(x: middleX + cardWidth * 0.90, y: geo.size.height * 0.52),
                    lineWidth: arrowWidth
                )
                .foregroundStyle(Color(red: 0.24, green: 0.75, blue: 0.42))

                // 3 -> 1 (top return arrow)
                connectorArrow(
                    from: CGPoint(x: rightX, y: topArrowY),
                    to: CGPoint(x: leftX, y: topArrowY),
                    control: CGPoint(x: middleX, y: geo.size.height * (isCompact ? -0.12 : -0.14)),
                    lineWidth: arrowWidth
                )
                .foregroundStyle(Color(red: 0.20, green: 0.69, blue: 0.39))

                stepCard(
                    text: "1) Scan item and analyze.",
                    icon: "viewfinder.circle.fill",
                    width: cardWidth,
                    height: cardHeight,
                    isCompact: isCompact,
                    iconOnRight: true
                )
                .position(x: leftX, y: topY)

                stepCard(
                    text: "3) Mark as recycled.",
                    icon: "checkmark.seal.fill",
                    width: cardWidth,
                    height: cardHeight,
                    isCompact: isCompact,
                    iconOnRight: true
                )
                .position(x: rightX, y: topY)

                stepCard(
                    text: "2) Recycle",
                    icon: "gift.fill",
                    width: cardWidth,
                    height: cardHeight,
                    isCompact: isCompact,
                    iconOnRight: false
                )
                .position(x: middleX, y: bottomY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func recycleLinearSteps(isCompact: Bool) -> some View {
        GeometryReader { geo in
            let cardWidth = min(isCompact ? 220 : 260, geo.size.width * 0.86)
            let cardHeight = geo.size.height * (isCompact ? 0.24 : 0.22)
            let centerX = geo.size.width / 2
            let card1Y = geo.size.height * (isCompact ? 0.19 : 0.18)
            let card2Y = geo.size.height * (isCompact ? 0.50 : 0.50)
            let card3Y = geo.size.height * (isCompact ? 0.81 : 0.82)
            let arrow1Y = (card1Y + card2Y) / 2
            let arrow2Y = (card2Y + card3Y) / 2

            ZStack {
                linearStepCard(
                    text: "1) Scan item and analyze.",
                    icon: "viewfinder.circle.fill",
                    width: cardWidth,
                    height: cardHeight,
                    isCompact: isCompact
                )
                .position(x: centerX, y: card1Y)

                linearStepCard(
                    text: "2) Recycle",
                    icon: "gift.fill",
                    width: cardWidth,
                    height: cardHeight,
                    isCompact: isCompact
                )
                .position(x: centerX, y: card2Y)

                linearStepCard(
                    text: "3) Mark as recycled.",
                    icon: "checkmark.seal.fill",
                    width: cardWidth,
                    height: cardHeight,
                    isCompact: isCompact
                )
                .position(x: centerX, y: card3Y)

                Image(systemName: "arrow.down")
                    .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.24, green: 0.75, blue: 0.42))
                    .position(x: centerX, y: arrow1Y)

                Image(systemName: "arrow.down")
                    .font(.system(size: isCompact ? 18 : 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.24, green: 0.75, blue: 0.42))
                    .position(x: centerX, y: arrow2Y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var stepsModeToggle: some View {
        HStack(spacing: 6) {
            modeButton(.loop)
            modeButton(.linear)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.16))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
    }

    private func modeButton(_ mode: StepsMode) -> some View {
        let selected = stepsMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                stepsMode = mode
            }
        } label: {
            Text(mode.rawValue)
                .font(AppType.title(12))
                .foregroundStyle(selected ? Color.black : Color.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(selected ? AppTheme.mint : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func stepCard(
        text: String,
        icon: String,
        width: CGFloat,
        height: CGFloat,
        isCompact: Bool,
        iconOnRight: Bool
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
                HStack(spacing: 10) {
                    textBlock
                    Spacer(minLength: 0)
                    iconBlock
                }
            } else {
                VStack(spacing: 8) {
                    textBlock
                    iconBlock
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.24, green: 0.63, blue: 0.38), lineWidth: 2.5)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 7, x: 0, y: 4)
    }

    private func linearStepCard(
        text: String,
        icon: String,
        width: CGFloat,
        height: CGFloat,
        isCompact: Bool
    ) -> some View {
        VStack(spacing: isCompact ? 6 : 8) {
            Text(text)
                .font(AppType.title(isCompact ? 13 : 15))
                .foregroundStyle(Color(red: 0.04, green: 0.10, blue: 0.13))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)

            Image(systemName: icon)
                .font(.system(size: isCompact ? 22 : 24, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.60, blue: 0.34))
        }
        .padding(.horizontal, isCompact ? 8 : 10)
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.24, green: 0.63, blue: 0.38), lineWidth: 2.2)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 7, x: 0, y: 4)
    }

    private func connectorArrow(
        from start: CGPoint,
        to end: CGPoint,
        control: CGPoint,
        lineWidth: CGFloat
    ) -> some View {
        var p = Path()
        p.move(to: start)
        p.addQuadCurve(to: end, control: control)

        let tangent = CGVector(dx: end.x - control.x, dy: end.y - control.y)
        let mag = max(0.001, sqrt(tangent.dx * tangent.dx + tangent.dy * tangent.dy))
        let back = CGVector(dx: -tangent.dx / mag, dy: -tangent.dy / mag)
        let wingLen = lineWidth * 1.55
        let wingAngle = CGFloat.pi / 5

        let a = rotate(back, by: wingAngle)
        let b = rotate(back, by: -wingAngle)
        let pa = CGPoint(x: end.x + a.dx * wingLen, y: end.y + a.dy * wingLen)
        let pb = CGPoint(x: end.x + b.dx * wingLen, y: end.y + b.dy * wingLen)

        p.move(to: end)
        p.addLine(to: pa)
        p.move(to: end)
        p.addLine(to: pb)

        return p
            .stroke(style: .init(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            .shadow(color: Color(red: 0.20, green: 0.62, blue: 0.34).opacity(0.25), radius: 3, x: 0, y: 2)
    }

    private func rotate(_ v: CGVector, by a: CGFloat) -> CGVector {
        let c = cos(a)
        let s = sin(a)
        return CGVector(dx: v.dx * c - v.dy * s, dy: v.dx * s + v.dy * c)
    }
}

#Preview {
    OnboardingView(onContinue: {})
}
