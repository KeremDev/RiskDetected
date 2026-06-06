import SwiftUI

struct OBSectorView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 4, total: 5, trailingLabel: "04 / 05", onBack: onBack)

            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    OBHeroTile { OBHeroSector() }
                        .obStage(delay: 0.08)
                    Text("En çok hangi sektörde çalışıyorsun?")
                        .font(.system(size: RDFontScale.size(24), weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(Color.rdOnyx)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .obStage(delay: 0.14)
                    Text("En fazla 2 sektör seçebilirsiniz — o sektörlerin risklerini önceleyeceğiz.")
                        .font(.system(size: RDFontScale.size(14)))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .obStage(delay: 0.22)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.rdLine)
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .obStage(delay: 0.28)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(OBSector.allCases.enumerated()), id: \.offset) { i, sector in
                        sectorCard(sector)
                            .obStage(delay: 0.32 + Double(i) * 0.05)
                    }
                }

                OBSelectionCounter(count: state.sectors.count, suffix: "sektör seçildi")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            Spacer(minLength: 8)

            OBFooter {
                OBPrimaryButton(title: "Devam", enabled: !state.sectors.isEmpty, accessibilityID: "onboarding.sector.continue") { onNext() }
                    .obStage(delay: 0.7)
            }
        }
        .background(Color.rdPaper)
        .accessibilityIdentifier("onboarding.sector")
    }

    private func sectorCard(_ s: OBSector) -> some View {
        let selected = state.sectors.contains(s)
        return Button {
            let accepted = state.toggleSector(s)
            if accepted {
                OBHaptic.medium()
                withAnimation(.obSpring) { }
            } else {
                OBHaptic.soft()
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(selected ? Color.rdOnyx : Color.rdFog)
                    Image(systemName: s.icon)
                        .font(.system(size: RDFontScale.size(14), weight: .regular))
                        .foregroundStyle(selected ? .white : Color.rdGraphite)
                }
                .frame(width: 30, height: 30)

                Spacer(minLength: 0)

                Text(s.label)
                    .font(.system(size: RDFontScale.size(13), weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(s.sub)
                    .font(.system(size: RDFontScale.size(11)))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 92)
            .padding(selected ? 9 : 10)
            .background(Color.rdWhite)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.rdOnyx : Color.rdOnyx.opacity(0.06),
                            lineWidth: selected ? 2 : 1)
            )
            .shadow(color: .black.opacity(selected ? 0.08 : 0.04), radius: selected ? 12 : 6, y: selected ? 6 : 3)
            .overlay(alignment: .topTrailing) {
                if selected {
                    ZStack {
                        Circle().fill(Color.rdOnyx)
                        Image(systemName: "checkmark")
                            .font(.system(size: RDFontScale.size(10), weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 18, height: 18)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(OBPressStyle())
        .accessibilityIdentifier("onboarding.sector.\(s.rawValue)")
    }
}

#Preview {
    OBSectorView(
        state: OnboardingV2State.previewSample(step: 4),
        onBack: {},
        onNext: {}
    )
}
