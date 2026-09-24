import Foundation

/// Keeps analysis titles and timestamps quiet and non-repetitive across the
/// list, result and finding-detail screens. Older analyses sometimes persist
/// their display date inside `title`; the server also returns the same value in
/// `createdOn`, so presentation must remove that duplicate rather than expose
/// storage history to the user.
enum NovaAnalysisPresentation {
    private static let trailingStamp = try! NSRegularExpression(
        pattern: #"\s*[·-]?\s*\d{1,2}\s+(?:Oca(?:k)?|Şub(?:at)?|Mar(?:t)?|Nis(?:an)?|May(?:ıs)?|Haz(?:iran)?|Tem(?:muz)?|Ağu(?:stos)?|Eyl(?:ül)?|Eki(?:m)?|Kas(?:ım)?|Ara(?:lık)?)\s+\d{4}(?:\s*[·-]?\s*\d{1,2}:\d{2})?\s*$"#,
        options: [.caseInsensitive]
    )
    private static let trailingNumericStamp = try! NSRegularExpression(
        pattern: #"\s*[·-]?\s*\d{1,2}[./-]\d{1,2}[./-]\d{4}(?:\s*[·-]?\s*\d{1,2}:\d{2})?\s*$"#
    )
    private static let time = try! NSRegularExpression(pattern: #"\s*[·-]?\s*\d{1,2}:\d{2}\s*$"#)

    static func title(_ value: String) -> String {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let withoutNamed = trailingStamp.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        let numericRange = NSRange(withoutNamed.startIndex..<withoutNamed.endIndex, in: withoutNamed)
        let withoutNumeric = trailingNumericStamp.stringByReplacingMatches(in: withoutNamed, range: numericRange, withTemplate: "")
        let cleaned = withoutNumeric.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? value : cleaned
    }

    static func dateOnly(_ value: String) -> String {
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        return time.stringByReplacingMatches(in: value, range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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

/// One factor of a published risk scale, as it is shown next to the product.
/// The label is the scale's own short letter; the value is what was chosen.
struct NovaAnalysisScoreFactor: Equatable, Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

/// What one published method says about one item. Both the number and the band
/// are the server's; nothing here recomputes them.
struct NovaAnalysisScore: Equatable {
    let band: String?
    let value: Double?
    var factors: [NovaAnalysisScoreFactor] = []
    var isUnreadableBand: Bool {
        guard let band else { return false }
        return !["low", "medium", "high", "critical"].contains(band)
    }
}

/// One named control measure carried with an item.
struct NovaAnalysisMeasure: Equatable, Identifiable {
    let id: String
    let title: String
    let text: String
    /// True for a preventive measure, false for a corrective one. Used only to
    /// pick the label tone, never to change what the text says.
    let isPreventive: Bool
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
    var rootCause: String?
    var measures: [NovaAnalysisMeasure] = []
    /// Who a training recommendation is meant for.
    var audience: String?
    var durationLabel: String?
    var durationValue: String?
    var durationNote: String?
    /// Which of the analysis photos this item was read from, one-based exactly
    /// as the analysis records them.
    var photoIndices: [Int] = []
    /// What the expert already answered about this item, as the server has it.
    var reaction: NovaAnalysisReaction = .none
    /// The scores the two published methods produced. An unscored section
    /// carries neither, so nothing can be shown as if it had a band.
    var fineKinney: NovaAnalysisScore?
    var matrix: NovaAnalysisScore?

    func score(_ method: NovaRiskMethod) -> NovaAnalysisScore? {
        method == .fineKinney ? fineKinney : matrix
    }
    func band(_ method: NovaRiskMethod) -> String? { score(method)?.band }
    func value(_ method: NovaRiskMethod) -> Double? { score(method)?.value }
    func isUnreadableBand(_ method: NovaRiskMethod) -> Bool {
        score(method)?.isUnreadableBand ?? false
    }
    /// The tags the card shows instead of repeating the whole record.
    var hasRootCause: Bool { !(rootCause ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasReferences: Bool { !(references ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasPreventive: Bool { measures.contains { $0.isPreventive } }
}

struct NovaAnalysisSection: Equatable, Identifiable {
    let kind: NovaAnalysisSectionKind
    let items: [NovaAnalysisItem]
    /// The server says the account only sees a teaser of this section.
    let isTeaser: Bool
    var id: String { kind.rawValue }

    /// How many items fall in each band under one method. Only the scored
    /// section answers this; the others have nothing to count.
    func distribution(_ method: NovaRiskMethod) -> [(band: String, count: Int)] {
        ["critical", "high", "medium", "low"].map { band in
            (band, items.filter { $0.band(method) == band }.count)
        }
    }
    func highest(_ method: NovaRiskMethod) -> NovaAnalysisItem? {
        items.max { ($0.value(method) ?? -1) < ($1.value(method) ?? -1) }
    }
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
    /// The focus the analysis ran under, as the product names it.
    var focusLabel: String?
    /// The analysis finished and its result is readable. A row that has not
    /// finished is not listed at all, so this is never a guess.
    var isReviewed = false
    /// The day part of the stamp, kept so a week can be counted without
    /// parsing the display string back.
    var createdAt: Date?
    /// Who made it, in an organization; personal analyses are all the account's.
    var createdBy: UUID?
    var isUnassigned: Bool { companyName == nil }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [title, companyName ?? "", sectorLabel ?? "", focusLabel ?? "", createdOn]
            .contains { $0.lowercased().contains(needle) }
    }
}

/// What the list card at the top of Analizlerim counts. Every number is taken
/// from the rows actually loaded, so the caption says so rather than claiming
/// an account total the screen did not read.
struct NovaAnalysisListStats: Equatable {
    let total: Int
    let thisWeek: Int
    let critical: Int
    let findings: Int

    init(total: Int, critical: Int, findings: Int) {
        self.total = max(0, total)
        self.thisWeek = 0
        self.critical = max(0, critical)
        self.findings = max(0, findings)
    }

    init(_ rows: [NovaAnalysisSummary], now: Date = Date()) {
        total = rows.count
        let boundary = now.addingTimeInterval(-7 * 24 * 60 * 60)
        thisWeek = rows.filter { ($0.createdAt ?? .distantPast) >= boundary }.count
        critical = rows.filter { $0.highestBand == "critical" }.count
        findings = rows.reduce(0) { $0 + ($1.findingCount ?? 0) }
    }
}

/// One archived report produced from a photo analysis.
struct NovaAnalysisReportEntry: Equatable, Identifiable {
    let id: UUID
    let title: String
    let fileName: String
    let createdOn: String
    let companyName: String?
    /// "pdf" or "excel", as the archive recorded it.
    let format: String
    let methodLabel: String
    let kindLabel: String
    /// Bytes, when the archive recorded a size.
    let fileSize: Int?
    let analysisID: UUID?
    var createdAt: Date?
    /// Personal archive reports keep their Supabase storage path. Workspace
    /// exports instead point at a filed workspace asset.
    var storagePath: String? = nil
    var mimeType: String? = nil
    var assetID: UUID? = nil
    var downloadBucket: String? = nil
    var downloadPath: String? = nil

    var isSpreadsheet: Bool { format.lowercased().contains("xls") || format.lowercased() == "excel" }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        return [title, fileName, companyName ?? "", kindLabel, createdOn]
            .contains { $0.lowercased().contains(needle) }
    }
}

struct NovaAnalysisReportStats: Equatable {
    let total: Int
    let documents: Int
    let spreadsheets: Int
    let companies: Int

    init(_ rows: [NovaAnalysisReportEntry]) {
        total = rows.count
        spreadsheets = rows.filter(\.isSpreadsheet).count
        documents = total - spreadsheets
        companies = Set(rows.compactMap(\.companyName)).count
    }
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
    var companyID: UUID? = nil
    let item: NovaAnalysisItem
    let section: NovaAnalysisSectionKind
    let workplaceID: UUID?
    let recordKind: NovaNonconformityRecordKind
    /// The band under the method the expert is reading the analysis with. Nil
    /// for every unscored section, and the server maps it only when no
    /// severity was chosen by hand.
    let band: String?
    /// Set when the expert chose it. For a scored finding with a readable band
    /// this stays nil and the server maps the band itself.
    let severity: NovaNonconformitySeverity?
    var sourceMethod: NovaRiskMethod? = nil
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
