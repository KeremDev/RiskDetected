import SwiftUI

enum RDButtonStyle {
    case primary       // black background
    case detect        // green background — analysis CTA
    case secondary     // fog background w/ border
    case ghost         // transparent
    case destructive   // critical red
}

struct RDButton: View {
    let title: String
    let style: RDButtonStyle
    var icon: String? = nil
    var trailingIcon: String? = nil
    var height: CGFloat = 52
    var backgroundOverride: Color? = nil
    var foregroundOverride: Color? = nil
    var shadowOverride: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 17, weight: .semibold)) }
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                if let trailingIcon { Image(systemName: trailingIcon).font(.system(size: 17, weight: .semibold)) }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, 18)
            .background(background)
            .foregroundStyle(textColor)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: shadow, radius: 18, x: 0, y: 6)
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var background: Color {
        if let backgroundOverride { return backgroundOverride }
        switch style {
        case .primary:     return .rdBlack
        case .detect:      return .rdGreen
        case .secondary:   return .rdFog
        case .ghost:       return .clear
        case .destructive: return .rdCritical
        }
    }

    private var textColor: Color {
        if let foregroundOverride { return foregroundOverride }
        switch style {
        case .primary, .detect, .destructive: return .white
        case .secondary, .ghost: return .rdBlack
        }
    }

    @ViewBuilder
    private var border: some View {
        if style == .secondary {
            RoundedRectangle(cornerRadius: 14).stroke(Color.rdLine, lineWidth: 1)
        }
    }

    private var shadow: Color {
        if let shadowOverride { return shadowOverride }
        return style == .detect ? Color.rdGreen.opacity(0.28) : .clear
    }
}

struct RDPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 12) {
        RDButton(title: "PDF Rapor", style: .primary, icon: "arrow.down.to.line") {}
        RDButton(title: "Taramayı Başlat", style: .detect, icon: "sparkles") {}
        RDButton(title: "Excel", style: .secondary, icon: "doc.fill") {}
        RDButton(title: "Sil", style: .destructive, icon: "trash") {}
    }
    .padding()
    .background(Color.rdPaper)
}
