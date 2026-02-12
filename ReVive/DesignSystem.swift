//
//  DesignSystem.swift
//  Recyclability
//

import SwiftUI

enum AppTheme {
    static let night = Color(red: 0.04, green: 0.07, blue: 0.10)
    static let deepTeal = Color(red: 0.03, green: 0.18, blue: 0.18)
    static let emerald = Color(red: 0.14, green: 0.82, blue: 0.52)
    static let mint = Color(red: 0.48, green: 0.95, blue: 0.78)
    static let sky = Color(red: 0.44, green: 0.68, blue: 1.00)
    static let violet = Color(red: 0.62, green: 0.48, blue: 1.00)
    static let glow = Color.white.opacity(0.45)

    static let heroGradient = LinearGradient(
        colors: [deepTeal, night],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func backgroundGradient(_ scheme: ColorScheme) -> LinearGradient {
        if scheme == .light {
            return LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.98, blue: 1.00),
                    Color(red: 0.85, green: 0.93, blue: 0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return heroGradient
    }

    static let accentGradient = LinearGradient(
        colors: [mint, sky, violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let cardGradient = LinearGradient(
        colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

enum AppType {
    static func display(_ size: CGFloat) -> Font {
        Font.custom("Avenir Next Heavy", size: size)
    }

    static func title(_ size: CGFloat) -> Font {
        Font.custom("Avenir Next Demi Bold", size: size)
    }

    static func body(_ size: CGFloat) -> Font {
        Font.custom("Avenir Next Medium", size: size)
    }

    static func mono(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced)
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.cardGradient)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    .allowsHitTesting(false)
            )
            .liquidGlassBackground(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                interactive: interactive
            )
    }
}
