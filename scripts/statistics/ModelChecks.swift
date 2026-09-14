import Foundation
@main struct Checks {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let value = try JSONDecoder().decode(NovaStatisticsSnapshot.self, from: data)
        precondition(value.validate(owner: value.owner_id, company: nil, period: 6))
        precondition(!value.validate(owner: UUID(), company: nil, period: 6))
        precondition(!value.validate(owner: value.owner_id, company: UUID(), period: 6))
        precondition(!value.validate(owner: value.owner_id, company: nil, period: 3))
        precondition(value.analyses == 252 && value.trainings == 1)
        precondition(value.findings?.open == 205 && value.documentTotal == 6)
        precondition(NovaStatisticsSnapshot.dayLabel("2026-09-14") == "14.09.2026")
        print("PASS: real SQL snapshot decode, owner/filter contract, complete aggregates and date labels")
    }
}
