import Foundation

enum PaywallSource: String, Codable, Equatable {
    case inApp = "in_app"
    case onboardingV2 = "onboarding_v2"
}

enum OnboardingPersonalPlanSegment: String, Codable, Equatable {
    case construction
    case industrialHighRisk = "industrial_high_risk"
    case osgbHighVolume = "osgb_high_volume"
    case officeService = "office_service"
    case healthTeam = "health_team"
}

struct OnboardingPersonalPlanStep: Equatable {
    let icon: String
    let title: String
    let subtitle: String
}

struct OnboardingPersonalPlanContext: Equatable {
    static let variantID = "onboarding_personal_plan_time_paywall_v1"

    let segment: OnboardingPersonalPlanSegment
    let eyebrow: String
    let headline: String
    let subtitle: String
    let chips: [String]
    let heroIcon: String
    let accentHex: String
    let steps: [OnboardingPersonalPlanStep]

    var segmentKey: String { segment.rawValue }

    @MainActor
    static func make(from state: OnboardingV2State) -> OnboardingPersonalPlanContext {
        let segment = resolveSegment(from: state)
        let certificate = state.certificateLabel
        let hazard = state.hazardsLabel
        let sector = state.primarySectorLabel
        let frequency = state.frequency?.title ?? RDLocalization.string("onboarding.onboarding.personal.plan.rutin.denetim.711caa02", table: .onboarding, fallback: "Rutin denetim")
        let chips = [certificate, hazard, sector]

        switch segment {
        case .osgbHighVolume:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: RDLocalization.string("onboarding.onboarding.personal.plan.sana.ozel.e76ebb67", table: .onboarding, fallback: "Sana Özel"),
                headline: RDLocalization.string("onboarding.onboarding.personal.plan.yogun.denetim.temponla.yarisacak.planin.hazir.4258cfff", table: .onboarding, fallback: "Yoğun denetim temponla yarışacak planın hazır"),
                subtitle: RDLocalization.format("onboarding.onboarding.personal.plan.isg.icin.egitilmis.sistem.1.temposunda.7ef96c1d", table: .onboarding, fallback: "İSG için eğitilmiş sistem, %1$@ temposunda.", arguments: [String(describing: frequency)]),
                chips: chips,
                heroIcon: "bolt.fill",
                accentHex: "#2F6FED",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.b1bfc79a", table: .onboarding, fallback: "Fotoğraf"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.isg.icin.egitilmis.yapay.zekamiz.aninda.cozumles.791693f0", table: .onboarding, fallback: "İSG için eğitilmiş yapay zekamız anında çözümlesin.")),
                    OnboardingPersonalPlanStep(icon: "exclamationmark.triangle.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.riskler.81ff87d0", table: .onboarding, fallback: "Riskler"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.en.kritik.bulgu.liste.basinda.df7429ca", table: .onboarding, fallback: "En kritik bulgu liste başında.")),
                    OnboardingPersonalPlanStep(icon: "building.2.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.rapor.536a7ec0", table: .onboarding, fallback: "Rapor"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.rapor.firma.arsivine.kaydedilsin.ce75c5a8", table: .onboarding, fallback: "Rapor firma arşivine kaydedilsin.")),
                    OnboardingPersonalPlanStep(icon: "paperplane.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.paylas.44a3428e", table: .onboarding, fallback: "Paylaş"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.risk.analizini.pdf.excel.tek.tikla.ilet.ef23bc9f", table: .onboarding, fallback: "Risk Analizini PDF/Excel tek tıkla ilet."))
                ]
            )
        case .healthTeam:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: RDLocalization.string("onboarding.onboarding.personal.plan.sana.ozel.ekip.akisi.68a81134", table: .onboarding, fallback: "Sana özel ekip akışı"),
                headline: RDLocalization.string("onboarding.onboarding.personal.plan.isg.ekibin.icin.kayit.ve.paylasim.duzeni.hazir.69bbf645", table: .onboarding, fallback: "İSG ekibin için kayıt ve paylaşım düzeni hazır"),
                subtitle: RDLocalization.format("onboarding.onboarding.personal.plan.1.rolune.gore.anlasilir.bulgu.dili.ve.duzenli.do.936186a5", table: .onboarding, fallback: "%1$@ rolüne göre; anlaşılır bulgu dili ve düzenli dokümantasyon odaklı bir akış kurduk. Ekip içi iletişim ve arşivleme aynı yerde.", arguments: [String(describing: certificate)]),
                chips: chips,
                heroIcon: "cross.case.fill",
                accentHex: "#0F9F8F",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.b1bfc79a", table: .onboarding, fallback: "Fotoğraf"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.gozlemini.hizla.analize.aktar.4bdb0017", table: .onboarding, fallback: "Gözlemini hızla analize aktar.")),
                    OnboardingPersonalPlanStep(icon: "person.2.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.ekip.dilinde.ozetle.a9beebae", table: .onboarding, fallback: "Ekip dilinde özetle"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.bulgular.anlasilir.ve.uygulanabilir.kalsin.ed3f419d", table: .onboarding, fallback: "Bulgular anlaşılır ve uygulanabilir kalsın.")),
                    OnboardingPersonalPlanStep(icon: "doc.richtext.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.rapor.ciktisi.olustur.4290d684", table: .onboarding, fallback: "Rapor çıktısı oluştur"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.kayit.ve.takip.icin.duzenli.dokuman.uret.969178b2", table: .onboarding, fallback: "Kayıt ve takip için düzenli doküman üret.")),
                    OnboardingPersonalPlanStep(icon: "square.and.arrow.up.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.paylas.ve.arsivle.5b69a799", table: .onboarding, fallback: "Paylaş ve arşivle"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.raporlar.ekibinin.hep.elinin.altinda.olsun.1ff6f6c8", table: .onboarding, fallback: "Raporlar ekibinin hep elinin altında olsun."))
                ]
            )
        case .construction:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: RDLocalization.string("onboarding.onboarding.personal.plan.sana.ozel.a7533e6f", table: .onboarding, fallback: "Sana Özel"),
                headline: RDLocalization.string("onboarding.onboarding.personal.plan.santiye.tehlikeleri.dakikalar.icinde.raporla.907e15d0", table: .onboarding, fallback: "Şantiye tehlikeleri dakikalar içinde raporla."),
                subtitle: RDLocalization.format("onboarding.onboarding.personal.plan.1.icin.egitilmis.sistem.aninda.rapor.914d7f50", table: .onboarding, fallback: "%1$@ için eğitilmiş sistem, anında rapor.", arguments: [String(describing: sector)]),
                chips: chips,
                heroIcon: "hammer.fill",
                accentHex: "#C56B12",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.7d19fd1b", table: .onboarding, fallback: "Fotoğraf"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.isg.icin.egitilmis.yapay.zekamiz.aninda.cozumles.99c8bc1a", table: .onboarding, fallback: "İSG için eğitilmiş yapay zekamız anında çözümlesin.")),
                    OnboardingPersonalPlanStep(icon: "shield.lefthalf.filled", title: RDLocalization.string("onboarding.onboarding.personal.plan.riskler.795bed4e", table: .onboarding, fallback: "Riskler"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.en.kritik.bulgu.liste.basinda.0a587b37", table: .onboarding, fallback: "En kritik bulgu liste başında.")),
                    OnboardingPersonalPlanStep(icon: "doc.text.magnifyingglass", title: RDLocalization.string("onboarding.onboarding.personal.plan.risk.analizi.6f07ec67", table: .onboarding, fallback: "Risk Analizi"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.fine.kinney.5.5.rapor.hazir.fdc34345", table: .onboarding, fallback: "Fine-Kinney/5*5 Rapor hazır.")),
                    OnboardingPersonalPlanStep(icon: "paperplane.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.paylas.d5d89d64", table: .onboarding, fallback: "Paylaş"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.risk.analizini.pdf.excel.tek.tikla.ilet.81f86a73", table: .onboarding, fallback: "Risk Analizini PDF/Excel tek tıkla ilet."))
                ]
            )
        case .industrialHighRisk:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: RDLocalization.string("onboarding.onboarding.personal.plan.sana.ozel.ef4ca24e", table: .onboarding, fallback: "Sana özel"),
                headline: RDLocalization.string("onboarding.onboarding.personal.plan.risk.analiz.planin.hazir.87aa9334", table: .onboarding, fallback: "Risk analiz planın hazır"),
                subtitle: RDLocalization.format("onboarding.onboarding.personal.plan.1.icin.egitilmis.sistem.denetime.hazir.rapor.acda2ffe", table: .onboarding, fallback: "%1$@ için eğitilmiş sistem, denetime hazır rapor.", arguments: [String(describing: sector)]),
                chips: chips,
                heroIcon: "exclamationmark.shield.fill",
                accentHex: "#B42318",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.e877cacc", table: .onboarding, fallback: "Fotoğraf"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.ya.da.metni.paylas.analiz.baslasin.8cd0d9d4", table: .onboarding, fallback: "Fotoğraf ya da metni paylaş, analiz başlasın.")),
                    OnboardingPersonalPlanStep(icon: "gauge", title: RDLocalization.string("onboarding.onboarding.personal.plan.riskler.d4c2534a", table: .onboarding, fallback: "Riskler"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.en.kritik.bulgu.liste.basinda.dfb35613", table: .onboarding, fallback: "En kritik bulgu liste başında.")),
                    OnboardingPersonalPlanStep(icon: "doc.text.magnifyingglass", title: RDLocalization.string("onboarding.onboarding.personal.plan.detayli.rapor.uretilir.e12f7411", table: .onboarding, fallback: "Detaylı rapor üretilir"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.fine.kinney.ve.5x5.ciktilari.otomatik.hazirlanir.7877daa5", table: .onboarding, fallback: "Fine-Kinney ve 5x5 çıktıları otomatik hazırlanır.")),
                    OnboardingPersonalPlanStep(icon: "building.2.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.paylas.5fb1aeba", table: .onboarding, fallback: "Paylaş"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.risk.analizini.pdf.excel.tek.tikla.ilet.00cf0ce0", table: .onboarding, fallback: "Risk Analizini PDF/Excel tek tıkla ilet."))
                ]
            )
        case .officeService:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: RDLocalization.string("onboarding.onboarding.personal.plan.sana.ozel.denetim.akisi.97d6a60f", table: .onboarding, fallback: "Sana özel denetim akışı"),
                headline: RDLocalization.string("onboarding.onboarding.personal.plan.pratik.kontrol.ve.raporlama.akisin.hazir.b6d6d6ba", table: .onboarding, fallback: "Pratik kontrol ve raporlama akışın hazır"),
                subtitle: RDLocalization.format("onboarding.onboarding.personal.plan.1.icin.egitilmis.sistem.sade.rapor.91133a60", table: .onboarding, fallback: "%1$@ için eğitilmiş Sistem, sade rapor.", arguments: [String(describing: sector)]),
                chips: chips,
                heroIcon: "building.2.fill",
                accentHex: "#237A3B",
                steps: [
                    OnboardingPersonalPlanStep(icon: "checklist", title: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.16fde2d2", table: .onboarding, fallback: "Fotoğraf"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.fotograf.ya.da.metni.paylas.analiz.baslasin.e4690171", table: .onboarding, fallback: "Fotoğraf ya da metni paylaş, analiz başlasın.")),
                    OnboardingPersonalPlanStep(icon: "exclamationmark.triangle.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.riskler.fa4a65d3", table: .onboarding, fallback: "Riskler"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.en.kritik.bulgu.liste.basinda.d608fb84", table: .onboarding, fallback: "En kritik bulgu liste başında.")),
                    OnboardingPersonalPlanStep(icon: "doc.on.doc.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.rapor.55c2795b", table: .onboarding, fallback: "Rapor"), subtitle: RDLocalization.string("onboarding.onboarding.personal.plan.pdf.excel.ciktisi.arsive.hazir.gelir.b0361bc4", table: .onboarding, fallback: "PDF/Excel çıktısı arşive hazır gelir.")),
                    OnboardingPersonalPlanStep(icon: "clock.fill", title: RDLocalization.string("onboarding.onboarding.personal.plan.takip.ritmini.koru.085971c4", table: .onboarding, fallback: "Takip ritmini koru"), subtitle: RDLocalization.format("onboarding.onboarding.personal.plan.1.akisina.uygun.ilerle.a26399c3", table: .onboarding, fallback: "%1$@ akışına uygun ilerle.", arguments: [String(describing: frequency)]))
                ]
            )
        }
    }

    @MainActor
    private static func resolveSegment(from state: OnboardingV2State) -> OnboardingPersonalPlanSegment {
        if state.frequency == .sixToFifteen || state.frequency == .fifteenPlus {
            return .osgbHighVolume
        }
        if state.certificate == .doctor || state.certificate == .otherHealth {
            return .healthTeam
        }
        if state.sectors.contains(.construction) {
            return .construction
        }
        if state.sectors.contains(.mining) ||
            state.sectors.contains(.energy) ||
            state.sectors.contains(.manufacturing) ||
            state.hazards.contains(.critical)
        {
            return .industrialHighRisk
        }
        return .officeService
    }
}
