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
        let frequency = state.frequency?.title ?? "Rutin denetim"
        let chips = [certificate, hazard, sector]

        switch segment {
        case .osgbHighVolume:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: "Sana Özel",
                headline: "Yoğun denetim temponla yarışacak planın hazır",
                subtitle: "İSG için eğitilmiş sistem, \(frequency) temposunda.",
                chips: chips,
                heroIcon: "bolt.fill",
                accentHex: "#2F6FED",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: "Fotoğraf", subtitle: "İSG için eğitilmiş yapay zekamız anında çözümlesin."),
                    OnboardingPersonalPlanStep(icon: "exclamationmark.triangle.fill", title: "Riskler", subtitle: "En kritik bulgu liste başında."),
                    OnboardingPersonalPlanStep(icon: "building.2.fill", title: "Rapor", subtitle: "Rapor firma arşivine kaydedilsin."),
                    OnboardingPersonalPlanStep(icon: "paperplane.fill", title: "Paylaş", subtitle: "Risk Analizini PDF/Excel tek tıkla ilet.")
                ]
            )
        case .healthTeam:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: "Sana özel ekip akışı",
                headline: "İSG ekibin için kayıt ve paylaşım düzeni hazır",
                subtitle: "\(certificate) rolüne göre; anlaşılır bulgu dili ve düzenli dokümantasyon odaklı bir akış kurduk. Ekip içi iletişim ve arşivleme aynı yerde.",
                chips: chips,
                heroIcon: "cross.case.fill",
                accentHex: "#0F9F8F",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: "Fotoğraf", subtitle: "Gözlemini hızla analize aktar."),
                    OnboardingPersonalPlanStep(icon: "person.2.fill", title: "Ekip dilinde özetle", subtitle: "Bulgular anlaşılır ve uygulanabilir kalsın."),
                    OnboardingPersonalPlanStep(icon: "doc.richtext.fill", title: "Rapor çıktısı oluştur", subtitle: "Kayıt ve takip için düzenli doküman üret."),
                    OnboardingPersonalPlanStep(icon: "square.and.arrow.up.fill", title: "Paylaş ve arşivle", subtitle: "Raporlar ekibinin hep elinin altında olsun.")
                ]
            )
        case .construction:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: "Sana Özel",
                headline: "Şantiye tehlikeleri dakikalar içinde raporla.",
                subtitle: "\(sector) için eğitilmiş sistem, anında rapor.",
                chips: chips,
                heroIcon: "hammer.fill",
                accentHex: "#C56B12",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: "Fotoğraf", subtitle: "İSG için eğitilmiş yapay zekamız anında çözümlesin."),
                    OnboardingPersonalPlanStep(icon: "shield.lefthalf.filled", title: "Riskler", subtitle: "En kritik bulgu liste başında."),
                    OnboardingPersonalPlanStep(icon: "doc.text.magnifyingglass", title: "Risk Analizi", subtitle: "Fine-Kinnet/5*5 Rapor hazır."),
                    OnboardingPersonalPlanStep(icon: "paperplane.fill", title: "Paylaş", subtitle: "Risk Analizini PDF/Excel tek tıkla ilet.")
                ]
            )
        case .industrialHighRisk:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: "Sana özel",
                headline: "Risk analiz planın hazır",
                subtitle: "\(sector) için eğitilmiş sistem, denetime hazır rapor.",
                chips: chips,
                heroIcon: "exclamationmark.shield.fill",
                accentHex: "#B42318",
                steps: [
                    OnboardingPersonalPlanStep(icon: "camera.viewfinder", title: "Fotoğraf", subtitle: "Fotoğraf ya da metni paylaş, analiz başlasın."),
                    OnboardingPersonalPlanStep(icon: "gauge", title: "Riskler", subtitle: "En kritik bulgu liste başında."),
                    OnboardingPersonalPlanStep(icon: "doc.text.magnifyingglass", title: "Detaylı rapor üretilir", subtitle: "Fine-Kinney ve 5x5 çıktıları otomatik hazırlanır."),
                    OnboardingPersonalPlanStep(icon: "building.2.fill", title: "Paylaş", subtitle: "Risk Analizini PDF/Excel tek tıkla ilet.")
                ]
            )
        case .officeService:
            return OnboardingPersonalPlanContext(
                segment: segment,
                eyebrow: "Sana özel denetim akışı",
                headline: "Pratik kontrol ve raporlama akışın hazır",
                subtitle: "\(sector) için eğitilmiş Sistem, sade rapor.",
                chips: chips,
                heroIcon: "building.2.fill",
                accentHex: "#237A3B",
                steps: [
                    OnboardingPersonalPlanStep(icon: "checklist", title: "Fotoğraf", subtitle: "Fotoğraf ya da metni paylaş, analiz başlasın."),
                    OnboardingPersonalPlanStep(icon: "exclamationmark.triangle.fill", title: "Riskler", subtitle: "En kritik bulgu liste başında."),
                    OnboardingPersonalPlanStep(icon: "doc.on.doc.fill", title: "Rapor", subtitle: "PDF/Excel çıktısı arşive hazır gelir."),
                    OnboardingPersonalPlanStep(icon: "clock.fill", title: "Takip ritmini koru", subtitle: "\(frequency) akışına uygun ilerle.")
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
