import Foundation

struct NovaTrainingSession: Codable {}

@main struct EditorVariations {
    static func main() {
        let company = UUID()
        let workplace = UUID()
        let topic = NovaEducationTopic(code: "G4-S1", group: "G4", title: "İşyerine özgü riskler", instruction_minutes: 45)
        var companyScope = NovaEducationScope(company_id: company, workplace_id: nil, hazard_class: "low")
        companyScope.topics = [topic]
        var workplaceScope = NovaEducationScope(company_id: UUID(), workplace_id: workplace, hazard_class: "low")
        workplaceScope.topics = [topic]

        var draft = NovaEducationDraft()
        precondition(!draft.isComplete(.companies) && !draft.isComplete(.trainers))
        draft.scopes = [companyScope]
        precondition(draft.isComplete(.companies) && draft.scopes[0].workplace_id == nil)
        draft.scopes.append(workplaceScope)
        precondition(draft.isComplete(.companies) && draft.scopes.count == 2)

        let first = NovaEducationTrainer(name: " Birinci Eğitici ", title: " Uzman ")
        let second = NovaEducationTrainer(name: "İkinci Eğitici", title: "")
        draft.trainers = [first, NovaEducationTrainer()]
        precondition(!draft.isComplete(.trainers))
        var prepared = draft.preparedForSave()
        precondition(prepared.trainers.count == 1 && prepared.trainers[0].name == "Birinci Eğitici")
        precondition(prepared.isComplete(.trainers))
        precondition(prepared.scopes.allSatisfy { $0.topics.allSatisfy { $0.trainer_ids == [first.id] } })

        draft.trainers = [first, second]
        prepared = draft.preparedForSave()
        precondition(prepared.trainers.count == 2 && prepared.isComplete(.trainers))
        precondition(prepared.scopes.allSatisfy { $0.topics.allSatisfy { $0.trainer_ids == [first.id, second.id] } })

        draft.trainers = [.init(name: "", title: "Belge var")]
        precondition(!draft.preparedForSave().isComplete(.trainers))
        draft.trainers = [first, second]
        draft.trainers.removeAll { $0.id == second.id }
        prepared = draft.preparedForSave()
        precondition(prepared.trainers.map(\.id) == [first.id])

        draft.scopes.removeAll { $0.id == companyScope.id }
        precondition(draft.scopes.count == 1 && draft.scopes[0].workplace_id == workplace)
        draft.scopes.removeAll { $0.id == workplaceScope.id }
        precondition(!draft.isComplete(.companies))

        let days16Hours = NovaEducationClock.initialDays(minutes: 720, basic: true)
        precondition(days16Hours.count == 2 && days16Hours.map(\.lessonCount) == [8, 8])
        precondition(NovaEducationClock.lessonUnits(minutes: 720, basic: true) == 16)
        precondition(NovaEducationClock.lessonUnits(minutes: 745, basic: true) == 16)
        precondition(NovaEducationClock.lessonUnits(minutes: 370, basic: true) == 8)
        var minutes745 = topic
        minutes745.instruction_minutes = 745
        let lessons745 = NovaEducationClock.distribute(topics: [minutes745], days: NovaEducationClock.initialDays(minutes: 745, basic: true), basic: true)
        precondition(lessons745.count == 16 && lessons745.last?.instruction_minutes == 70)
        var minutes370 = topic
        minutes370.instruction_minutes = 370
        let days370 = NovaEducationClock.initialDays(minutes: 370, basic: true)
        let lessons370 = NovaEducationClock.distribute(topics: [minutes370], days: days370, basic: true)
        precondition(lessons370.count == 8 && lessons370.last?.instruction_minutes == 55)
        let packageURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let package = try! JSONDecoder().decode(NovaEducationPackage.self, from: Data(contentsOf: packageURL))
        precondition(package.preset(cycle: "initial", hazard: "low")?.common_groups_review_guard?.reference_instruction_minutes == 270)
        precondition(package.preset(cycle: "initial", hazard: "high")?.common_groups_review_guard?.reference_instruction_minutes == 540)
        print("PASS: company/workplace selection, one/two/empty/partial trainers, removals, duration and package guards")
    }
}
