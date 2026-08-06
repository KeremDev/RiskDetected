import SwiftUI

struct OBSafetyProfileSelectionView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 3, total: 5, trailingLabel: "03 / 05", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "globe.europe.africa.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.rdGreenDark)
                            .frame(width: 76, height: 76)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 22))

                        Text(
                            RDLocalization.string(
                                "safety.profile.title",
                                table: .safetyTerminology,
                                fallback: "İş güvenliği terminolojini seç"
                            )
                        )
                            .font(.system(size: RDFontScale.size(28), weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)

                        Text(
                            RDLocalization.string(
                                "safety.profile.body",
                                table: .safetyTerminology,
                                fallback: "Çalışmanda kullanılan terminolojiyi seç. Bu seçim analiz ve rapor ifadelerini değiştirir; yasal uyumluluğu belgelemez."
                            )
                        )
                            .font(.system(size: RDFontScale.size(15)))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(RDSafetyProfileID.englishSelectionCases) { profileID in
                            OBCard(
                                title: profileID.localizedTitle,
                                subtitle: profileID.localizedSubtitle,
                                isSelected: state.safetyProfileID == profileID,
                                accessibilityID: "onboarding.safety_profile.\(profileID.rawValue)",
                                leading: {
                                    Image(systemName: profileID.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.rdGreenDark)
                                        .frame(width: 44, height: 44)
                                        .background(Color.rdGreenSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            ) {
                                OBHaptic.medium()
                                withAnimation(.obSpring) {
                                    state.safetyProfileID = profileID
                                }
                            }
                        }
                    }

                    Text(
                        RDLocalization.string(
                            "safety.profile.footer",
                            table: .safetyTerminology,
                            fallback: "Gelecekteki analizler için bu seçimi Profil’den değiştirebilirsin."
                        )
                    )
                        .font(.system(size: RDFontScale.size(12)))
                        .foregroundStyle(Color.rdSlate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            OBFooter {
                OBPrimaryButton(
                    title: RDLocalization.string("onboarding.obsafety.profile.selection.view.continue.2db574eb", table: .onboarding, fallback: "Devam etmek"),
                    enabled: state.safetyProfileID != nil,
                    accessibilityID: "onboarding.safety_profile.continue",
                    action: onNext
                )
            }
        }
        .background(Color.rdPaper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.safety_profile")
    }
}

#Preview {
    OBSafetyProfileSelectionView(
        state: OnboardingV2State(step: 3, appLanguage: .english),
        onBack: {},
        onNext: {}
    )
}
