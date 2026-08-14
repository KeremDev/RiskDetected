import SwiftUI

// PASSIVE_LEGACY_VIEW: kept for visual reference only.
// The live onboarding flow uses OBTimelinePaywallView at step 11.
struct OBPaywallView: View {
    @ObservedObject var state: OnboardingV2State
    var packages: [SubscriptionPlanPackage] = []
    let onStartTrial: () -> Void
    let onDismiss: () -> Void

    private let benefits: [(icon: String, title: String, sub: String)] = [
        ("photo.fill", RDLocalization.string("onboarding.obpaywall.view.sinirsiz.fotograf.analizi.d14fa9d7", table: .onboarding, fallback: "Sınırsız fotoğraf analizi"), RDLocalization.string("onboarding.obpaywall.view.fine.kinney.5.5.l.s.4ac3cf81", table: .onboarding, fallback: "Fine-Kinney · 5×5 · L×Ş")),
        ("doc.text.fill", RDLocalization.string("onboarding.obpaywall.view.pdf.excel.disa.aktarim.893fa0e6", table: .onboarding, fallback: "PDF + Excel dışa aktarım"), RDLocalization.string("onboarding.obpaywall.view.mevzuat.referanslari.ile.927c6758", table: .onboarding, fallback: "Mevzuat referansları ile")),
        ("person.2.fill", RDLocalization.string("onboarding.obpaywall.view.ekip.ile.paylas.ve.yorumla.3d615ff3", table: .onboarding, fallback: "Ekip ile paylaş ve yorumla"), RDLocalization.string("onboarding.obpaywall.view.5.kullaniciya.kadar.52755363", table: .onboarding, fallback: "5 kullanıcıya kadar")),
        ("bubble.left.fill", RDLocalization.string("onboarding.obpaywall.view.oncelikli.destek.d923fb48", table: .onboarding, fallback: "Öncelikli destek"), RDLocalization.string("onboarding.obpaywall.view.turkce.24.saat.icinde.yanit.b7483600", table: .onboarding, fallback: "Türkçe · 24 saat içinde yanıt"))
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: "#161819"), Color(hex: "#0B0D0E")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        pill
                            .padding(.top, 56)
                            .obStage(delay: 0.08)

                        Text(titleAttr)
                            .font(.system(size: RDFontScale.size(30), weight: .semibold))
                            .tracking(-0.96)
                            .lineSpacing(2)
                            .padding(.top, 18)
                            .obStage(delay: 0.16)

                        trialPill
                            .padding(.top, 12)
                            .obStage(delay: 0.24)

                        benefitsCard
                            .padding(.top, 24)
                            .obStage(delay: 0.34)

                        VStack(spacing: 10) {
                            planCard(.yearly)
                                .obStage(delay: 0.46)
                            planCard(.monthly)
                                .obStage(delay: 0.54)
                        }
                        .padding(.top, 16)

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    Button {
                        OBHaptic.medium(); onStartTrial()
                    } label: {
                        HStack(spacing: 8) {
                            Text(RDLocalization.string("onboarding.obpaywall.view.ucretsiz.denemeyi.baslat.a308f2c3", table: .onboarding, fallback: "Devam et"))
                                .font(.system(size: RDFontScale.size(16), weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: RDFontScale.size(15), weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(Color.rdGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.rdGreen.opacity(0.32), radius: 16, y: 6)
                    }
                    .buttonStyle(OBPressStyle())
                    .obStage(delay: 0.68)

                    finePrint
                        .obStage(delay: 0.76)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .background(
                    LinearGradient(colors: [.clear, Color(hex: "#0B0D0E").opacity(0.6), Color(hex: "#0B0D0E")],
                                   startPoint: .top, endPoint: .bottom)
                )
            }

            Button {
                OBHaptic.light(); onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: RDFontScale.size(14), weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(OBPressStyle())
            .padding(.top, 64)
            .padding(.trailing, 16)
        }
    }

    private var titleAttr: AttributedString {
        var s = AttributedString(RDLocalization.string("onboarding.obpaywall.view.sahadaki.her.gozlemi.74e61cb3", table: .onboarding, fallback: "Sahadaki her gözlemi"))
        var accent = AttributedString("rapora")
        accent.foregroundColor = Color(hex: "#4FE07E")
        s.append(accent)
        s.append(AttributedString(RDLocalization.string("onboarding.obpaywall.view.donustur.569f5956", table: .onboarding, fallback: "dönüştür.")))
        s.foregroundColor = .white
        return s
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#00E03A")).frame(width: 5, height: 5)
            Text(RDLocalization.format("onboarding.obpaywall.view.1.uzmanlari.icin.hazirlandi.1895b300", table: .onboarding, fallback: "%1$@ UZMANLARI İÇİN HAZIRLANDI", arguments: [String(describing: state.primarySectorLabel.uppercased())]))
                .font(.system(size: RDFontScale.size(11), weight: .semibold))
                .tracking(0.8)
        }
        .foregroundStyle(Color(hex: "#4FE07E"))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.rdGreen.opacity(0.16))
        .overlay(Capsule().stroke(Color.rdGreen.opacity(0.32), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var trialPill: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#4FE07E")).frame(width: 5, height: 5)
                .shadow(color: Color(hex: "#4FE07E"), radius: 4)
            Text(RDLocalization.string("onboarding.obpaywall.view.planin.hazir.7.gun.ucretsiz.dene.77c5ffa7", table: .onboarding, fallback: "Fiyat ve uygun teklifler App Store'da doğrulanır"))
                .font(.system(size: RDFontScale.size(12), weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var benefitsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.offset) { i, b in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.rdGreen.opacity(0.18))
                        Image(systemName: b.icon)
                            .font(.system(size: RDFontScale.size(14)))
                            .foregroundStyle(Color(hex: "#4FE07E"))
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title)
                            .font(.system(size: RDFontScale.size(14), weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(b.sub)
                            .font(.system(size: RDFontScale.size(12)))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                if i < benefits.count - 1 {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func planCard(_ plan: OBPlan) -> some View {
        let selected = state.selectedPlan == plan
        let isYearly = plan == .yearly
        return Button {
            OBHaptic.light()
            withAnimation(.obSpring) { state.selectedPlan = plan }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color(hex: "#4FE07E") : .white.opacity(0.25), lineWidth: 1.5)
                    if selected {
                        Circle().fill(Color(hex: "#4FE07E")).padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isYearly ? RDLocalization.string("onboarding.obpaywall.view.yillik.5e3176f4", table: .onboarding, fallback: "Yıllık") : RDLocalization.string("onboarding.obpaywall.view.aylik.c58200cd", table: .onboarding, fallback: "Aylık"))
                            .font(.system(size: RDFontScale.size(14), weight: .semibold))
                            .foregroundStyle(.white)
                        if isYearly {
                            Text(RDLocalization.string("onboarding.obpaywall.view.17.indirim.acd00702", table: .onboarding, fallback: "%17 İNDİRİM"))
                                .font(.system(size: RDFontScale.size(10), weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Color.rdOnyx)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#4FE07E"))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text(planSubtitle(for: plan))
                        .font(.system(size: RDFontScale.size(12)))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(displayPrice(for: plan))
                        .font(.system(size: RDFontScale.size(17), weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(isYearly ? RDLocalization.string("onboarding.obpaywall.view.yil.a344c127", table: .onboarding, fallback: "/yıl") : "/ay")
                        .font(.system(size: RDFontScale.size(11)))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(selected ? Color.rdGreen.opacity(0.10) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color(hex: "#4FE07E") : Color.white.opacity(0.1),
                            lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(OBPressStyle())
    }

    private func planSubtitle(for plan: OBPlan) -> String {
        switch plan {
        case .yearly:
            guard let price = displayPriceValue(for: .yearly) else {
                return RDLocalization.string("onboarding.obpaywall.view.ilk.7.gun.ucretsiz.fiyat.app.store.uzerinden.yuk.7d822ee9", table: .onboarding, fallback: "Fiyat ve uygun teklifler App Store'da gösterilir")
            }
            return RDLocalization.format("onboarding.obpaywall.view.ilk.7.gun.ucretsiz.sonra.1.yil.92cf2208", table: .onboarding, fallback: "Yıllık %1$@ · varsa teklif App Store'da uygulanır", arguments: [String(describing: price)])
        case .monthly:
            return RDLocalization.string("onboarding.obpaywall.view.hemen.baslar.istedigin.zaman.iptal.bda70860", table: .onboarding, fallback: "Hemen başlar · istediğin zaman iptal")
        }
    }

    private func displayPrice(for plan: OBPlan) -> String {
        displayPriceValue(for: plan) ?? OBTrialPriceCopy.loadingPrice
    }

    private func displayPriceValue(for plan: OBPlan) -> String? {
        plusPackage(for: plan)?.displayPrice
    }

    private func plusPackage(for plan: OBPlan) -> SubscriptionPlanPackage? {
        packages
            .filter { $0.tier == .plus }
            .first { $0.matchesOnboardingBilling(plan) }
    }

    private var finePrint: some View {
        VStack(spacing: 4) {
            Text(RDLocalization.string("onboarding.obpaywall.view.istedigin.zaman.iptal.app.store.uzerinden.fatura.34352096", table: .onboarding, fallback: "İstediğin zaman iptal · App Store üzerinden faturalandırılır"))
            HStack(spacing: 0) {
                Text(RDLocalization.string("onboarding.obpaywall.view.sartlar.9a992598", table: .onboarding, fallback: "Şartlar")).underline()
                dot
                Text(RDLocalization.string("onboarding.obpaywall.view.gizlilik.120a8da1", table: .onboarding, fallback: "Gizlilik")).underline()
                dot
                Text(RDLocalization.string("onboarding.obpaywall.view.satin.alimlari.geri.yukle.b9e04822", table: .onboarding, fallback: "Satın alımları geri yükle")).underline()
            }
        }
        .font(.system(size: RDFontScale.size(11)))
        .foregroundStyle(.white.opacity(0.45))
        .lineSpacing(3)
        .frame(maxWidth: .infinity)
    }

    private var dot: some View {
        Circle().fill(.white.opacity(0.3))
            .frame(width: 3, height: 3)
            .padding(.horizontal, 5)
    }
}

#Preview {
    OBPaywallView(
        state: OnboardingV2State.previewSample(step: 11),
        onStartTrial: {},
        onDismiss: {}
    )
}
