//
//  LiquidGlass.swift
//  Recyclability
//

import SwiftUI

@available(iOS 26.0, *)
private func makeLiquidGlassEffect(tint: Color?, interactive: Bool) -> Glass {
    var effect: Glass = .regular
    if let tint { effect = effect.tint(tint) }
    if interactive { effect = effect.interactive() }
    return effect
}

private struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(makeLiquidGlassEffect(tint: tint, interactive: interactive), in: shape)
        } else {
            content
        }
    }
}

extension View {
    func liquidGlassBackground<S: Shape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassModifier(shape: shape, interactive: interactive, tint: tint))
    }

    @ViewBuilder
    func liquidGlassButton<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = true
    ) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                makeLiquidGlassEffect(tint: tint, interactive: interactive),
                in: shape
            )
            .contentShape(shape)
        } else {
            self
                .contentShape(shape)
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(Color.primary.opacity(0.2), lineWidth: 1))
        }
    }
}
