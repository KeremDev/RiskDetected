import Foundation

struct RDAnalysisLocalizationRequest: Encodable, Equatable, Sendable {
    let outputLanguage: RDAppLanguage
    let outputLocale: RDContentLocale
    let workJurisdictionCountry: RDWorkJurisdictionCountry
    let workJurisdictionRegion: String?
    let safetyProfileID: RDSafetyProfileID
    let safetyProfileVersion: Int
    let method: RDRiskMethod

    enum CodingKeys: String, CodingKey {
        case outputLanguage = "output_language"
        case outputLocale = "output_locale"
        case workJurisdictionCountry = "work_jurisdiction_country"
        case workJurisdictionRegion = "work_jurisdiction_region"
        case safetyProfileID = "safety_profile_id"
        case safetyProfileVersion = "safety_profile_version"
        case method
    }
}

extension RiskMethodWire {
    var localizationMethod: RDRiskMethod {
        switch self {
        case .fineKinney: return .fineKinney
        case .matrix5x5: return .matrix5x5
        }
    }
}

extension RDRiskMethod {
    var wireMethod: RiskMethodWire {
        switch self {
        case .fineKinney: return .fineKinney
        case .matrix5x5: return .matrix5x5
        }
    }
}
