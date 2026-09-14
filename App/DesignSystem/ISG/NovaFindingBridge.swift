import Foundation

/// What happened to one analysis item after the expert pressed open. There is
/// no blanket success: every item carries its own answer, including the two
/// that are not failures — a record that was opened now, and one that the
/// server says already existed for this item.
enum NovaFindingOutcome: Equatable {
    case untouched
    case opened
    case alreadyOpen
    case failed(String)
}
