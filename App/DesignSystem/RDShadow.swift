import SwiftUI

extension View {
    func rdCardShadow() -> some View {
        self
            .shadow(color: Color.rdBlack.opacity(0.105), radius: 4, x: 5, y: 6)
            .shadow(color: Color.rdSlate.opacity(0.045), radius: 7, x: 7, y: 8)
    }

    func rdCardShadow(
        colorScheme: ColorScheme,
        accent: Color = Color.rdBlack,
        radius: CGFloat = 4,
        x: CGFloat = 5,
        y: CGFloat = 6
    ) -> some View {
        self
            .shadow(
                color: Color.rdBlack.opacity(colorScheme == .dark ? 0.30 : 0.105),
                radius: radius,
                x: x,
                y: y
            )
            .shadow(
                color: Color.rdSlate.opacity(colorScheme == .dark ? 0.12 : 0.045),
                radius: radius + 3,
                x: x + 2,
                y: y + 2
            )
            .shadow(
                color: accent.opacity(colorScheme == .dark ? 0.07 : 0.025),
                radius: 6,
                x: 6,
                y: 7
            )
    }

    func rdRowShadow() -> some View {
        self
            .shadow(color: Color.rdBlack.opacity(0.10), radius: 4, x: 5, y: 6)
            .shadow(color: Color.rdSlate.opacity(0.045), radius: 7, x: 7, y: 8)
    }

    func rdModalShadow() -> some View {
        self.shadow(color: Color(hex: "#0F172A").opacity(0.16), radius: 32, x: 0, y: 12)
    }

    func rdSheetShadow() -> some View {
        self.shadow(color: Color(hex: "#0B0D0E").opacity(0.18), radius: 40, x: 0, y: -10)
    }
}
