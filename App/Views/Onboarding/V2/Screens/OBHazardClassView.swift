import SwiftUI

struct OBHazardClassView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void

    private let items: [(cls: OBHazardClass, icon: String, sub: String)] = [
        (.critical, "exclamationmark.triangle.fill", "Petrokimya, maden, inşaat"),
        (.high, "exclamationmark.circle.fill", "İmalat, gıda, sağlık"),
        (.low, "info.circle.fill", "Ofis, perakende, hizmet"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 3, total: 5, trailingLabel: "03 / 05", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 14) {
                        OBHeroTile { OBHeroHazard() }
                            .obStage(delay: 0.08)
                        Text("Hangi tehlike sınıfında çalışıyorsun?")
                            .font(.system(size: 28, weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.14)
                        Text("Birden fazla seçebilirsin.")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .obStage(delay: 0.28)

                    VStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            OBCard(
                                title: item.cls.label,
                                subtitle: item.sub,
                                isSelected: state.hazards.contains(item.cls),
                                multi: true,
                                accessibilityID: "onboarding.hazard.\(item.cls.rawValue)",
                                leading: { hazardIcon(item.cls, icon: item.icon) }
                            ) {
                                OBHaptic.medium()
                                withAnimation(.obSpring) { state.toggleHazard(item.cls) }
                            }
                            .obStage(delay: 0.32 + Double(i) * 0.06)
                        }
                    }

                    OBSelectionCounter(count: state.hazards.count, suffix: "sınıf seçildi")
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            OBFooter {
                OBPrimaryButton(title: "Devam", enabled: !state.hazards.isEmpty, accessibilityID: "onboarding.hazard.continue") { onNext() }
                    .obStage(delay: 0.7)
            }
        }
        .background(Color.rdPaper)
        .accessibilityIdentifier("onboarding.hazard")
    }

    private func hazardIcon(_ cls: OBHazardClass, icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(cls.bgColor)
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(cls.color)
        }
        .frame(width: 44, height: 44)
    }
}
