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
    var total: Int { NovaCompanySection.allCases.count }
    var completed: Int { NovaCompanySection.allCases.filter { states[$0] == .complete }.count }
    var isKnown: Bool { NovaCompanySection.allCases.allSatisfy { states[$0] != nil && states[$0] != .unknown } }
    var fraction: Double? { isKnown ? Double(completed) / Double(total) : nil }
    var score: Int? { fraction.map { Int(($0 * 100).rounded()) } }
    subscript(section: NovaCompanySection) -> NovaCompletionState { states[section] ?? .unknown }
}
