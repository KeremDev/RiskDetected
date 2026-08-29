import Foundation

enum AnalysisResultSectionID: String, Codable, CaseIterable, Identifiable {
    case riskAnalysis = "risk_analysis"
    case expertRecommendations = "expert_recommendations"
    case approvedNotebook = "approved_notebook"

    var id: String { rawValue }

    func title(language: RDLanguage) -> String {
        switch self {
        case .riskAnalysis: return language == .turkish ? "Risk Analizi" : "Risk Analysis"
        case .expertRecommendations: return language == .turkish ? "Uzman Görüşü Önerileri" : "Expert Recommendations"
        case .approvedNotebook: return language == .turkish ? "Onaylı Defter Önerisi" : "Safety Log Recommendation"
        }
    }

    var title: String { title(language: .current) }

    func compactTitle(language: RDLanguage) -> String {
        switch self {
        case .riskAnalysis: return language == .turkish ? "Risk Analizi" : "Risk Analysis"
        case .expertRecommendations: return language == .turkish ? "Uzman Görüşü" : "Expert Advice"
        case .approvedNotebook: return language == .turkish ? "Onaylı Defter" : "Safety Log"
        }
    }

    var compactTitle: String { compactTitle(language: .current) }

    var icon: String {
        switch self {
        case .riskAnalysis: return "exclamationmark.shield.fill"
        case .expertRecommendations: return "person.badge.shield.checkmark.fill"
        case .approvedNotebook: return "book.closed.fill"
        }
    }

    func countLabel(language: RDLanguage, count: Int? = nil) -> String {
        switch self {
        case .riskAnalysis:
            return language == .turkish ? "Bulgu" : (count == 1 ? "Finding" : "Findings")
        case .expertRecommendations:
            return language == .turkish ? "Öneri" : (count == 1 ? "Recommendation" : "Recommendations")
        case .approvedNotebook:
            return language == .turkish ? "Kayıt" : (count == 1 ? "Entry" : "Entries")
        }
    }

    var countLabel: String { countLabel(language: .current) }
}

enum AnalysisResultSectionAccess: String, Codable {
    case full
    case teaser
}

enum AnalysisItemReaction: String, Codable {
    case none
    case like
    case dislike
}

struct AnalysisResultHubResponse: Decodable {
    let enabled: Bool
    let contractVersion: String
    let uiVersion: String?
    let analysisID: UUID?
    let analysisEditVersion: Int?
    let tier: String?
    let language: String?
    let disclaimers: AnalysisResultHubDisclaimers?
    let sections: [AnalysisResultSection]
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case enabled
        case contractVersion = "contract_version"
        case uiVersion = "ui_version"
        case analysisID = "analysis_id"
        case analysisEditVersion = "analysis_edit_version"
        case tier, language, disclaimers, sections, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        contractVersion = try container.decodeIfPresent(String.self, forKey: .contractVersion) ?? "analysis-result-sections-v1"
        uiVersion = try container.decodeIfPresent(String.self, forKey: .uiVersion)
        analysisID = try container.decodeIfPresent(UUID.self, forKey: .analysisID)
        analysisEditVersion = try container.decodeIfPresent(Int.self, forKey: .analysisEditVersion)
        tier = try container.decodeIfPresent(String.self, forKey: .tier)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        disclaimers = try container.decodeIfPresent(AnalysisResultHubDisclaimers.self, forKey: .disclaimers)
        sections = try container.decodeIfPresent([AnalysisResultSection].self, forKey: .sections) ?? []
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
    }
}

struct AnalysisResultHubDisclaimers: Decodable {
    let expert: String
    let notebook: String
}

struct AnalysisResultSection: Decodable, Identifiable {
    let id: AnalysisResultSectionID
    let access: AnalysisResultSectionAccess
    let count: Int
    let canEdit: Bool
    let canReport: Bool
    let items: [AnalysisResultHubItem]

    enum CodingKeys: String, CodingKey {
        case id, access, count, items
        case canEdit = "can_edit"
        case canReport = "can_report"
    }
}

struct AnalysisResultHubItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let analysisID: UUID?
    let ordinal: Int?
    let title: String?
    let category: String?
    let description: String?
    let recommendedAction: String?
    let recommendedMeasures: [FindingMeasure]?
    let referencesText: String?
    let rootCauseText: String?
    let confidence: Double?
    let needsFieldVerification: Bool?
    let fkProbability: Double?
    let fkFrequency: Double?
    let fkSeverity: Double?
    let fkScore: Double?
    let fkBand: String?
    let m5Probability: Int?
    let m5Severity: Int?
    let m5Score: Int?
    let m5Band: String?
    let sourcePhotoIndices: [Int]?
    let displayOrder: Int?
    let itemClass: String?
    let isScored: Bool?
    let locked: Bool?
    let userReaction: AnalysisItemReaction?
    let findingText: String?
    let recommendationText: String?
    let referenceText: String?
    let sourceFindingIDs: [UUID]?
    let isUserEdited: Bool?
    let isStale: Bool?

    enum CodingKeys: String, CodingKey {
        case id, ordinal, title, category, description, confidence, locked
        case analysisID = "analysis_id"
        case recommendedAction = "recommended_action"
        case recommendedMeasures = "recommended_measures"
        case referencesText = "references_text"
        case rootCauseText = "root_cause_text"
        case needsFieldVerification = "needs_field_verification"
        case fkProbability = "fk_probability"
        case fkFrequency = "fk_frequency"
        case fkSeverity = "fk_severity"
        case fkScore = "fk_score"
        case fkBand = "fk_band"
        case m5Probability = "m5_probability"
        case m5Severity = "m5_severity"
        case m5Score = "m5_score"
        case m5Band = "m5_band"
        case sourcePhotoIndices = "source_photo_indices"
        case displayOrder = "display_order"
        case itemClass = "item_class"
        case isScored = "is_scored"
        case userReaction = "user_reaction"
        case findingText = "finding_text"
        case recommendationText = "recommendation_text"
        case referenceText = "reference_text"
        case sourceFindingIDs = "source_finding_ids"
        case isUserEdited = "is_user_edited"
        case isStale = "is_stale"
    }

    var displayTitle: String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? findingText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "Kayıt"
    }

    func displayTitle(language: RDLanguage) -> String {
        title?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? findingText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? (language == .turkish ? "Kayıt" : "Entry")
    }

    var displayBody: String {
        description?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? recommendationText?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? ""
    }

    func asFindingRow(fallbackAnalysisID: UUID) -> FindingRow {
        FindingRow(
            id: id,
            analysisID: analysisID ?? fallbackAnalysisID,
            ordinal: ordinal ?? max(1, displayOrder ?? 1),
            title: title ?? displayTitle,
            category: category,
            description: description ?? findingText,
            recommendedAction: recommendedAction ?? recommendationText,
            recommendedMeasures: recommendedMeasures,
            referencesText: referencesText ?? referenceText,
            rootCauseText: rootCauseText,
            needsFieldVerification: needsFieldVerification,
            confidence: confidence ?? 0,
            fkProbability: fkProbability,
            fkFrequency: fkFrequency,
            fkSeverity: fkSeverity,
            fkScore: fkScore,
            fkBand: fkBand ?? "unknown",
            m5Probability: m5Probability,
            m5Severity: m5Severity,
            m5Score: m5Score,
            m5Band: m5Band ?? "unknown",
            origin: nil,
            sourcePhotoIndices: sourcePhotoIndices,
            aiConfidence: confidence,
            lastUserEditAt: nil,
            userEditCount: nil,
            findingVersion: nil,
            displayOrder: displayOrder,
            itemClass: itemClass,
            isScored: isScored
        )
    }
}

struct AnalysisReportIntent: Decodable {
    let id: UUID
    let analysisID: UUID
    let contentScope: AnalysisResultSectionID
    let format: String
    let selectedItemKeys: [UUID]

    enum CodingKeys: String, CodingKey {
        case id, format
        case analysisID = "analysis_id"
        case contentScope = "content_scope"
        case selectedItemKeys = "selected_item_keys"
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
