import SwiftUI

enum OBProfessionalRole: String, CaseIterable, Identifiable {
    case safetyProfessional = "safety_professional"
    case safetyManager = "hse_ohs_whs_manager"
    case siteManager = "site_manager"
    case engineer
    case supervisor
    case consultant
    case employerOwner = "employer_owner"
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .safetyProfessional: return RDLocalization.string("onboarding.onboarding.v2.state.safety.professional.c44c5726", table: .onboarding, fallback: "Güvenlik uzmanı")
        case .safetyManager: return RDLocalization.string("onboarding.onboarding.v2.state.hse.ohs.whs.manager.d49c5272", table: .onboarding, fallback: "SEÇ/İSG/İSG yöneticisi")
        case .siteManager: return RDLocalization.string("onboarding.onboarding.v2.state.site.manager.f4479e1d", table: .onboarding, fallback: "Site yöneticisi")
        case .engineer: return RDLocalization.string("onboarding.onboarding.v2.state.engineer.c783d461", table: .onboarding, fallback: "Mühendis")
        case .supervisor: return RDLocalization.string("onboarding.onboarding.v2.state.supervisor.4c6a7edf", table: .onboarding, fallback: "Süpervizör")
        case .consultant: return RDLocalization.string("onboarding.onboarding.v2.state.consultant.bf04c397", table: .onboarding, fallback: "Danışman")
        case .employerOwner: return RDLocalization.string("onboarding.onboarding.v2.state.employer.owner.d72645c4", table: .onboarding, fallback: "İşveren/Sahip")
        case .other: return RDLocalization.string("onboarding.onboarding.v2.state.other.54ebe7f5", table: .onboarding, fallback: "Diğer")
        }
    }
}

enum OBCertificate: String, CaseIterable, Identifiable {
    case A, B, C, doctor, otherHealth
    var id: String { rawValue }

    var label: String {
        switch self {
        case .A: return RDLocalization.string("onboarding.onboarding.v2.state.a.sinifi.0251c6bf", table: .onboarding, fallback: "A Sınıfı")
        case .B: return RDLocalization.string("onboarding.onboarding.v2.state.b.sinifi.d1b0323b", table: .onboarding, fallback: "B Sınıfı")
        case .C: return RDLocalization.string("onboarding.onboarding.v2.state.c.sinifi.e98b4664", table: .onboarding, fallback: "C Sınıfı")
        case .doctor: return RDLocalization.string("onboarding.onboarding.v2.state.isyeri.hekimi.33816b60", table: .onboarding, fallback: "İşyeri Hekimi")
        case .otherHealth: return RDLocalization.string("onboarding.onboarding.v2.state.saglik.personeli.a48c2086", table: .onboarding, fallback: "Sağlık personeli")
        }
    }
}

enum OBHazardClass: String, CaseIterable, Identifiable {
    case critical, high, low
    var id: String { rawValue }

    var label: String {
        switch self {
        case .critical: return RDLocalization.string("onboarding.onboarding.v2.state.cok.tehlikeli.eababa99", table: .onboarding, fallback: "Çok Tehlikeli")
        case .high: return RDLocalization.string("onboarding.onboarding.v2.state.tehlikeli.ff529f2c", table: .onboarding, fallback: "Tehlikeli")
        case .low: return RDLocalization.string("onboarding.onboarding.v2.state.az.tehlikeli.af92fef7", table: .onboarding, fallback: "Az Tehlikeli")
        }
    }

    var color: Color {
        switch self {
        case .critical: return .rdCritical
        case .high: return .rdHigh
        case .low: return .rdLow
        }
    }

    var bgColor: Color {
        switch self {
        case .critical: return .rdCriticalBg
        case .high: return .rdHighBg
        case .low: return .rdLowBg
        }
    }
}

enum OBSector: String, CaseIterable, Identifiable {
    case construction
    case manufacturing
    case energy
    case mining
    case office
    case logisticsWarehouse = "logistics_warehouse"
    case chemicalLaboratory = "chemical_laboratory"
    case healthcare
    case foodProduction = "food_production"
    case agricultureLivestock = "agriculture_livestock"
    case retail
    case municipalFieldServices = "municipal_field_services"
    case education
    case hospitality
    case other

    var id: String { rawValue }

    var analysisSectorID: AnalysisSectorID? {
        AnalysisSectorID(rawValue: rawValue)
    }

    var label: String {
        analysisSectorID?.label() ?? RDLocalization.string("onboarding.onboarding.v2.state.diger.51be7c29", table: .onboarding, fallback: "Diğer")
    }

    var sub: String {
        analysisSectorID?.subtitle ?? RDLocalization.string("onboarding.onboarding.v2.state.tanimlanmamis.veya.farkli.sektorler.6eef1c31", table: .onboarding, fallback: "Tanımlanmamış veya farklı sektörler")
    }

    var icon: String {
        analysisSectorID?.icon ?? "ellipsis"
    }
}

enum OBFrequency: String, CaseIterable, Identifiable {
    case one = "1"
    case twoToFive = "2-5"
    case sixToFifteen = "6-15"
    case fifteenPlus = "15+"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .one: return RDLocalization.string("onboarding.onboarding.v2.state.tek.odak.30bd054c", table: .onboarding, fallback: "Tek odak")
        case .twoToFive: return RDLocalization.string("onboarding.onboarding.v2.state.standart.yogunluk.5f3fb070", table: .onboarding, fallback: "Standart yoğunluk")
        case .sixToFifteen: return RDLocalization.string("onboarding.onboarding.v2.state.yuksek.tempo.ea428772", table: .onboarding, fallback: "Yüksek tempo")
        case .fifteenPlus: return RDLocalization.string("onboarding.onboarding.v2.state.yogun.saha.9c5b0a16", table: .onboarding, fallback: "Yoğun saha")
        }
    }

    var sub: String {
        switch self {
        case .one: return RDLocalization.string("onboarding.onboarding.v2.state.bir.isyerine.derin.denetim.ea8a60da", table: .onboarding, fallback: "Bir işyerine derin denetim")
        case .twoToFive: return RDLocalization.string("onboarding.onboarding.v2.state.birden.cok.osgb.sozlesmesi.4ffd6ac0", table: .onboarding, fallback: "Birden çok OSGB sözleşmesi")
        case .sixToFifteen: return RDLocalization.string("onboarding.onboarding.v2.state.surekli.saha.rotasyonu.77f079c0", table: .onboarding, fallback: "Sürekli saha rotasyonu")
        case .fifteenPlus: return RDLocalization.string("onboarding.onboarding.v2.state.yogun.osgb.endustri.grubu.497fbbfb", table: .onboarding, fallback: "Yoğun OSGB / endüstri grubu")
        }
    }
}

enum OBPlan: String, Codable, Equatable {
    case yearly, monthly

    var label: String {
        switch self {
        case .yearly: return RDLocalization.string("onboarding.onboarding.v2.state.yillik.bb3f3195", table: .onboarding, fallback: "Yıllık")
        case .monthly: return RDLocalization.string("onboarding.onboarding.v2.state.aylik.8ab1efeb", table: .onboarding, fallback: "Aylık")
        }
    }
}

enum OBTrialPriceCopy {
    static let loadingPrice = RDLocalization.string("onboarding.onboarding.v2.state.app.store.fiyati.yukleniyor.b089c458", table: .onboarding, fallback: "App Store fiyatı yükleniyor")
    static let unavailablePrice = RDLocalization.string("onboarding.onboarding.v2.state.fiyat.alinamadi.e680a4ea", table: .onboarding, fallback: "Fiyat alınamadı")
    static let yearlyFineprint = RDLocalization.string("onboarding.onboarding.v2.state.fiyat.app.store.uzerinden.yuklenecek.2dfc04c7", table: .onboarding, fallback: "Fiyat App Store üzerinden yüklenecek.")
}

@MainActor
final class OnboardingV2State: ObservableObject {
    let appLanguage: RDLanguage
    @Published var step: Int = 0
    @Published var certificate: OBCertificate?
    @Published var hazards: Set<OBHazardClass> = []
    @Published var professionalRole: OBProfessionalRole?
    @Published var safetyProfileID: RDSafetyProfileID?
    @Published var sectors: [OBSector] = []
    @Published var frequency: OBFrequency?
    @Published var selectedPlan: OBPlan = .yearly

    init(
        step: Int = 0,
        appLanguage: RDLanguage = .current,
        safetyProfileID: RDSafetyProfileID? = nil
    ) {
        self.step = step
        self.appLanguage = appLanguage
        self.safetyProfileID = safetyProfileID
    }

    let totalQuestionSteps: Int = 5

    var primarySectorLabel: String {
        sectors.first?.label ?? RDLocalization.string("onboarding.onboarding.v2.state.insaat.00734e7a", table: .onboarding, fallback: "İnşaat")
    }

    var hazardsLabel: String {
        if hazards.isEmpty { return RDLocalization.string("onboarding.onboarding.v2.state.cok.tehlikeli.ea365d68", table: .onboarding, fallback: "Çok Tehlikeli") }
        return hazards.map { $0.label }.joined(separator: " · ")
    }

    var certificateLabel: String { certificate?.label ?? RDLocalization.string("onboarding.onboarding.v2.state.a.sinifi.ab0600aa", table: .onboarding, fallback: "A Sınıfı") }

    func makeAnswersDraft() -> OnboardingAnswersDraft {
        let orderedHazards = OBHazardClass.allCases.filter { hazards.contains($0) }
        return OnboardingAnswersDraft(
            certificateClass: appLanguage == .turkish ? certificate.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.label)
            } : nil,
            hazardClasses: appLanguage == .turkish ? orderedHazards.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.label)
            } : [],
            professionalRole: professionalRole.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.label)
            },
            safetyProfileID: safetyProfileID?.rawValue,
            appLanguage: appLanguage.rawValue,
            sectors: sectors.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.label)
            },
            auditFrequency: frequency.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.title)
            },
            selectedPlan: OnboardingAnswerChoice(value: selectedPlan.rawValue, label: selectedPlan.label)
        )
    }

    func toggleHazard(_ h: OBHazardClass) {
        if hazards.contains(h) { hazards.remove(h) } else { hazards.insert(h) }
    }

    @discardableResult
    func toggleSector(_ s: OBSector) -> Bool {
        if let i = sectors.firstIndex(of: s) {
            sectors.remove(at: i)
            return true
        }
        sectors.append(s)
        return true
    }

    func next() { withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step += 1 } }
    func back() { withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = max(0, step - 1) } }
    func goTo(_ i: Int) { withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = i } }
}

extension OnboardingV2State {
    static func previewSample(step: Int = 0) -> OnboardingV2State {
        let state = OnboardingV2State(step: step, appLanguage: .turkish)
        state.certificate = .A
        state.hazards = [.critical, .high]
        state.sectors = [.construction, .manufacturing]
        state.frequency = .sixToFifteen
        state.selectedPlan = .yearly
        return state
    }
}

enum OBHaptic {
    static func soft() {
        let g = UIImpactFeedbackGenerator(style: .soft); g.impactOccurred(intensity: 0.5)
    }
    static func light() {
        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
    }
    static func medium() {
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
    }
    static func success() {
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.success)
    }
}
