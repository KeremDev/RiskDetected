import SwiftUI

struct RDAvatar: View {
    @Environment(\.colorScheme) private var colorScheme

    var initials: String = "EY"
    var size: CGFloat = 36
    var tier: SubscriptionTier = .free
    var pro: Bool = false

    private var effectiveTier: SubscriptionTier {
        pro ? .pro : tier
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [Color(hex: "#17201A"), Color(hex: "#0F1512")]
        }
        return [Color(hex: "#DDE5E0"), Color(hex: "#C9D4CD")]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(Circle())

            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(colorScheme == .dark ? Color.rdCharcoal : .white)
                .tracking(0)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.55), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if effectiveTier.isPaid {
                Circle()
                    .fill(effectiveTier.accentColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .overlay {
                        Image(systemName: effectiveTier.badgeIcon)
                            .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .overlay(
                        Circle().stroke(Color.rdPaper, lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        RDAvatar(initials: "EY", size: 36)
        RDAvatar(initials: "EY", size: 48, tier: .plus)
        RDAvatar(initials: "KK", size: 64, pro: true)
    }
    .padding()
    .background(Color.rdPaper)
}
