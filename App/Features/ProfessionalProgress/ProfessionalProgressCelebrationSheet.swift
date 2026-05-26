import SwiftUI

struct ProfessionalProgressCelebrationSheet: View {
    let badge: ProfessionalProgressBadge
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: RDSpacing.lg) {
            Capsule()
                .fill(Color.rdLine)
                .frame(width: 46, height: 5)
                .padding(.top, RDSpacing.sm)

            Image(systemName: badge.iconName)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 72, height: 72)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.xl))
                .scaleEffect(1.0)

            VStack(spacing: 8) {
                Text(badge.title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .multilineTextAlignment(.center)
                Text(badge.subtitle)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            RDButton(
                title: "Tamam",
                style: .detect,
                icon: "checkmark",
                height: 52
            ) {
                onClose()
            }
            .padding(.top, RDSpacing.sm)
        }
        .padding(.horizontal, RDSpacing.xl)
        .padding(.bottom, RDSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.rdPaper)
        .accessibilityIdentifier("professionalProgress.celebration.sheet")
    }
}
