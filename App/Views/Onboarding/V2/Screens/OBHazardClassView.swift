import SwiftUI

struct OBHazardClassView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void

    private let items: [(cls: OBHazardClass, icon: String, sub: String)] = [
        (.critical, "exclamationmark.triangle.fill", RDLocalization.string("onboarding.obhazard.class.view.petrokimya.maden.insaat.fabrika.vb.34e41743", table: .onboarding, fallback: "Petrokimya, maden, inşaat, fabrika vb.")),
        (.high, "exclamationmark.circle.fill", RDLocalization.string("onboarding.obhazard.class.view.imalat.gida.saglik.vb.5c5fd03f", table: .onboarding, fallback: "İmalat, gıda, sağlık vb.")),
        (.low, "info.circle.fill", RDLocalization.string("onboarding.obhazard.class.view.ofis.perakende.hizmet.vb.37aa6e42", table: .onboarding, fallback: "Ofis, perakende, hizmet vb.")),
    ]

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 3, total: 5, trailingLabel: "03 / 05", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 14) {
                        OBHeroTile { OBHeroHazard() }
                            .obStage(delay: 0.08)
                        Text(RDLocalization.string("onboarding.obhazard.class.view.hangi.tehlike.sinifinda.calisiyorsun.79f6293b", table: .onboarding, fallback: "Hangi tehlike sınıfında çalışıyorsun?"))
                            .font(.system(size: RDFontScale.size(28), weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.14)
                        Text(RDLocalization.string("onboarding.obhazard.class.view.birden.fazla.secebilirsin.9a89b3cb", table: .onboarding, fallback: "Birden fazla seçebilirsin."))
                            .font(.system(size: RDFontScale.size(15)))
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

                    OBSelectionCounter(count: state.hazards.count, suffix: RDLocalization.string("onboarding.obhazard.class.view.sinif.secildi.1b7300f0", table: .onboarding, fallback: "sınıf seçildi"))
                        .padding(.top, 6)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            OBFooter {
                OBPrimaryButton(title: RDLocalization.string("onboarding.obhazard.class.view.devam.dca438c1", table: .onboarding, fallback: "Devam"), enabled: !state.hazards.isEmpty, accessibilityID: "onboarding.hazard.continue") { onNext() }
                    .obStage(delay: 0.7)
            }
        }
        .background(Color.rdPaper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.hazard")
    }

    private func hazardIcon(_ cls: OBHazardClass, icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(cls.bgColor)
            Image(systemName: icon)
                .font(.system(size: RDFontScale.size(20)))
                .foregroundStyle(cls.color)
        }
        .frame(width: 44, height: 44)
    }
}

#Preview {
    OBHazardClassView(
        state: OnboardingV2State.previewSample(step: 3),
        onBack: {},
        onNext: {}
    )
}
