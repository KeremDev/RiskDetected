import Foundation

/// One sector the analysis engine already knows, with every name a person might
/// have typed for it. The catalogue is handed in, so this file stays free of the
/// localisation layer and can be compiled on its own.
struct NovaSectorCandidate: Equatable {
    let id: String
    let labels: [String]
}

/// Turns the free text a company was saved with into one of the analysis
/// sectors — or into nothing at all.
enum NovaSectorMatch {
    /// Folding runs under a fixed locale: under a Turkish one the dotted capital
    /// I lowercases to the dotless one and a sector name typed without its
    /// diacritics would stop matching. The dotless i carries no diacritic of its
    /// own, so U+0131 is mapped to a plain i afterwards by hand.
    static func normalize(_ value: String) -> String {
        let invariant = Locale(identifier: "en_US_POSIX")
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: invariant)
            .replacingOccurrences(of: "\u{0131}", with: "i")
        let cleaned = folded.map { character -> Character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ").lowercased(with: invariant)
    }

    /// Every name a candidate answers to: its identifier, its whole label, and
    /// each side of a label that names two things with a slash between them.
    private static func names(_ candidate: NovaSectorCandidate) -> Set<String> {
        var result: Set<String> = [normalize(candidate.id.replacingOccurrences(of: "_", with: " "))]
        for label in candidate.labels {
            result.insert(normalize(label))
            for part in label.split(separator: "/") {
                let piece = normalize(String(part))
                if !piece.isEmpty { result.insert(piece) }
            }
        }
        result.remove("")
        return result
    }

    /// Exact match on a normalised name, and only when exactly one candidate
    /// answers. A sector nobody recognises, or one two sectors both claim, is
    /// left to the expert: a wrong pre-selection is worse than none.
    static func suggestion(for companySector: String?, in candidates: [NovaSectorCandidate]) -> String? {
        guard let companySector else { return nil }
        let needle = normalize(companySector)
        guard !needle.isEmpty else { return nil }
        let matches = candidates.filter { names($0).contains(needle) }
        return matches.count == 1 ? matches[0].id : nil
    }
}

/// Which company the analysis belongs to. "No company" is a first-class answer,
/// not a missing value: the analysis is then kept on the account and can be
/// assigned later.
enum NovaAnalysisOwner: Equatable {
    case unassigned
    case company(id: UUID, name: String, sector: String?)

    var companyID: UUID? {
        if case let .company(id, _, _) = self { return id }
        return nil
    }
    var companyName: String? {
        if case let .company(_, name, _) = self { return name }
        return nil
    }
    var declaredSector: String? {
        if case let .company(_, _, sector) = self { return sector }
        return nil
    }
}

enum NovaAnalysisIntakeStep: String, CaseIterable, Identifiable {
    case owner, sector, focus
    var id: String { rawValue }
}

/// What the three intake steps have collected so far.
struct NovaAnalysisIntakeDraft: Equatable {
    var photoCount = 0
    var owner: NovaAnalysisOwner = .unassigned
    var sectorID: String?
    /// True only while the sector still is the one the company implied. Any
    /// change by the expert clears it, so the note never outlives the fact.
    var sectorCameFromCompany = false
    var focusIDs: [String] = []

    var isReady: Bool { photoCount > 0 && sectorID != nil && !focusIDs.isEmpty }

    mutating func choose(owner value: NovaAnalysisOwner, catalog: [NovaSectorCandidate]) {
        owner = value
        if let suggested = NovaSectorMatch.suggestion(for: value.declaredSector, in: catalog) {
            sectorID = suggested
            sectorCameFromCompany = true
        } else {
            // An unrecognised company sector leaves the previous answer alone
            // rather than clearing a choice the expert already made by hand.
            if sectorCameFromCompany { sectorID = nil }
            sectorCameFromCompany = false
        }
    }

    mutating func choose(sector value: String) {
        if sectorID != value { sectorCameFromCompany = false }
        sectorID = value
    }

    mutating func toggle(focus value: String) {
        if let at = focusIDs.firstIndex(of: value) { focusIDs.remove(at: at) } else { focusIDs.append(value) }
    }
}
