import Foundation

enum RDLanguage: String, CaseIterable, Identifiable, Codable, Equatable {
    case turkish = "tr"

    static let supportedCases: [RDLanguage] = [.turkish]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .turkish: return "Türkçe"
        }
    }

    var subtitle: String {
        switch self {
        case .turkish: return "Uygulama metinleri Türkçe kalır."
        }
    }

    var icon: String {
        switch self {
        case .turkish: return "textformat"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .turkish: return "tr_TR"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }
}

typealias RDLanguagePreference = RDLanguage

enum RDLocalizedKey: String {
    case reportCreateTitle
    case reportLanguageSection
    case reportLanguageTurkishSubtitle
    case reportLanguageFutureNote
    case standardPDFTitle
    case standardPDFSubtitle
    case riskAnalysisPDFTitle
    case riskAnalysisPDFSubtitle
    case standardReportHeader
    case riskAnalysisReportHeader
    case findingDetailsHeader
    case riskAnalysisTableHeader
}

struct RDLocalization {
    static let shared = RDLocalization()

    private static let turkish: [RDLocalizedKey: String] = [
        .reportCreateTitle: "Rapor Oluştur",
        .reportLanguageSection: "RAPOR DİLİ",
        .reportLanguageTurkishSubtitle: "PDF ve Excel çıktıları Türkçe hazırlanır.",
        .reportLanguageFutureNote: "Çoklu dil geldiğinde rapor dili bu alandan seçilecek.",
        .standardPDFTitle: "Standart PDF",
        .standardPDFSubtitle: "RiskDetected şablonu ile hızlı saha raporu.",
        .riskAnalysisPDFTitle: "Detaylı risk analizi",
        .riskAnalysisPDFSubtitle: "Fine-Kinney veya 5×5 metoduna göre denetim çıktısı.",
        .standardReportHeader: "SAHA TARAMA RAPORU",
        .riskAnalysisReportHeader: "İŞ GÜVENLİĞİ RİSK ANALİZİ",
        .findingDetailsHeader: "BULGU DETAYLARI",
        .riskAnalysisTableHeader: "RİSK ANALİZİ TABLOSU",
    ]

    func text(_ key: RDLocalizedKey, language: RDLanguage = .turkish) -> String {
        switch language {
        case .turkish:
            return Self.turkish[key] ?? key.rawValue
        }
    }
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
