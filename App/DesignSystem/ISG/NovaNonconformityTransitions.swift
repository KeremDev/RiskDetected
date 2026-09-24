import Foundation

/// One allowed move of the record's state machine, and what the server will
/// insist on before it accepts the move.
///
/// The same sixteen edges are server data in
/// `20260913210000_isg_nonconformity_core.sql`; a guard test compares the two
/// so the screen can never offer a move the server would refuse, and never
/// hide one it would accept.
struct NovaNonconformityEdge: Equatable, Identifiable {
    let from: NovaNonconformityState
    let to: NovaNonconformityState
    let requiresReason: Bool
    let requiresAssignee: Bool
    /// Closing needs an accepted verification for this cycle. The screen asks
    /// for the verification first rather than offering a move that will fail.
    let requiresVerification: Bool
    var id: String { "\(from.rawValue)>\(to.rawValue)" }
}

enum NovaNonconformityMachine {
    static let edges: [NovaNonconformityEdge] = [
        .init(from: .draft, to: .open, requiresReason: false, requiresAssignee: false, requiresVerification: false),
        .init(from: .draft, to: .cancelled, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .open, to: .assigned, requiresReason: false, requiresAssignee: true, requiresVerification: false),
        .init(from: .open, to: .cancelled, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .assigned, to: .in_progress, requiresReason: false, requiresAssignee: false, requiresVerification: false),
        .init(from: .assigned, to: .open, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .assigned, to: .cancelled, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .in_progress, to: .pending_verification, requiresReason: false, requiresAssignee: false, requiresVerification: false),
        .init(from: .in_progress, to: .assigned, requiresReason: true, requiresAssignee: true, requiresVerification: false),
        .init(from: .in_progress, to: .cancelled, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .pending_verification, to: .closed, requiresReason: false, requiresAssignee: false, requiresVerification: true),
        .init(from: .pending_verification, to: .in_progress, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .closed, to: .reopened, requiresReason: true, requiresAssignee: false, requiresVerification: false),
        .init(from: .reopened, to: .assigned, requiresReason: false, requiresAssignee: true, requiresVerification: false),
        .init(from: .reopened, to: .in_progress, requiresReason: false, requiresAssignee: false, requiresVerification: false),
        .init(from: .reopened, to: .cancelled, requiresReason: true, requiresAssignee: false, requiresVerification: false),
    ]

    static func moves(from state: NovaNonconformityState) -> [NovaNonconformityEdge] {
        edges.filter { $0.from == state }
    }
    /// A state nobody can leave is a finished record, not a broken screen.
    static func isTerminal(_ state: NovaNonconformityState) -> Bool { moves(from: state).isEmpty }
}

/// What the list is currently showing. Every filter is a plain choice the
/// expert made; nothing is filtered away on their behalf.
struct NovaNonconformityFilter: Equatable {
    var companyID: UUID?
    var state: NovaNonconformityState?
    var kind: NovaNonconformityRecordKind?
    var query = ""
    /// Records whose due date has passed and which are still being worked on.
    var overdueOnly = false
    /// What a "Senin İçin" card counted: overdue, draft or recorded
    /// nonconformities, in its days, and in an organization only the member's.
    var preset: NovaListPreset?

    var isEmpty: Bool {
        companyID == nil && state == nil && kind == nil && !overdueOnly && preset == nil
            && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// One row of the cross-company list: the record plus the company it belongs
/// to, because the list is no longer scoped to a single company.
struct NovaNonconformityEntry: Equatable, Identifiable {
    let row: NovaNonconformityRow
    let companyID: UUID
    let companyName: String
    let workplaceName: String?
    var id: UUID { row.id }

    /// A draft is not being worked on yet, so it is never overdue; the
    /// deadline board and the home page count the same way.
    func isOverdue(today: String) -> Bool {
        guard let due = row.due_on, !["draft", "closed", "cancelled"].contains(row.state) else { return false }
        // ISO day strings compare correctly as text, so no calendar maths is
        // needed and no time zone can shift the answer.
        return due < today
    }

    func matches(_ filter: NovaNonconformityFilter, today: String) -> Bool {
        if let preset = filter.preset, !matches(preset, today: today) { return false }
        if let company = filter.companyID, company != companyID { return false }
        if let state = filter.state, state.rawValue != row.state { return false }
        if let kind = filter.kind, kind != row.kind { return false }
        if filter.overdueOnly && !isOverdue(today: today) { return false }
        let needle = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        let folded = NovaSectorMatch.normalize(needle)
        return [row.title, companyName, workplaceName ?? ""]
            .contains { NovaSectorMatch.normalize($0).contains(folded) }
    }

    /// The records a home card counted, by the same rules the server used.
    func matches(_ preset: NovaListPreset, today: String) -> Bool {
        guard row.kind == .nonconformity else { return false }
        if let mine = preset.mine, row.created_by_user_id != mine { return false }
        switch preset.status {
        case "overdue": return isOverdue(today: today)
        case "draft": return row.state == NovaNonconformityState.draft.rawValue
        case "recorded":
            guard !["draft", "cancelled"].contains(row.state) else { return false }
            return preset.includes(NovaListPreset.moment(row.created_at))
        default: return true
        }
    }
}
