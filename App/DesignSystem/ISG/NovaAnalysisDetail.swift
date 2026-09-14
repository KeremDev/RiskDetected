import Foundation

/// The four parts of a finished analysis, in the order the product shows them.
enum NovaAnalysisSectionKind: String, CaseIterable, Identifiable, Equatable {
    case riskAnalysis = "risk_analysis"
    case expertRecommendations = "expert_recommendations"
    case trainingRecommendations = "training_recommendations"
    case approvedNotebook = "approved_notebook"
    var id: String { rawValue }

    /// Only the risk analysis arrives scored. Everything else is the expert's
    /// judgement, so nothing in those sections may be filed with a mapped band.
    var isScored: Bool { self == .riskAnalysis }
    /// Which sections may be turned into a record on a company.
    var isFileable: Bool { self != .approvedNotebook }
}

/// One row of a section, reduced to what the screen and the filing step need.
struct NovaAnalysisItem: Equatable, Identifiable {
    let id: UUID
    let ordinal: Int
    let title: String
    let category: String?
    let body: String
    let measure: String?
    let references: String?
    /// The band the expert's own method produced, or nil when the section is
    /// unscored. "unknown" arrives as a band that no mapping accepts.
    let band: String?
    let score: Double?
    var isUnreadableBand: Bool {
        guard let band else { return false }
        return !["low", "medium", "high", "critical"].contains(band)
    }
}

struct NovaAnalysisSection: Equatable, Identifiable {
    let kind: NovaAnalysisSectionKind
    let items: [NovaAnalysisItem]
    /// The server says the account only sees a teaser of this section.
    let isTeaser: Bool
    var id: String { kind.rawValue }
}

/// Everything the detail screen shows about one analysis.
struct NovaAnalysisDetailData: Equatable {
    let analysisID: UUID
    let title: String
    let createdOn: String
    let methodLabel: String
    let method: NovaRiskMethod
    var companyID: UUID?
    var companyName: String?
    let sections: [NovaAnalysisSection]
    /// The server said the section projection is not available for this
    /// analysis. The screen says so instead of showing four empty sections.
    let isProjectionMissing: Bool
    /// How many photos the analysis was run on. The pictures themselves are
    /// fetched separately so this model stays free of image data.
    var photoCount: Int = 0
    /// The sector the analysis actually ran under, when one was chosen.
    var sectorLabel: String?
    /// The focuses the analysis ran with, in the order they were chosen.
    var focusLabels: [String] = []

    func section(_ kind: NovaAnalysisSectionKind) -> NovaAnalysisSection? {
        sections.first { $0.kind == kind }
    }
}

/// One analysis in the account's list, with the labels that tell it apart.
struct NovaAnalysisSummary: Equatable, Identifiable {
    let id: UUID
    let title: String
    let createdOn: String
    let companyName: String?
    let findingCount: Int?
    var photoCount: Int = 0
    var sectorLabel: String?
    /// The worst band the analysis produced under the expert's own method, or
    /// nil when the analysis produced no band at all.
    var highestBand: String?
    var isUnassigned: Bool { companyName == nil }
}

/// What the expert changed on one scored finding. Every field is optional: an
/// absent field is one the form did not touch.
struct NovaAnalysisFindingEdit: Equatable {
    let analysisID: UUID
    let findingID: UUID
    var title: String?
    var category: String?
    var body: String?
    var measure: String?
    var references: String?
    var score = NovaRiskScoreInput()
}

/// One item on its way to becoming a record on a company.
struct NovaAnalysisFileRequest: Equatable {
    let item: NovaAnalysisItem
    let section: NovaAnalysisSectionKind
    let workplaceID: UUID
    let recordKind: NovaNonconformityRecordKind
    /// Set when the expert chose it. For a scored finding with a readable band
    /// this stays nil and the server maps the band itself.
    let severity: NovaNonconformitySeverity?
}

/// What the expert said about one item. `none` withdraws an earlier answer.
enum NovaAnalysisReaction: String, Equatable {
    case none, like, dislike
}

enum NovaAnalysisReportFormat: String, CaseIterable, Identifiable, Equatable {
    case pdf, excel
    var id: String { rawValue }
}

struct NovaAnalysisReportRequest: Equatable {
    let analysisID: UUID
    let format: NovaAnalysisReportFormat
    let method: NovaRiskMethod
    /// The company the report is filed against. Nil keeps it on the account.
    let companyID: UUID?
}
