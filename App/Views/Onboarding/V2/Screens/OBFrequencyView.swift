import SwiftUI

struct OBFrequencyView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void
    @Environment(\.rdLayoutProfile) private var layoutProfile

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 5, total: 5, trailingLabel: "05 / 05", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    VStack(spacing: 10) {
                        OBHeroTile(tint: .green) { OBHeroFrequency() }
                            .obStage(delay: 0.08)
                        Text(RDLocalization.string("onboarding.obfrequency.view.haftada.kac.isyerinde.denetim.yapiyorsun.800c3756", table: .onboarding, fallback: "Haftada kaç işyerinde denetim yapıyorsun?"))
                            .font(RDTypography.font(size: RDFontScale.size(22), weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.14)
                        Text(RDLocalization.string("onboarding.obfrequency.view.planimizi.senin.tempona.gore.olceklendirelim.a834ab15", table: .onboarding, fallback: "Planımızı senin tempona göre ölçeklendirelim."))
                            .font(RDTypography.font(size: RDFontScale.size(14)))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                        .obStage(delay: 0.28)

                    VStack(spacing: 12) {
                        ForEach(Array(OBFrequency.allCases.enumerated()), id: \.offset) { i, freq in
                            freqCard(freq)
                                .obStage(delay: 0.32 + Double(i) * 0.06)
                        }
                    }
                }
                .padding(.horizontal, layoutProfile.horizontalPadding)
                .padding(.bottom, 16)
            }

            OBFooter {
                OBPrimaryButton(title: RDLocalization.string("onboarding.obfrequency.view.planimi.hazirla.3638fcc3", table: .onboarding, fallback: "Planımı Hazırla"), enabled: state.frequency != nil, accessibilityID: "onboarding.frequency.prepare") { onNext() }
                    .obStage(delay: 0.68)
            }
        }
        .background(Color.rdPaper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.frequency")
    }

    private func freqCard(_ f: OBFrequency) -> some View {
        let selected = state.frequency == f
        return Button {
            OBHaptic.medium()
            withAnimation(.obSpring) { state.frequency = f }
        } label: {
            HStack(spacing: 16) {
                Text(f.rawValue)
                    .font(RDTypography.font(size: RDFontScale.size(30), weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.rdOnyx)
                    .frame(minWidth: 72, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.title)
                        .font(RDTypography.font(size: RDFontScale.size(16), weight: .semibold))
                        .foregroundStyle(Color.rdOnyx)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(f.sub)
                        .font(RDTypography.font(size: RDFontScale.size(13)))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .semibold))
                    .foregroundStyle(selected ? Color.rdOnyx : Color.rdSlate.opacity(0.4))
                    .offset(x: selected ? 2 : 0)
            }
            .padding(.horizontal, selected ? 17 : 18)
            .padding(.vertical, selected ? 17 : 18)
            .frame(minHeight: 84)
            .background(Color.rdWhite)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(selected ? Color.rdOnyx : Color.rdOnyx.opacity(0.06),
                            lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(selected ? 0.08 : 0.04), radius: selected ? 14 : 8, y: selected ? 8 : 4)
        }
        .buttonStyle(OBPressStyle())
        .accessibilityIdentifier("onboarding.frequency.\(f.rawValue.replacingOccurrences(of: "+", with: "_plus").replacingOccurrences(of: "-", with: "_"))")
    }
}

#Preview {
    OBFrequencyView(
        state: OnboardingV2State.previewSample(step: 5),
        onBack: {},
        onNext: {}
    )
}
