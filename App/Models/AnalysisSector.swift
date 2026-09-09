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

    static let activeAnalysisPromptVersion = "sector-profile-v2"

    /// Sectors shown during onboarding (profile signal). `general` is analysis-only.
    static var onboardingSelectableCases: [AnalysisSectorID] {
        allCases.filter { $0 != .general }
    }

    static func fromOnboardingValue(_ raw: String) -> AnalysisSectorID? {
        AnalysisSectorID(rawValue: raw)
    }

    func label(language: RDLanguage = .current) -> String {
        switch language {
        case .turkish:
            switch self {
            case .general: return RDLocalization.string("analysis.analysis.sector.genel.isg.23c52d29", table: .analysis, fallback: "Genel İSG")
            case .construction: return RDLocalization.string("analysis.analysis.sector.insaat.d202ed82", table: .analysis, fallback: "İnşaat")
            case .manufacturing: return RDLocalization.string("analysis.analysis.sector.imalat.fabrika.edfbcadc", table: .analysis, fallback: "İmalat / Fabrika")
            case .mining: return RDLocalization.string("analysis.analysis.sector.maden.87eb5434", table: .analysis, fallback: "Maden")
            case .energy: return RDLocalization.string("analysis.analysis.sector.enerji.4d4a959b", table: .analysis, fallback: "Enerji")
            case .office: return RDLocalization.string("analysis.analysis.sector.ofis.e6332822", table: .analysis, fallback: "Ofis")
            case .logisticsWarehouse: return RDLocalization.string("analysis.analysis.sector.depo.lojistik.73ea166e", table: .analysis, fallback: "Depo / Lojistik")
            case .chemicalLaboratory: return RDLocalization.string("analysis.analysis.sector.kimya.laboratuvar.ee199171", table: .analysis, fallback: "Kimya / Laboratuvar")
            case .healthcare: return RDLocalization.string("analysis.analysis.sector.saglik.hastane.8ba8ae32", table: .analysis, fallback: "Sağlık / Hastane")
            case .foodProduction: return RDLocalization.string("analysis.analysis.sector.gida.uretimi.d021b3dd", table: .analysis, fallback: "Gıda Üretimi")
            case .agricultureLivestock: return RDLocalization.string("analysis.analysis.sector.tarim.hayvancilik.e1cc42ab", table: .analysis, fallback: "Tarım / Hayvancılık")
            case .retail: return RDLocalization.string("analysis.analysis.sector.perakende.magaza.36c2c14a", table: .analysis, fallback: "Perakende / Mağaza")
            case .municipalFieldServices: return RDLocalization.string("analysis.analysis.sector.belediye.kamu.saha.isleri.1f419a6e", table: .analysis, fallback: "Belediye / Kamu Saha İşleri")
            case .education: return RDLocalization.string("analysis.analysis.sector.egitim.kurumu.2645201b", table: .analysis, fallback: "Eğitim Kurumu")
            case .hospitality: return RDLocalization.string("analysis.analysis.sector.otel.konaklama.ee928560", table: .analysis, fallback: "Otel / Konaklama")
            }
        case .english:
            switch self {
            case .general: return RDLocalization.string("analysis.analysis.sector.general.safety.323a9be1", table: .analysis, fallback: "Genel güvenlik")
            case .construction: return RDLocalization.string("analysis.analysis.sector.construction.0885ea76", table: .analysis, fallback: "Yapı")
            case .manufacturing: return RDLocalization.string("analysis.analysis.sector.manufacturing.factory.94ff249b", table: .analysis, fallback: "İmalat / Fabrika")
            case .mining: return RDLocalization.string("analysis.analysis.sector.mining.83e0ebbd", table: .analysis, fallback: "madencilik")
            case .energy: return RDLocalization.string("analysis.analysis.sector.energy.63d2863a", table: .analysis, fallback: "Enerji")
            case .office: return RDLocalization.string("analysis.analysis.sector.office.d52e96bf", table: .analysis, fallback: "Ofis")
            case .logisticsWarehouse: return RDLocalization.string("analysis.analysis.sector.warehouse.logistics.fd7f0984", table: .analysis, fallback: "Depo / Lojistik")
            case .chemicalLaboratory: return RDLocalization.string("analysis.analysis.sector.chemical.laboratory.91024d51", table: .analysis, fallback: "Kimya / Laboratuvar")
            case .healthcare: return RDLocalization.string("analysis.analysis.sector.healthcare.hospital.cbfbe937", table: .analysis, fallback: "Sağlık / Hastane")
            case .foodProduction: return RDLocalization.string("analysis.analysis.sector.food.production.8fd609e6", table: .analysis, fallback: "Gıda üretimi")
            case .agricultureLivestock: return RDLocalization.string("analysis.analysis.sector.agriculture.livestock.de4d4a05", table: .analysis, fallback: "Tarım / Hayvancılık")
            case .retail: return RDLocalization.string("analysis.analysis.sector.retail.store.18b90293", table: .analysis, fallback: "Perakende / Mağaza")
            case .municipalFieldServices: return RDLocalization.string("analysis.analysis.sector.municipal.public.field.services.7350b553", table: .analysis, fallback: "Belediye / Kamu saha hizmetleri")
            case .education: return RDLocalization.string("analysis.analysis.sector.education.fd63834d", table: .analysis, fallback: "Eğitim")
            case .hospitality: return RDLocalization.string("analysis.analysis.sector.hotel.hospitality.cde7f6ca", table: .analysis, fallback: "Otel / Konaklama")
            }
        }
    }

    var subtitle: String {
        if RDLanguage.current == .english {
            switch self {
            case .general: return RDLocalization.string("analysis.analysis.sector.general.site.inspection.without.a.specific.secto.7597b0cf", table: .analysis, fallback: "Belirli bir sektör bağlamı olmaksızın genel saha denetimi")
            case .construction: return RDLocalization.string("analysis.analysis.sector.construction.sites.structures.and.earthworks.7a38db83", table: .analysis, fallback: "İnşaat sahaları, yapılar ve hafriyat işleri")
            case .manufacturing: return RDLocalization.string("analysis.analysis.sector.factories.workshops.and.production.lines.f4a5f7d5", table: .analysis, fallback: "Fabrikalar, atölyeler ve üretim hatları")
            case .mining: return RDLocalization.string("analysis.analysis.sector.underground.surface.and.quarry.operations.d77067a3", table: .analysis, fallback: "Yeraltı, yer üstü ve taş ocağı operasyonları")
            case .energy: return RDLocalization.string("analysis.analysis.sector.power.plants.refineries.and.energy.facilities.26dc5afa", table: .analysis, fallback: "Enerji santralleri, rafineriler ve enerji tesisleri")
            case .office: return RDLocalization.string("analysis.analysis.sector.offices.banks.malls.and.administrative.buildings.4b5a2af2", table: .analysis, fallback: "Ofisler, bankalar, alışveriş merkezleri ve idari binalar")
            case .logisticsWarehouse: return RDLocalization.string("analysis.analysis.sector.warehouses.logistics.and.loading.areas.846bb96e", table: .analysis, fallback: "Depolar, lojistik ve yükleme alanları")
            case .chemicalLaboratory: return RDLocalization.string("analysis.analysis.sector.chemical.processes.and.laboratories.34664e78", table: .analysis, fallback: "Kimyasal prosesler ve laboratuvarlar")
            case .healthcare: return RDLocalization.string("analysis.analysis.sector.hospitals.clinics.and.healthcare.facilities.42c39001", table: .analysis, fallback: "Hastaneler, klinikler ve sağlık tesisleri")
            case .foodProduction: return RDLocalization.string("analysis.analysis.sector.food.production.kitchens.and.hygiene.areas.28af7507", table: .analysis, fallback: "Gıda üretimi, mutfaklar ve hijyen alanları")
            case .agricultureLivestock: return RDLocalization.string("analysis.analysis.sector.agriculture.livestock.and.outdoor.work.5f9ba368", table: .analysis, fallback: "Tarım, hayvancılık ve açık havada çalışma")
            case .retail: return RDLocalization.string("analysis.analysis.sector.stores.retail.and.customer.areas.f5b6c157", table: .analysis, fallback: "Mağazalar, perakende ve müşteri alanları")
            case .municipalFieldServices: return RDLocalization.string("analysis.analysis.sector.municipal.and.public.field.services.05566b87", table: .analysis, fallback: "Belediye ve kamu saha hizmetleri")
            case .education: return RDLocalization.string("analysis.analysis.sector.schools.universities.and.workshops.1b9a7960", table: .analysis, fallback: "Okullar, üniversiteler ve atölyeler")
            case .hospitality: return RDLocalization.string("analysis.analysis.sector.hotels.accommodation.and.guest.areas.5387dc5d", table: .analysis, fallback: "Oteller, konaklama ve misafir alanları")
            }
        }
        switch self {
        case .general: return RDLocalization.string("analysis.analysis.sector.sektor.baglami.net.olmayan.genel.saha.taramasi.e57050cb", table: .analysis, fallback: "Sektör bağlamı net olmayan genel saha taraması")
        case .construction: return RDLocalization.string("analysis.analysis.sector.santiye.yapi.hafriyat.d1850901", table: .analysis, fallback: "Şantiye, yapı, hafriyat")
        case .manufacturing: return RDLocalization.string("analysis.analysis.sector.fabrika.atolye.uretim.hatti.2fe0f2ea", table: .analysis, fallback: "Fabrika, atölye, üretim hattı")
        case .mining: return RDLocalization.string("analysis.analysis.sector.yeralti.acik.ocak.tasocagi.206b7a23", table: .analysis, fallback: "Yeraltı, açık ocak, taşocağı")
        case .energy: return RDLocalization.string("analysis.analysis.sector.santral.rafineri.enerji.tesisleri.27902a52", table: .analysis, fallback: "Santral, rafineri, enerji tesisleri")
        case .office: return RDLocalization.string("analysis.analysis.sector.banka.avm.idari.bina.47c81a63", table: .analysis, fallback: "Banka, AVM, idari bina")
        case .logisticsWarehouse: return RDLocalization.string("analysis.analysis.sector.depo.lojistik.yukleme.alanlari.4ec3c322", table: .analysis, fallback: "Depo, lojistik, yükleme alanları")
        case .chemicalLaboratory: return RDLocalization.string("analysis.analysis.sector.kimyasal.islem.laboratuvar.e2dc0d6c", table: .analysis, fallback: "Kimyasal işlem, laboratuvar")
        case .healthcare: return RDLocalization.string("analysis.analysis.sector.hastane.klinik.saglik.tesisi.aee8044f", table: .analysis, fallback: "Hastane, klinik, sağlık tesisi")
        case .foodProduction: return RDLocalization.string("analysis.analysis.sector.gida.uretimi.mutfak.hijyen.alanlari.c7b33ab9", table: .analysis, fallback: "Gıda üretimi, mutfak, hijyen alanları")
        case .agricultureLivestock: return RDLocalization.string("analysis.analysis.sector.tarim.hayvancilik.acik.alan.7f0c34df", table: .analysis, fallback: "Tarım, hayvancılık, açık alan")
        case .retail: return RDLocalization.string("analysis.analysis.sector.magaza.perakende.musteri.alani.b94be9f4", table: .analysis, fallback: "Mağaza, perakende, müşteri alanı")
        case .municipalFieldServices: return RDLocalization.string("analysis.analysis.sector.belediye.kamu.saha.isleri.3b5527ec", table: .analysis, fallback: "Belediye, kamu saha işleri")
        case .education: return RDLocalization.string("analysis.analysis.sector.okul.universite.atolye.c6b52c7b", table: .analysis, fallback: "Okul, üniversite, atölye")
        case .hospitality: return RDLocalization.string("analysis.analysis.sector.otel.konaklama.misafir.alanlari.bfff587f", table: .analysis, fallback: "Otel, konaklama, misafir alanları")
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
        case .recommended: return RDLocalization.string("analysis.analysis.sector.onerilen.f13796a3", table: .analysis, fallback: "Önerilen")
        case .lastUsed: return RDLocalization.string("analysis.analysis.sector.son.kullanilan.e4c2b96c", table: .analysis, fallback: "Son kullanılan")
        }
    }

    /// Compact chip badge copy for the 3-column inline grid.
    var compactLabel: String {
        switch self {
        case .recommended: return RDLocalization.string("analysis.analysis.sector.onerilen.64ee05f3", table: .analysis, fallback: "Önerilen")
        case .lastUsed: return RDLocalization.string("analysis.analysis.sector.son.36d6b5b2", table: .analysis, fallback: "Son")
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

        for sector in AnalysisSectorID.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) where sector != .general {
            append(sector)
        }

        append(.general)

        return items
    }
}
