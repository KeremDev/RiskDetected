import Foundation

struct NovaStatisticsSnapshot: Codable, Equatable {
    struct Company: Codable, Equatable, Identifiable {
        let id: UUID; let name: String; let personnel: Int; let workplaces: Int; let hazard: String
    }
    struct Month: Codable, Equatable, Identifiable {
        let month: String; let analyses: Int; let trainings: Int
        var id: String { month }
        var label: String {
            let names = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
            let parts = month.split(separator: "-")
            guard parts.count == 3, let index = Int(parts[1]), (1...12).contains(index) else { return month }
            return names[index - 1]
        }
    }
    struct Findings: Codable, Equatable {
        let open: Int; let overdue: Int; let pending: Int; let opened: Int; let closed: Int
        let severity: [String: Int]
    }
    let schema_version: Int; let owner_id: UUID; let company_id: UUID?; let months: Int
    let from_day: String; let today: String; let generated_at: String
    let companies: [Company]; let company_count: Int; let personnel: Int; let workplaces: Int
    let analyses: Int; let trainings: Int; let trained_people: Int; let training_enrollments: Int
    let series: [Month]; let findings: Findings?; let documents: [String: Int]?

    func validate(owner: UUID, company: UUID?, period: Int) -> Bool {
        schema_version == 1 && owner_id == owner && company_id == company && months == period
        && [1,3,6,12].contains(months) && series.count == months
        && Set(series.map(\.month)).count == months
        && Set(companies.map(\.id)).count == companies.count
        && (company == nil || companies.contains { $0.id == company })
        && [company_count,personnel,workplaces,analyses,trainings,trained_people,training_enrollments].allSatisfy { $0 >= 0 }
        && companies.allSatisfy { $0.personnel >= 0 && $0.workplaces >= 0 }
        && series.allSatisfy { $0.analyses >= 0 && $0.trainings >= 0 }
        && series.reduce(0, { $0 + $1.analyses }) == analyses
        && series.reduce(0, { $0 + $1.trainings }) == trainings
        && (findings.map { f in [f.open,f.overdue,f.pending,f.opened,f.closed].allSatisfy { $0 >= 0 }
            && f.overdue <= f.open && f.pending <= f.open && f.severity.values.allSatisfy { $0 >= 0 } } ?? true)
        && (documents?.values.allSatisfy { $0 >= 0 } ?? true)
    }
    var selectedCompanies: [Company] { companies.filter { company_id == nil || $0.id == company_id } }
    var documentTotal: Int? { documents.map { $0.values.reduce(0,+) } }
    static func dayLabel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        return parts.count == 3 ? "\(parts[2]).\(parts[1]).\(parts[0])" : value
    }
}
