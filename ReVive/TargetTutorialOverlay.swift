//
//  TargetTutorialOverlay.swift
//  Recyclability
//

import SwiftUI

struct TargetTutorialOverlay: View {
    enum HighlightStyle {
        case circle(padding: CGFloat = 14)
        case roundedRect(cornerRadius: CGFloat = 16, padding: CGFloat = 8)
        case capsule(padding: CGFloat = 2)

        var padding: CGFloat {
            switch self {
            case .circle(let padding):
                return padding
            case .roundedRect(_, let padding):
                return padding
            case .capsule(let padding):
                return padding
            }
        }

        var minimumSize: CGFloat {
            switch self {
            case .circle:
                return 58
            case .roundedRect, .capsule:
                return 1
            }
        }
    }

    let targetRect: CGRect
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var onDone: (() -> Void)? = nil
    var highlightStyle: HighlightStyle = .circle()
    var showDirectionalArrow: Bool = true
    var showPressIndicator: Bool = false
    var onTargetTap: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let placeCardAbove = targetRect.midY > proxy.size.height * 0.58
            let highlightPadding = highlightStyle.padding
            let highlightWidth = max(highlightStyle.minimumSize, targetRect.width + highlightPadding)
            let highlightHeight = max(highlightStyle.minimumSize, targetRect.height + highlightPadding)
            let arrowSymbol = placeCardAbove ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill"
            let arrowY = placeCardAbove ? targetRect.minY - 24 : targetRect.maxY + 24
            let pressIndicatorY = targetRect.minY > 40 ? targetRect.minY - 18 : targetRect.maxY + 18
            let cardY = placeCardAbove
                ? max(110, targetRect.minY - 150)
                : min(proxy.size.height - 130, targetRect.maxY + 150)

            ZStack {
                Color.black.opacity(0.62)
                    .ignoresSafeArea()

                tutorialHighlight(width: highlightWidth, height: highlightHeight)
                    .position(x: targetRect.midX, y: targetRect.midY)
                    .shadow(color: AppTheme.mint.opacity(0.62), radius: 14, x: 0, y: 0)
                    .allowsHitTesting(false)

                if let onTargetTap {
                    tutorialTapTarget(width: highlightWidth, height: highlightHeight)
                        .onTapGesture {
                            onTargetTap()
                        }
                    .position(x: targetRect.midX, y: targetRect.midY)
                }

                if showDirectionalArrow {
                    Image(systemName: arrowSymbol)
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(AppTheme.mint)
                        .position(x: targetRect.midX, y: arrowY)
                        .allowsHitTesting(false)
                }

                if showPressIndicator {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(10)
                        .background(Circle().fill(AppTheme.mint))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: AppTheme.mint.opacity(0.5), radius: 10, x: 0, y: 5)
                        .position(x: targetRect.midX, y: pressIndicatorY)
                        .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Beginner Tips")
                        .font(AppType.title(18))
                        .foregroundStyle(AppTheme.mint)

                    Text(title)
                        .font(AppType.display(30))
                        .foregroundStyle(.white)

                    Text(message)
                        .font(AppType.body(17))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)

                    if let buttonTitle, let onDone {
                        Button(buttonTitle) {
                            onDone()
                        }
                        .font(AppType.title(15))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppTheme.mint))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(width: min(360, proxy.size.width - 28), alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .position(x: proxy.size.width / 2, y: cardY)
            }
        }
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func tutorialHighlight(width: CGFloat, height: CGFloat) -> some View {
        switch highlightStyle {
        case .circle:
            Circle()
                .stroke(AppTheme.mint, lineWidth: 4)
                .frame(width: width, height: height)
        case .roundedRect(let cornerRadius, _):
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(AppTheme.mint, lineWidth: 4)
                .frame(width: width, height: height)
        case .capsule:
            Capsule()
                .stroke(AppTheme.mint, lineWidth: 4)
                .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private func tutorialTapTarget(width: CGFloat, height: CGFloat) -> some View {
        switch highlightStyle {
        case .circle:
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: width, height: height)
        case .roundedRect(let cornerRadius, _):
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.001))
                .frame(width: width, height: height)
        case .capsule:
            Capsule()
                .fill(Color.white.opacity(0.001))
                .frame(width: width, height: height)
        }
    }
}
