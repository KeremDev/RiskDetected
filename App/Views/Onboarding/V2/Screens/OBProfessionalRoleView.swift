import SwiftUI

struct OBProfessionalRoleView: View {
    @ObservedObject var state: OnboardingV2State
    let onBack: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(step: 2, total: 5, trailingLabel: "02 / 05", onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(systemName: "person.text.rectangle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.rdGreenDark)
                            .frame(width: 76, height: 76)
                            .background(Color.rdGreenSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 22))

                        Text(RDLocalization.string("onboarding.obprofessional.role.view.what.best.describes.your.role.cb5ef255", table: .onboarding, fallback: "Rolünüzü en iyi ne tanımlar?"))
                            .font(.system(size: RDFontScale.size(28), weight: .semibold))
                            .tracking(-0.8)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)

                        Text(RDLocalization.string("onboarding.obprofessional.role.view.choose.the.closest.option.this.does.not.verify.a.a568fb3b", table: .onboarding, fallback: "En yakın seçeneği seçin. Bu, bir lisansı veya mesleki durumu doğrulamaz."))
                            .font(.system(size: RDFontScale.size(15)))
                            .foregroundStyle(Color.rdSlate)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(spacing: 10) {
                        ForEach(OBProfessionalRole.allCases) { role in
                            OBCard(
                                title: role.label,
                                subtitle: roleSubtitle(role),
                                isSelected: state.professionalRole == role,
                                accessibilityID: "onboarding.role.\(role.rawValue)",
                                leading: {
                                    Image(systemName: roleIcon(role))
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(Color.rdGreenDark)
                                        .frame(width: 44, height: 44)
                                        .background(Color.rdGreenSoft)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            ) {
                                OBHaptic.medium()
                                withAnimation(.obSpring) {
                                    state.professionalRole = role
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            OBFooter {
                OBPrimaryButton(
                    title: RDLocalization.string("onboarding.obprofessional.role.view.continue.a1d0f82e", table: .onboarding, fallback: "Devam etmek"),
                    enabled: state.professionalRole != nil,
                    accessibilityID: "onboarding.role.continue",
                    action: onNext
                )
            }
        }
        .background(Color.rdPaper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.role")
    }

    private func roleSubtitle(_ role: OBProfessionalRole) -> String {
        switch role {
        case .safetyProfessional: return RDLocalization.string("onboarding.obprofessional.role.view.provides.workplace.safety.support.or.inspections.b7f20a56", table: .onboarding, fallback: "İşyeri güvenliği desteği veya denetimleri sağlar")
        case .safetyManager: return RDLocalization.string("onboarding.obprofessional.role.view.leads.health.safety.or.whs.activity.64cd8ac9", table: .onboarding, fallback: "Sağlık, güvenlik veya WHS faaliyetlerine öncülük eder")
        case .siteManager: return RDLocalization.string("onboarding.obprofessional.role.view.manages.site.operations.450bd9c7", table: .onboarding, fallback: "Site operasyonlarını yönetir")
        case .engineer: return RDLocalization.string("onboarding.obprofessional.role.view.engineering.or.technical.role.6d65e946", table: .onboarding, fallback: "Mühendislik veya teknik rol")
        case .supervisor: return RDLocalization.string("onboarding.obprofessional.role.view.supervises.people.or.work.activities.df558498", table: .onboarding, fallback: "İnsanları veya iş faaliyetlerini denetler")
        case .consultant: return RDLocalization.string("onboarding.obprofessional.role.view.advises.organisations.or.clients.fb24608f", table: .onboarding, fallback: "Kuruluşlara veya müşterilere tavsiyelerde bulunur")
        case .employerOwner: return RDLocalization.string("onboarding.obprofessional.role.view.responsible.for.a.business.or.workplace.10186bd4", table: .onboarding, fallback: "Bir işletme veya işyerinden sorumlu")
        case .other: return RDLocalization.string("onboarding.obprofessional.role.view.another.role.connected.to.workplace.safety.4a8815f1", table: .onboarding, fallback: "İşyeri güvenliğiyle bağlantılı başka bir rol")
        }
    }

    private func roleIcon(_ role: OBProfessionalRole) -> String {
        switch role {
        case .safetyProfessional: return "shield.checkered"
        case .safetyManager: return "person.3.fill"
        case .siteManager: return "building.2.fill"
        case .engineer: return "gearshape.2.fill"
        case .supervisor: return "person.badge.key.fill"
        case .consultant: return "person.crop.circle.badge.checkmark"
        case .employerOwner: return "briefcase.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

#Preview {
    OBProfessionalRoleView(
        state: OnboardingV2State(step: 2, appLanguage: .english),
        onBack: {},
        onNext: {}
    )
}
