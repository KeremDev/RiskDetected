import Foundation

/// Canonical active-analysis sector IDs shared with the Supabase backend allowlist.
enum AnalysisSectorID: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case general
    case construction
    case manufacturing
    case mining
    case energy
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

    var id: String { rawValue }

    static let canonicalIDs: [String] = allCases.map(\.rawValue).sorted()

    static let activeAnalysisPromptVersion = "active-sector-v1"

    /// Sectors shown during onboarding (profile signal). `general` is analysis-only.
    static var onboardingSelectableCases: [AnalysisSectorID] {
        allCases.filter { $0 != .general }
    }

    static func fromOnboardingValue(_ raw: String) -> AnalysisSectorID? {
        AnalysisSectorID(rawValue: raw)
    }

    func label(language: RDLanguage = .turkish) -> String {
        switch language {
        case .turkish:
            switch self {
            case .general: return "Genel İSG"
            case .construction: return "İnşaat"
            case .manufacturing: return "İmalat / Fabrika"
            case .mining: return "Maden"
            case .energy: return "Enerji"
            case .office: return "Ofis"
            case .logisticsWarehouse: return "Depo / Lojistik"
            case .chemicalLaboratory: return "Kimya / Laboratuvar"
            case .healthcare: return "Sağlık / Hastane"
            case .foodProduction: return "Gıda Üretimi"
            case .agricultureLivestock: return "Tarım / Hayvancılık"
            case .retail: return "Perakende / Mağaza"
            case .municipalFieldServices: return "Belediye / Kamu Saha İşleri"
            case .education: return "Eğitim Kurumu"
            case .hospitality: return "Otel / Konaklama"
            }
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Sektör bağlamı net olmayan genel saha taraması"
        case .construction: return "Şantiye, yapı, hafriyat"
        case .manufacturing: return "Fabrika, atölye, üretim hattı"
        case .mining: return "Yeraltı, açık ocak, taşocağı"
        case .energy: return "Santral, rafineri, enerji tesisleri"
        case .office: return "Banka, AVM, idari bina"
        case .logisticsWarehouse: return "Depo, lojistik, yükleme alanları"
        case .chemicalLaboratory: return "Kimyasal işlem, laboratuvar"
        case .healthcare: return "Hastane, klinik, sağlık tesisi"
        case .foodProduction: return "Gıda üretimi, mutfak, hijyen alanları"
        case .agricultureLivestock: return "Tarım, hayvancılık, açık alan"
        case .retail: return "Mağaza, perakende, müşteri alanı"
        case .municipalFieldServices: return "Belediye, kamu saha işleri"
        case .education: return "Okul, üniversite, atölye"
        case .hospitality: return "Otel, konaklama, misafir alanları"
        }
    }

    var icon: String {
        switch self {
        case .general: return "shield.lefthalf.filled"
        case .construction: return "hammer.fill"
        case .manufacturing: return "gearshape.2.fill"
        case .mining: return "mountain.2.fill"
        case .energy: return "bolt.fill"
        case .office: return "building.2.fill"
        case .logisticsWarehouse: return "shippingbox.fill"
        case .chemicalLaboratory: return "flask.fill"
        case .healthcare: return "cross.case.fill"
        case .foodProduction: return "fork.knife"
        case .agricultureLivestock: return "leaf.fill"
        case .retail: return "bag.fill"
        case .municipalFieldServices: return "signpost.right.fill"
        case .education: return "graduationcap.fill"
        case .hospitality: return "bed.double.fill"
        }
    }

    var accessibilityChipID: String {
        "analysis_sector_chip_\(rawValue)"
    }

    var sortOrder: Int {
        switch self {
        case .general: return 0
        case .construction: return 10
        case .manufacturing: return 20
        case .mining: return 30
        case .energy: return 40
        case .office: return 50
        case .logisticsWarehouse: return 60
        case .chemicalLaboratory: return 70
        case .healthcare: return 80
        case .foodProduction: return 90
        case .agricultureLivestock: return 100
        case .retail: return 110
        case .municipalFieldServices: return 120
        case .education: return 130
        case .hospitality: return 140
        }
    }
}

enum AnalysisSectorBadge: String, Hashable, Sendable {
    case recommended
    case lastUsed

    var label: String {
        switch self {
        case .recommended: return "Önerilen"
        case .lastUsed: return "Son kullanılan"
        }
    }

    /// Compact chip badge copy for the 3-column inline grid.
    var compactLabel: String {
        switch self {
        case .recommended: return "Önerilen"
        case .lastUsed: return "Son"
        }
    }
}

struct AnalysisSectorPickerItem: Identifiable, Hashable, Sendable {
    let sector: AnalysisSectorID
    let badges: Set<AnalysisSectorBadge>

    var id: String { sector.id }
}

enum AnalysisSectorCatalog {
    static func validateSyncWithBackend() {
        #if DEBUG
        let expected: Set<String> = [
            "general",
            "construction",
            "manufacturing",
            "mining",
            "energy",
            "office",
            "logistics_warehouse",
            "chemical_laboratory",
            "healthcare",
            "food_production",
            "agriculture_livestock",
            "retail",
            "municipal_field_services",
            "education",
            "hospitality",
        ]
        assert(Set(AnalysisSectorID.canonicalIDs) == expected)
        #endif
    }
}

enum AnalysisSectorPreferences {
    private static let lastUsedKey = "rd.analysis_sector.last_used"

    static func lastUsedSector() -> AnalysisSectorID? {
        guard let raw = UserDefaults.standard.string(forKey: lastUsedKey) else { return nil }
        return AnalysisSectorID(rawValue: raw)
    }

    static func recordLastUsed(_ sector: AnalysisSectorID) {
        UserDefaults.standard.set(sector.rawValue, forKey: lastUsedKey)
    }

    static func onboardingSectors(from answers: OnboardingAnswersDraft?) -> [AnalysisSectorID] {
        guard let answers else { return [] }
        var seen = Set<String>()
        return answers.sectors.compactMap { choice in
            guard seen.insert(choice.value).inserted else { return nil }
            return AnalysisSectorID.fromOnboardingValue(choice.value)
        }
    }

    static func pickerItems(
        onboardingSectors: [AnalysisSectorID],
        lastUsed: AnalysisSectorID?,
        recommended: AnalysisSectorID? = nil
    ) -> [AnalysisSectorPickerItem] {
        AnalysisSectorCatalog.validateSyncWithBackend()

        var items: [AnalysisSectorPickerItem] = []
        var seen = Set<AnalysisSectorID>()

        func append(_ sector: AnalysisSectorID, badges: Set<AnalysisSectorBadge> = []) {
            guard seen.insert(sector).inserted else { return }
            items.append(AnalysisSectorPickerItem(sector: sector, badges: badges))
        }

        if let recommended, recommended != .general {
            append(recommended, badges: [.recommended])
        }

        for sector in onboardingSectors where sector != .general {
            append(sector)
        }

        if let lastUsed,
           lastUsed != .general,
           !onboardingSectors.contains(lastUsed) {
            append(lastUsed, badges: [.lastUsed])
        }

        append(.general)

        for sector in AnalysisSectorID.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) where sector != .general {
            append(sector)
        }

        return items
    }
}
