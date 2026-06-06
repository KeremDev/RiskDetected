import SwiftUI

struct ProfessionalProgressCelebrationSheet: View {
    let badge: ProfessionalProgressBadge
    let onClose: () -> Void

    @State private var animateConfetti = false

    var body: some View {
        ZStack(alignment: .top) {
            ProfessionalProgressConfettiView(isActive: animateConfetti)
                .frame(height: 168)
                .padding(.horizontal, RDSpacing.lg)
                .padding(.top, RDSpacing.sm)
                .allowsHitTesting(false)
                .zIndex(2)

            VStack(spacing: RDSpacing.lg) {
                Image(systemName: badge.iconName)
                    .font(.system(size: RDFontScale.size(34), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreenDark)
                    .frame(width: 72, height: 72)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: RDRadius.xl))
                    .scaleEffect(animateConfetti ? 1.0 : 0.94)
                    .animation(.spring(response: 0.42, dampingFraction: 0.72), value: animateConfetti)

                VStack(spacing: 9) {
                    Text("Tebrikler")
                        .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdGreenDark)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.rdGreenSoft)
                        .clipShape(Capsule())

                    Text(badge.title)
                        .font(.system(size: RDFontScale.size(22), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .multilineTextAlignment(.center)

                    Text(badge.subtitle)
                        .font(.system(size: RDFontScale.size(14), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                RDButton(
                    title: "Tamam",
                    style: .detect,
                    icon: "checkmark",
                    height: 52,
                    showsActionIcon: false,
                    reservesActionIconSpace: false
                ) {
                    onClose()
                }
                .padding(.top, RDSpacing.sm)
            }
            .padding(.horizontal, RDSpacing.xl)
            .padding(.top, 72)
            .padding(.bottom, RDSpacing.xl)
            .zIndex(1)

            HStack {
                Spacer()
                RDModalCloseButton(action: onClose)
                    .padding(.top, RDSpacing.lg)
                    .padding(.trailing, RDSpacing.xl)
            }
            .zIndex(3)
        }
        .frame(maxWidth: .infinity)
        .background(Color.rdPaper)
        .accessibilityIdentifier("professionalProgress.celebration.sheet")
        .onAppear {
            animateConfetti = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 1.35)) {
                    animateConfetti = true
                }
            }
        }
    }
}

private struct ProfessionalProgressConfettiView: View {
    let isActive: Bool

    private let pieces: [ConfettiPiece] = [
        .init(x: 0.10, startY: -20, endY: 76, delay: 0.00, size: CGSize(width: 6, height: 14), color: .rdGreen, rotation: 92),
        .init(x: 0.20, startY: -36, endY: 108, delay: 0.05, size: CGSize(width: 8, height: 8), color: .rdPlanPlus, rotation: -140),
        .init(x: 0.32, startY: -26, endY: 70, delay: 0.08, size: CGSize(width: 5, height: 13), color: .rdMedium, rotation: 120),
        .init(x: 0.44, startY: -44, endY: 118, delay: 0.02, size: CGSize(width: 7, height: 12), color: .rdGreenDark, rotation: -98),
        .init(x: 0.57, startY: -24, endY: 86, delay: 0.11, size: CGSize(width: 7, height: 7), color: .rdLow, rotation: 170),
        .init(x: 0.68, startY: -38, endY: 104, delay: 0.06, size: CGSize(width: 5, height: 14), color: .rdHigh, rotation: -126),
        .init(x: 0.79, startY: -18, endY: 74, delay: 0.13, size: CGSize(width: 9, height: 9), color: .rdPlanPlus, rotation: 104),
        .init(x: 0.90, startY: -34, endY: 112, delay: 0.04, size: CGSize(width: 6, height: 13), color: .rdGreen, rotation: -152)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color.opacity(0.92))
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotationEffect(.degrees(isActive ? piece.rotation : 0))
                    .scaleEffect(isActive ? 1.0 : 0.72)
                    .position(
                        x: proxy.size.width * piece.x,
                        y: isActive ? piece.endY : piece.startY
                    )
                    .opacity(isActive ? 0.92 : 0)
                    .animation(
                        .spring(response: 0.9, dampingFraction: 0.78)
                            .delay(piece.delay),
                        value: isActive
                    )
            }
        }
        .clipped()
    }
}

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let delay: Double
    let size: CGSize
    let color: Color
    let rotation: Double
}

#Preview {
    ProfessionalProgressCelebrationSheet(
        badge: ProfessionalProgressBadge(
            id: UUID(),
            badgeKey: "first_report",
            badgeType: "report",
            title: "İlk Adım",
            subtitle: "İlk raporunu oluşturdun. Mesleki takip izin başladı.",
            iconName: "rosette",
            unlockedAt: nil,
            seenAt: nil
        )
    ) {}
    .padding()
    .background(Color.rdPaper)
}
