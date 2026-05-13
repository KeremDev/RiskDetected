import SwiftUI

struct RDAvatar: View {
    var initials: String = "EY"
    var size: CGFloat = 36
    var tier: SubscriptionTier = .free
    var pro: Bool = false

    private var effectiveTier: SubscriptionTier {
        pro ? .pro : tier
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.rdGraphite, Color.rdCharcoal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(Circle())

            Text(initials)
                .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .tracking(-0.3)
        }
        .frame(width: size, height: size)
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
                        Circle().stroke(.white, lineWidth: 2)
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
