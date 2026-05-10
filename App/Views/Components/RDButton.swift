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
    var showsActionIcon: Bool = true
    var reservesActionIconSpace: Bool = true
    var titleFontSize: CGFloat = 17
    var contentOffsetX: CGFloat = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack {
                    Spacer()
                    if let actionIcon {
                        capsuleIcon(actionIcon)
                    }
                }

                HStack(spacing: 8) {
                    if let icon {
                        inlineIcon(icon)
                    }
                    Text(title)
                        .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                        .tracking(-0.2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    if inlineTrailingIconStyle, let trailingIcon {
                        inlineIcon(trailingIcon)
                    }
                }
                .padding(.horizontal, shouldReserveActionIconSpace ? max(56, height) : 0)
                .offset(x: contentOffsetX)
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .padding(.horizontal, capsuleIconStyle ? 10 : 18)
            .background(background)
            .foregroundStyle(textColor)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: shadow, radius: 18, x: 0, y: 6)
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    @ViewBuilder
    private func inlineIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
    }

    @ViewBuilder
    private func capsuleIcon(_ name: String) -> some View {
        if capsuleIconStyle {
            Image(systemName: name)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.rdOnyx)
                .frame(width: max(38, height - 14), height: max(38, height - 14))
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: max(12, (height - 14) * 0.28)))
        } else {
            EmptyView()
        }
    }

    private var background: Color {
        if let backgroundOverride { return backgroundOverride }
        switch style {
        case .primary:     return .rdOnyx
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
            RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.rdLine, lineWidth: 1)
        }
    }

    private var shadow: Color {
        if let shadowOverride { return shadowOverride }
        return style == .detect ? Color.rdGreen.opacity(0.28) : .clear
    }

    private var capsuleIconStyle: Bool {
        switch style {
        case .primary, .detect, .destructive:
            return actionIcon != nil
        case .secondary, .ghost:
            return false
        }
    }

    private var shouldReserveActionIconSpace: Bool {
        capsuleIconStyle && reservesActionIconSpace
    }

    private var inlineTrailingIconStyle: Bool {
        switch style {
        case .secondary, .ghost:
            return trailingIcon != nil
        case .primary, .detect, .destructive:
            return false
        }
    }

    private var actionIcon: String? {
        guard showsActionIcon else { return nil }
        switch style {
        case .primary, .detect, .destructive:
            return trailingIcon ?? defaultActionIcon
        case .secondary, .ghost:
            return nil
        }
    }

    private var defaultActionIcon: String {
        switch style {
        case .primary, .detect:
            return "paperplane.fill"
        case .destructive:
            return "trash"
        case .secondary, .ghost:
            return ""
        }
    }

    private var cornerRadius: CGFloat {
        capsuleIconStyle ? min(22, height * 0.32) : 14
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
