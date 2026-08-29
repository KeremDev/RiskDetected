import SwiftUI

struct RDTierBadge: View {
    let tier: SubscriptionTier
    var small: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: tier.badgeIcon)
                .font(RDTypography.font(size: small ? 9 : 11, weight: .bold, design: .rounded))
            Text(tier.badgeLabel)
                .font(RDTypography.font(size: small ? 9 : 10, weight: .heavy, design: .rounded))
                .tracking(0.6)
        }
        .padding(.horizontal, small ? 6 : 8)
        .frame(height: small ? 18 : 22)
        .background(tier.accentColor)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .shadow(color: small ? .clear : tier.accentColor.opacity(0.28), radius: 8, x: 0, y: 2)
    }
}

struct RDProBadge: View {
    var small: Bool = false

    var body: some View {
        RDTierBadge(tier: .pro, small: small)
    }
}

#Preview {
    VStack(spacing: 12) {
        RDTierBadge(tier: .plus)
        RDProBadge()
        RDTierBadge(tier: .plus, small: true)
        RDProBadge(small: true)
    }
    .padding()
    .background(Color.rdPaper)
}
