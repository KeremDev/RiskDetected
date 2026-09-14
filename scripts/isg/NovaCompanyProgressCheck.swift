import Foundation

@main struct Check {
    static func main() {
        var progress = NovaCompanyProgress()
        precondition(progress.score == nil && progress.fraction == nil)
        precondition(progress.completed == 0 && progress.total == 12)
        for section in NovaCompanySection.allCases { progress.states[section] = .missing }
        precondition(progress.score == 0 && progress.fraction == 0)
        for section in NovaCompanySection.allCases.prefix(6) { progress.states[section] = .complete }
        precondition(progress.score == 50 && progress.fraction == 0.5)
        progress.states[.inspections] = .complete
        precondition(progress.score == 58 && progress.completed == 7)
        progress.states[.inspections] = .complete
        precondition(progress.completed == 7)
        for section in NovaCompanySection.allCases { progress.states[section] = .complete }
        precondition(progress.score == 100 && progress.fraction == 1)
        progress.states[.logo] = .missing
        precondition(progress.score == 92)
        progress.states[.risk] = .needsReview
        precondition(progress.score == 83)
        progress.states[.risk] = .unknown
        precondition(progress.score == nil)
        progress.states[.risk] = nil
        precondition(progress.score == nil)
        print("11 company score checks PASS")
    }
}
