import Foundation

extension RDSafetyProfileID: Identifiable {
    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .turkeyCurrentV1:
            return localizedSafetyText("safety.profile.tr.title", fallback: "Türkiye")
        case .englishInternationalGenericV1:
            return localizedSafetyText("safety.profile.intl.title", fallback: "Uluslararası")
        case .englishUnitedKingdomGenericV1:
            return localizedSafetyText("safety.profile.gb.title", fallback: "Birleşik Krallık")
        case .englishUnitedStatesGenericV1:
            return localizedSafetyText("safety.profile.us.title", fallback: "Amerika Birleşik Devletleri")
        case .englishAustraliaGenericV1:
            return localizedSafetyText("safety.profile.au.title", fallback: "Avustralya")
        case .englishCanadaGenericV1:
            return localizedSafetyText("safety.profile.ca.title", fallback: "Kanada")
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .turkeyCurrentV1:
            return localizedSafetyText(
                "safety.profile.tr.subtitle",
                fallback: "Mevcut Türkiye İSG terminolojisi ve ürün davranışı."
            )
        case .englishInternationalGenericV1:
            return localizedSafetyText(
                "safety.profile.intl.subtitle",
                fallback: "Bölgeler arası çalışmalar için tarafsız iş güvenliği terminolojisi."
            )
        case .englishUnitedKingdomGenericV1:
            return localizedSafetyText(
                "safety.profile.gb.subtitle",
                fallback: "Yasal uyumluluk iddiası içermeyen Birleşik Krallık iş sağlığı ve güvenliği terminolojisi."
            )
        case .englishUnitedStatesGenericV1:
            return localizedSafetyText(
                "safety.profile.us.subtitle",
                fallback: "Yasal uyumluluk iddiası içermeyen ABD iş güvenliği terminolojisi."
            )
        case .englishAustraliaGenericV1:
            return localizedSafetyText(
                "safety.profile.au.subtitle",
                fallback: "Yasal uyumluluk iddiası içermeyen Avustralya iş sağlığı ve güvenliği terminolojisi."
            )
        case .englishCanadaGenericV1:
            return localizedSafetyText(
                "safety.profile.ca.subtitle",
                fallback: "Kanada çapında uyumluluk iddiası içermeyen iş sağlığı ve güvenliği terminolojisi."
            )
        }
    }

    private func localizedSafetyText(_ key: String, fallback: String) -> String {
        RDLocalization.string(
            key,
            table: .safetyTerminology,
            fallback: fallback
        )
    }

    var icon: String {
        switch self {
        case .turkeyCurrentV1: return "flag.fill"
        case .englishInternationalGenericV1: return "globe"
        case .englishUnitedKingdomGenericV1: return "building.columns.fill"
        case .englishUnitedStatesGenericV1: return "shield.lefthalf.filled"
        case .englishAustraliaGenericV1: return "sun.max.fill"
        case .englishCanadaGenericV1: return "leaf.fill"
        }
    }

    static let englishSelectionCases: [RDSafetyProfileID] = [
        .englishInternationalGenericV1,
        .englishUnitedKingdomGenericV1,
        .englishUnitedStatesGenericV1,
        .englishAustraliaGenericV1,
        .englishCanadaGenericV1,
    ]
}
