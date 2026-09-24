import SwiftUI

extension View {
    func rdCardShadow() -> some View {
        modifier(RDDepthShadowModifier())
    }

    func rdCardShadow(
        colorScheme: ColorScheme,
        accent: Color = Color.rdBlack,
        radius: CGFloat = 4,
        x: CGFloat = 5,
        y: CGFloat = 6
    ) -> some View {
        modifier(
            RDDepthShadowModifier(
                explicitColorScheme: colorScheme,
                accent: accent,
                radius: radius,
                x: x,
                y: y
            )
        )
    }

    func rdRowShadow() -> some View {
        modifier(RDDepthShadowModifier(radius: 4, x: 5, y: 6))
    }

    func rdModalShadow() -> some View {
        self.shadow(color: Color(hex: "#0F172A").opacity(0.16), radius: 32, x: 0, y: 12)
    }

    func rdSheetShadow() -> some View {
        self.shadow(color: Color(hex: "#0B0D0E").opacity(0.18), radius: 40, x: 0, y: -10)
    }
}

private struct RDDepthShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var environmentColorScheme

    var explicitColorScheme: ColorScheme?
    var accent: Color = Color.rdBlack
    var radius: CGFloat = 4
    var x: CGFloat = 5
    var y: CGFloat = 6

    func body(content: Content) -> some View {
        let resolvedScheme = explicitColorScheme ?? environmentColorScheme

        if resolvedScheme == .dark {
            content
        } else {
            content
                .shadow(color: Color.rdBlack.opacity(0.105), radius: radius, x: x, y: y)
                .shadow(color: Color.rdSlate.opacity(0.045), radius: radius + 3, x: x + 2, y: y + 2)
                .shadow(color: accent.opacity(0.025), radius: 6, x: 6, y: 7)
        }
    }
}
