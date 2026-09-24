import Foundation

/// The app language is owned by iOS. RiskDetected never writes
/// `AppleLanguages` and does not replace `Bundle.main`.
enum RDLanguage: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case turkish = "tr"
    case english = "en"

    static let supportedCases: [RDLanguage] = [.turkish, .english]

    static var current: RDLanguage {
        guard RDGlobalLocalizationBuildGate.isEnabled else {
            return .turkish
        }
        return native
    }

    static var native: RDLanguage {
        let preferred = Bundle.main.preferredLocalizations.first?
            .lowercased()
            .split(separator: "-")
            .first
            .map(String.init)
        return RDLanguage(rawValue: preferred ?? "") ?? .turkish
    }

    var id: String { rawValue }

    var appLanguage: RDAppLanguage {
        switch self {
        case .turkish: return .turkish
        case .english: return .english
        }
    }

    var title: String {
        switch self {
        case .turkish: return RDLocalization.string("localizable.rdlocalization.turkce.423754d7", table: .localizable, fallback: "Türkçe")
        case .english: return RDLocalization.string("localizable.rdlocalization.english.919b0740", table: .localizable, fallback: "İngilizce")
        }
    }

    var subtitle: String {
        switch self {
        case .turkish: return RDLocalization.string("localizable.rdlocalization.uygulama.dili.ios.ayarlari.tarafindan.yonetilir.5fd1ab01", table: .localizable, fallback: "Uygulama dili iOS Ayarları tarafından yönetilir.")
        case .english: return RDLocalization.string("localizable.rdlocalization.the.app.language.is.managed.in.ios.settings.795ec9dd", table: .localizable, fallback: "Uygulama dili iOS Ayarlarında yönetilir.")
        }
    }

    var icon: String { "character.bubble" }

    var localeIdentifier: String {
        switch self {
        case .turkish: return RDLocalization.string("localizable.rdlocalization.tr.tr.94f9cbc3", table: .localizable, fallback: "tr_TR")
        case .english: return "en_001"
        }
    }

    var locale: Locale { Locale(identifier: localeIdentifier) }
}

typealias RDLanguagePreference = RDLanguage

/// Professional Progress English copy contains safety-sensitive terminology.
/// Keep the English surface unavailable until both native-language and safety
/// reviewers have explicitly approved the catalog for shipping.
enum RDProfessionalProgressLocalizationReview {
    static let englishShippingApproved = false

    static var isAvailable: Bool {
        RDLanguage.current == .turkish || englishShippingApproved
    }
}

enum RDLocalizationTable: String, CaseIterable, Sendable {
    case localizable = "Localizable"
    case auth = "Auth"
    case onboarding = "Onboarding"
    case paywall = "Paywall"
    case analysis = "Analysis"
    case reports = "Reports"
    case notifications = "Notifications"
    case professionalProgress = "ProfessionalProgress"
    case legal = "Legal"
    case safetyTerminology = "SafetyTerminology"
}

enum RDLocalizedKey: String {
    case reportCreateTitle = "reports.create.title"
    case reportLanguageSection = "reports.language.section"
    case reportLanguageTurkishSubtitle = "reports.language.turkish.subtitle"
    case reportLanguageFutureNote = "reports.language.future.note"
    case standardPDFTitle = "reports.pdf.standard.title"
    case standardPDFSubtitle = "reports.pdf.standard.subtitle"
    case riskAnalysisPDFTitle = "reports.pdf.risk_analysis.title"
    case riskAnalysisPDFSubtitle = "reports.pdf.risk_analysis.subtitle"
    case standardReportHeader = "reports.pdf.standard.header"
    case riskAnalysisReportHeader = "reports.pdf.risk_analysis.header"
    case findingDetailsHeader = "reports.pdf.finding_details.header"
    case riskAnalysisTableHeader = "reports.pdf.risk_table.header"
}

struct RDLocalization {
    static let shared = RDLocalization()

    static func uppercased(_ value: String) -> String {
        let locale = RDLanguage.current == .turkish
            ? Locale(identifier: "tr_TR")
            : Locale(identifier: "en_US_POSIX")
        return value.uppercased(with: locale)
    }

    /// Native bundle lookup with an explicit source-language fallback.
    /// Shipping parity is enforced by `scripts/localization_catalog_tests.mjs`.
    static func string(
        _ key: String,
        table: RDLocalizationTable = .localizable,
        fallback: String,
        language: RDLanguage? = nil
    ) -> String {
        let bundle = lookupBundle(for: language)
        let value = bundle.localizedString(
            forKey: key,
            value: nil,
            table: table.rawValue
        )
        guard value != key else {
            #if DEBUG
            // The marker's own key can be missing too (a bundle without the catalog); never recurse on it.
            guard key != "localizable.rdlocalization.missing.1.b9a12a72" else { return fallback }
            return RDLocalization.format("localizable.rdlocalization.missing.1.b9a12a72", table: .localizable, fallback: "⟦EKSİK:%1$@⟧", arguments: [String(describing: key)])
            #else
            return fallback
            #endif
        }
        return value
    }

    static func format(
        _ key: String,
        table: RDLocalizationTable = .localizable,
        fallback: String,
        arguments: [CVarArg],
        language: RDLanguage? = nil
    ) -> String {
        let template = string(
            key,
            table: table,
            fallback: fallback,
            language: language
        )
        let locale = effectiveLanguage(for: language).locale
        return String(format: template, locale: locale, arguments: arguments)
    }

    static func plural(
        _ key: String,
        table: RDLocalizationTable = .localizable,
        value: Int,
        fallbackOne: String,
        fallbackOther: String,
        language: RDLanguage? = nil
    ) -> String {
        let effectiveLanguage = effectiveLanguage(for: language)
        let bundle = lookupBundle(for: language)
        let template = bundle.localizedString(
            forKey: key,
            value: nil,
            table: table.rawValue
        )
        guard template != key else {
            #if DEBUG
            return format(
                "localizable.rdlocalization.missing.1.b9a12a72",
                table: .localizable,
                fallback: "⟦EKSİK:%1$@⟧",
                arguments: [key]
            )
            #else
            return String(
                format: value == 1 ? fallbackOne : fallbackOther,
                locale: effectiveLanguage.locale,
                arguments: [value]
            )
            #endif
        }
        return String.localizedStringWithFormat(template, value)
    }

    func text(_ key: RDLocalizedKey, language: RDLanguage = .current) -> String {
        Self.string(
            key.rawValue,
            table: .reports,
            fallback: Self.reportFallbacks[key] ?? key.rawValue,
            language: language
        )
    }

    private static func effectiveLanguage(
        for requestedLanguage: RDLanguage?
    ) -> RDLanguage {
        guard RDGlobalLocalizationBuildGate.isEnabled else {
            return .turkish
        }
        return requestedLanguage ?? RDLanguage.current
    }

    private static func lookupBundle(
        for requestedLanguage: RDLanguage?
    ) -> Bundle {
        let effectiveLanguage = effectiveLanguage(for: requestedLanguage)
        if requestedLanguage != nil || !RDGlobalLocalizationBuildGate.isEnabled {
            return bundle(for: effectiveLanguage) ?? .main
        }
        return .main
    }

    private static func bundle(for language: RDLanguage) -> Bundle? {
        guard
            let path = Bundle.main.path(
                forResource: language.rawValue,
                ofType: "lproj"
            )
        else {
            return nil
        }
        return Bundle(path: path)
    }

    private static let reportFallbacks: [RDLocalizedKey: String] = [
        .reportCreateTitle: "Rapor Oluştur",
        .reportLanguageSection: "RAPOR DİLİ",
        .reportLanguageTurkishSubtitle: "PDF ve Excel çıktıları Türkçe hazırlanır.",
        .reportLanguageFutureNote: "Rapor dili analiz kaydının diliyle aynıdır.",
        .standardPDFTitle: "Standart PDF",
        .standardPDFSubtitle: "RiskDetected şablonu ile hızlı saha raporu.",
        .riskAnalysisPDFTitle: "Detaylı risk analizi",
        .riskAnalysisPDFSubtitle: "Fine-Kinney veya 5×5 metoduna göre denetim çıktısı.",
        .standardReportHeader: "SAHA TARAMA RAPORU",
        .riskAnalysisReportHeader: "İŞ GÜVENLİĞİ RİSK ANALİZİ",
        .findingDetailsHeader: "BULGU DETAYLARI",
        .riskAnalysisTableHeader: "RİSK ANALİZİ TABLOSU",
    ]
}

struct RDReportLocalization {
    let language: RDLanguage

    init(language: RDLanguage = .turkish) {
        self.language = language
    }

    var locale: Locale { language.locale }

    func text(_ key: RDLocalizedKey) -> String {
        RDLocalization.shared.text(key, language: language)
    }
}
