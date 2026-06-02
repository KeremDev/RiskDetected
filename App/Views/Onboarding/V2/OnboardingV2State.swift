import SwiftUI

enum OBCertificate: String, CaseIterable, Identifiable {
    case A, B, C, doctor, otherHealth
    var id: String { rawValue }

    var label: String {
        switch self {
        case .A: return "A Sınıfı"
        case .B: return "B Sınıfı"
        case .C: return "C Sınıfı"
        case .doctor: return "İşyeri Hekimi"
        case .otherHealth: return "Sağlık personeli"
        }
    }
}

enum OBHazardClass: String, CaseIterable, Identifiable {
    case critical, high, low
    var id: String { rawValue }

    var label: String {
        switch self {
        case .critical: return "Çok Tehlikeli"
        case .high: return "Tehlikeli"
        case .low: return "Az Tehlikeli"
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
    case construction, manufacturing, energy, mining, office, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .construction: return "İnşaat"
        case .manufacturing: return "İmalat"
        case .energy: return "Enerji"
        case .mining: return "Maden"
        case .office: return "Hizmet / Ofis"
        case .other: return "Diğer"
        }
    }

    var sub: String {
        switch self {
        case .construction: return "Şantiye, yapı, hafriyat"
        case .manufacturing: return "Fabrika, atölye, tekstil"
        case .energy: return "Rafineri, santral, kimya"
        case .mining: return "Yeraltı, açık ocak, taşocağı"
        case .office: return "Banka, AVM, perakende"
        case .other: return "Tarım, lojistik, sağlık"
        }
    }

    var icon: String {
        switch self {
        case .construction: return "hammer.fill"
        case .manufacturing: return "gearshape.2.fill"
        case .energy: return "flame.fill"
        case .mining: return "mountain.2.fill"
        case .office: return "building.2.fill"
        case .other: return "ellipsis"
        }
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
        case .one: return "Tek odak"
        case .twoToFive: return "Standart yoğunluk"
        case .sixToFifteen: return "Yüksek tempo"
        case .fifteenPlus: return "Yoğun saha"
        }
    }

    var sub: String {
        switch self {
        case .one: return "Bir işyerine derin denetim"
        case .twoToFive: return "Birden çok OSGB sözleşmesi"
        case .sixToFifteen: return "Sürekli saha rotasyonu"
        case .fifteenPlus: return "Yoğun OSGB / endüstri grubu"
        }
    }
}

enum OBPlan: String, Codable, Equatable {
    case yearly, monthly

    var label: String {
        switch self {
        case .yearly: return "Yıllık"
        case .monthly: return "Aylık"
        }
    }
}

enum OBTrialPriceCopy {
    static let yearlyPrice = "₺1.999,99"
    static let yearlyMonthlyEquivalent = "₺166,67/ay"
    static let monthlyPrice = "₺199,99"
    static let yearlyPaywallLine = "7 gün ücretsiz, sonra ₺1.999,99 (₺166,67/ay)"
    static let monthlyPaywallLine = "₺199,99/ay — istediğin zaman iptal"
    static let yearlyFineprint = "Yıllık yalnızca ₺1.999,99 (₺166,67/ay)"
    static let monthlyRenewalLine = "₺199,99 otomatik yenilenir. İstediğin zaman iptal edebilirsin."
}

@MainActor
final class OnboardingV2State: ObservableObject {
    @Published var step: Int = 0
    @Published var certificate: OBCertificate?
    @Published var hazards: Set<OBHazardClass> = []
    @Published var sectors: [OBSector] = []
    @Published var frequency: OBFrequency?
    @Published var selectedPlan: OBPlan = .yearly

    init(step: Int = 0) {
        self.step = step
    }

    let totalQuestionSteps: Int = 5

    var primarySectorLabel: String {
        sectors.first?.label ?? "İnşaat"
    }

    var hazardsLabel: String {
        if hazards.isEmpty { return "Çok Tehlikeli" }
        return hazards.map { $0.label }.joined(separator: " · ")
    }

    var certificateLabel: String { certificate?.label ?? "A Sınıfı" }

    func makeAnswersDraft() -> OnboardingAnswersDraft {
        let orderedHazards = OBHazardClass.allCases.filter { hazards.contains($0) }
        return OnboardingAnswersDraft(
            certificateClass: certificate.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.label)
            },
            hazardClasses: orderedHazards.map {
                OnboardingAnswerChoice(value: $0.rawValue, label: $0.label)
            },
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

    static let maxSectorSelection = 2

    @discardableResult
    func toggleSector(_ s: OBSector) -> Bool {
        if let i = sectors.firstIndex(of: s) {
            sectors.remove(at: i)
            return true
        }
        guard sectors.count < Self.maxSectorSelection else { return false }
        sectors.append(s)
        return true
    }

    func next() { withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step += 1 } }
    func back() { withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = max(0, step - 1) } }
    func goTo(_ i: Int) { withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) { step = i } }
}

extension OnboardingV2State {
    static func previewSample(step: Int = 0) -> OnboardingV2State {
        let state = OnboardingV2State(step: step)
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
