import SwiftUI

extension View {
    func rdCardShadow() -> some View {
        self.shadow(color: Color(hex: "#0F172A").opacity(0.06), radius: 2, x: 0, y: 1)
    }

    func rdModalShadow() -> some View {
        self.shadow(color: Color(hex: "#0F172A").opacity(0.16), radius: 32, x: 0, y: 12)
    }

    func rdSheetShadow() -> some View {
        self.shadow(color: Color(hex: "#0B0D0E").opacity(0.18), radius: 40, x: 0, y: -10)
    }
}
