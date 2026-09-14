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
    /// A record that came from a photo analysis keeps pointing at that finding;
    /// the finding itself is never rewritten.
    var camefromFinding: Bool { source_kind == "legacy_finding" }
}

struct NovaNonconformityWorkplace: Equatable, Identifiable, Codable {
    let id: UUID
    let name: String
    let needs_review: Bool
}

enum NovaNonconformityFailure: Error, Equatable {
    case denied, validation, conflict, unavailable, severityUnknown, payloadRejected
}

/// What the new-nonconformity screen is about to send. `severity` stays optional
/// so the caller can let the server map a legacy band instead of guessing here.
struct NovaNonconformityIntent: Equatable, Codable {
    enum Origin: String, Codable, Equatable { case manual, finding }
    let origin: Origin
    let workplaceID: UUID
    let title: String
    var severity: NovaNonconformitySeverity?
    var riskBand: String?
    var findingID: UUID?
    var dueOn: String?
    var assignee: String?
}
