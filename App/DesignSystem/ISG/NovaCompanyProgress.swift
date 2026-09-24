import Foundation

enum NovaCompanySection: String, CaseIterable, Identifiable {
    case logo, personnel, representative, support, risk, emergency, inspections, accidents, board, training, files, handover
    var id: String { rawValue }
}

enum NovaCompletionState: String, Codable {
    case missing, complete, needsReview, unknown
}

/// Counts leaf headings once. Unknown data is never fabricated as missing or zero.
struct NovaCompanyProgress: Equatable {
    var states: [NovaCompanySection: NovaCompletionState] = [:]
    /// Only services that answered participate in the score. An unavailable
    /// module cannot silently lower the company and no longer blocks the ring
    /// from producing a useful value.
    var measured: [NovaCompanySection] {
        NovaCompanySection.allCases.filter { $0 != .handover && states[$0] != nil && states[$0] != .unknown }
    }
    var total: Int { measured.count }
    var completed: Int { measured.filter { states[$0] == .complete }.count }
    var isKnown: Bool { total > 0 }
    var fraction: Double? { isKnown ? Double(completed) / Double(total) : nil }
    var score: Int? { fraction.map { Int(($0 * 100).rounded()) } }
    subscript(section: NovaCompanySection) -> NovaCompletionState { states[section] ?? .unknown }
}
