import SwiftUI

struct RDCard<Content: View>: View {
    var padding: CGFloat = RDSpacing.md
    var cornerRadius: CGFloat = RDRadius.lg
    var background: Color = .rdWhite
    var borderColor: Color = .rdLine
    var showsShadow: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        if showsShadow {
            cardBody
                .rdCardShadow(colorScheme: colorScheme)
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        content()
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

struct RDPlaceholderPhoto: View {
    var label: String? = nil
    var cornerRadius: CGFloat = RDRadius.md

    var body: some View {
        ZStack {
            stripes
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.rdSlate)
                    .tracking(1.6)
                    .textCase(.uppercase)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var stripes: some View {
        Canvas { ctx, size in
            let stripe: CGFloat = 8
            let total = size.width + size.height
            var x: CGFloat = -size.height
            while x < total {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x + stripe, y: 0))
                    p.addLine(to: CGPoint(x: x + stripe + size.height, y: size.height))
                    p.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    p.closeSubpath()
                }
                let fill: Color = (Int(x / stripe) % 2 == 0)
                    ? Color(hex: "#E6EBE7")
                    : Color(hex: "#EEF2EE")
                ctx.fill(path, with: .color(fill))
                x += stripe
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        RDCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Card title").font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("Body text").foregroundStyle(Color.rdSlate)
            }
        }
        RDPlaceholderPhoto(label: "Saha")
            .frame(height: 120)
    }
    .padding()
    .background(Color.rdPaper)
}
