import Foundation

/// The four severities the server accepts. The legacy band 'unknown' is absent
/// on purpose: an unreadable band has to reach a person, not become the lowest.
enum NovaNonconformitySeverity: String, CaseIterable, Codable, Identifiable, Equatable {
    case low, medium, high, critical
    var id: String { rawValue }
}

enum NovaNonconformityState: String, Codable, Equatable {
    case draft, open, assigned, in_progress, pending_verification, closed, reopened, cancelled
}

struct NovaNonconformityRow: Equatable, Identifiable, Codable {
    let id: UUID
    let workplace_id: UUID
    let title: String
    let severity: String
    let state: String
    let version: Int64
    let opened_on: String
    let due_on: String?
    let source_kind: String
    let source_ref: String?
    /// Absent on rows written before the detail slice; those rows are
    /// nonconformities, which is what the server column also defaults to.
    var record_kind: String? = nil
    /// Present on list rows only when the record carries a scored detail.
    var risk_band: String? = nil
    var closed_on: String? = nil
    var assignee_contact: String? = nil
    var detail: NovaNonconformityDetail? = nil
    var actions: [NovaCorrectiveAction]? = nil
    var verifications: [NovaVerificationRecord]? = nil
    /// A record that came from a photo analysis keeps pointing at that finding;
    /// the finding itself is never rewritten.
    var camefromFinding: Bool { source_kind == "legacy_finding" }
    /// An expert-opinion item arrives unscored, so a record born from one never
    /// claims a band it was not given.
    var camefromExpertItem: Bool { source_kind == "legacy_expert_item" }
    var kind: NovaNonconformityRecordKind {
        NovaNonconformityRecordKind(rawValue: record_kind ?? "") ?? .nonconformity
    }
}

/// One corrective action recorded against a record.
struct NovaCorrectiveAction: Equatable, Identifiable, Codable {
    let id: UUID
    let description: String
    let assignee: String?
    let due_on: String?
    let state: String
}

/// One expert verification cycle. A rejected verification closes nothing.
struct NovaVerificationRecord: Equatable, Identifiable, Codable {
    let id: UUID
    let outcome: String
    let verified_on: String
}

struct NovaNonconformityWorkplace: Equatable, Identifiable, Codable {
    let id: UUID
    let name: String
    let needs_review: Bool
}

enum NovaNonconformityFailure: Error, Equatable {
    case denied, validation, conflict, unavailable, severityUnknown, payloadRejected, riskInputIncomplete
}

/// What the new-nonconformity screen is about to send. `severity` stays optional
/// so the caller can let the server map a legacy band instead of guessing here.
struct NovaNonconformityIntent: Equatable, Codable {
    /// `expertItem` is the unscored half of a photo analysis. It carries no
    /// band on purpose: the server has no key to receive one.
    enum Origin: String, Codable, Equatable { case manual, finding, expertItem, detailed }
    let origin: Origin
    let workplaceID: UUID
    let title: String
    var severity: NovaNonconformitySeverity?
    var riskBand: String?
    var findingID: UUID?
    var expertItemID: UUID?
    var recordKind: NovaNonconformityRecordKind = .nonconformity
    var dueOn: String?
    var assignee: String?
    var hazardDescription: String?
    var controlMeasure: String?
    var legislation: String?
    var responsible: String?
    var score = NovaRiskScoreInput()

    var action: String {
        switch origin {
        case .manual: return "open_manual"
        case .finding: return "open_from_finding"
        case .expertItem: return "open_from_expert_item"
        case .detailed: return "open_detailed"
        }
    }
}

/// An improvement suggestion travels the same lifecycle but is not a
/// nonconformity and is never counted as one.
enum NovaNonconformityRecordKind: String, Codable, Equatable, CaseIterable, Identifiable {
    case nonconformity, improvement
    var id: String { rawValue }
}

/// The two scoring methods, their published scales and their published bands.
/// The same numbers live in `20260914190000_isg_nonconformity_detail.sql`, and
/// a guard test compares the two so they cannot drift apart.
enum NovaRiskMethod: String, Codable, Equatable, CaseIterable, Identifiable {
    case fineKinney = "fine_kinney"
    case matrix5x5 = "matrix_5x5"
    var id: String { rawValue }

    static let probabilityScale: [Double] = [0.2, 0.5, 1, 3, 6, 10]
    static let frequencyScale: [Double] = [0.5, 1, 2, 3, 6, 10]
    static let severityScale: [Double] = [1, 3, 7, 15, 40, 100]
    static let matrixScale: [Int] = [1, 2, 3, 4, 5]
}

/// What the expert has typed into the scoring step so far.
struct NovaRiskScoreInput: Equatable, Codable {
    var method: NovaRiskMethod?
    var probability: Double?
    var frequency: Double?
    var severity: Double?
    var matrixProbability: Int?
    var matrixSeverity: Int?

    /// Complete means the chosen method has all of its own inputs and none of
    /// the other method's. A half-filled method is not a score.
    var isComplete: Bool {
        switch method {
        case .none: return false
        case .fineKinney: return probability != nil && frequency != nil && severity != nil
        case .matrix5x5: return matrixProbability != nil && matrixSeverity != nil
        }
    }
    /// Empty is a legitimate answer: a record may be filed without a score.
    var isEmpty: Bool {
        method == nil && probability == nil && frequency == nil && severity == nil
            && matrixProbability == nil && matrixSeverity == nil
    }
    var score: Double? {
        guard isComplete else { return nil }
        switch method {
        case .fineKinney:
            guard let probability, let frequency, let severity else { return nil }
            return probability * frequency * severity
        case .matrix5x5:
            guard let matrixProbability, let matrixSeverity else { return nil }
            return Double(matrixProbability * matrixSeverity)
        case .none: return nil
        }
    }
    /// The preview the expert sees while scoring. The stored band is the
    /// server's generated column; this only shows the same published rule.
    var band: NovaNonconformitySeverity? {
        guard let score, let method else { return nil }
        switch method {
        case .fineKinney:
            if score <= 70 { return .low }
            if score <= 200 { return .medium }
            if score <= 400 { return .high }
            return .critical
        case .matrix5x5:
            if score <= 4 { return .low }
            if score <= 9 { return .medium }
            if score <= 19 { return .high }
            return .critical
        }
    }
    mutating func select(_ value: NovaRiskMethod?) {
        guard method != value else { return }
        // Switching method drops the other method's inputs instead of carrying
        // numbers that belong to a scale nobody chose.
        self = NovaRiskScoreInput(method: value)
    }
}

/// The fields the expert fills in by hand, as the server stores them.
struct NovaNonconformityDetail: Equatable, Codable {
    var description: String?
    var control_measure: String?
    var legislation_ref: String?
    var responsible_contact: String?
    var risk_method: String?
    var fk_probability: Double?
    var fk_frequency: Double?
    var fk_severity: Double?
    var m5_probability: Int?
    var m5_severity: Int?
    var risk_score: Double?
    var risk_band: String?

    var scoreInput: NovaRiskScoreInput {
        .init(method: risk_method.flatMap(NovaRiskMethod.init(rawValue:)),
              probability: fk_probability, frequency: fk_frequency, severity: fk_severity,
              matrixProbability: m5_probability, matrixSeverity: m5_severity)
    }
}

/// The steps of the hand-entered flow, in the order they are asked.
enum NovaManualStep: String, CaseIterable, Identifiable {
    case photo, company, hazard, scoring, legislation, responsible
    var id: String { rawValue }
}

/// One draft of a hand-entered record, and which of its steps are finished.
/// Pure: the screen reads `completion` for the ticks and the progress bar.
struct NovaManualDraft: Equatable {
    /// How many site photos the expert attached. The pictures live in the
    /// screen; the draft only counts them so this model stays free of images.
    var photoCount = 0
    var workplaceID: UUID?
    var title = ""
    var hazardDescription = ""
    var controlMeasure = ""
    var severity: NovaNonconformitySeverity = .medium
    var recordKind: NovaNonconformityRecordKind = .nonconformity
    var score = NovaRiskScoreInput()
    var legislation = ""
    var responsible = ""
    var dueOn: String?

    private func filled(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// A step counts as finished only when it carries what the record needs.
    /// The two optional steps are finished once they carry anything at all,
    /// and an untouched optional step is simply not finished — never a tick.
    func isComplete(_ step: NovaManualStep) -> Bool {
        switch step {
        case .photo: return photoCount > 0
        case .company: return workplaceID != nil
        case .hazard: return filled(title) && filled(hazardDescription) && filled(controlMeasure)
        case .scoring: return score.isComplete
        case .legislation: return filled(legislation)
        case .responsible: return filled(responsible)
        }
    }
    /// The two steps without which the server would refuse the record.
    static let requiredSteps: [NovaManualStep] = [.company, .hazard]
    var canSave: Bool {
        Self.requiredSteps.allSatisfy { isComplete($0) } && (score.isEmpty || score.isComplete)
    }
    var completedCount: Int { NovaManualStep.allCases.filter { isComplete($0) }.count }
    var progress: Double { Double(completedCount) / Double(NovaManualStep.allCases.count) }
    /// The next step after this one that is still unfinished, so a finished
    /// step can open the next one instead of leaving the expert to hunt.
    func nextIncomplete(after step: NovaManualStep) -> NovaManualStep? {
        let all = NovaManualStep.allCases
        guard let at = all.firstIndex(of: step) else { return nil }
        return all[(at + 1)...].first { !isComplete($0) }
    }
}
