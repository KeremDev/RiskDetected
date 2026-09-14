#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Synthetic data only, available exclusively in the simulator review route.
enum NovaStatisticsReview {
    static func snapshot(owner: UUID, company: UUID?, months: Int, empty: Bool) -> NovaStatisticsSnapshot {
        let first = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
        let second = UUID(uuidString: "10000000-0000-4000-8000-000000000002")!
        let firms: [NovaStatisticsSnapshot.Company] = empty ? [] : [
            .init(id: first, name: "Atlas Metal Sanayi", personnel: 48, workplaces: 3, hazard: "high"),
            .init(id: second, name: "Kuzey Lojistik", personnel: 32, workplaces: 2, hazard: "medium")]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let rows: [NovaStatisticsSnapshot.Month] = (0..<months).map { index in
            .init(month: formatter.string(from: calendar.date(byAdding: .month, value: index-months+1, to: end)!),
                  analyses: empty ? 0 : ([8,12,7,18,14,23][index % 6] / (company == nil ? 1 : 2)),
                  trainings: empty ? 0 : [1,2,1,3,2,4][index % 6])
        }
        let selected = firms.filter { company == nil || $0.id == company }
        return .init(schema_version: 1, owner_id: owner, company_id: company, months: months,
            from_day: rows[0].month, today: "2026-09-14", generated_at: "2026-09-14T17:00:00Z",
            companies: firms, company_count: selected.count, personnel: selected.reduce(0) { $0+$1.personnel }, workplaces: selected.reduce(0) { $0+$1.workplaces },
            analyses: rows.reduce(0) { $0+$1.analyses }, trainings: rows.reduce(0) { $0+$1.trainings },
            trained_people: empty ? 0 : 64, training_enrollments: empty ? 0 : 96, series: rows,
            findings: .init(open: empty ? 0 : 18, overdue: empty ? 0 : 4, pending: empty ? 0 : 3, opened: empty ? 0 : 26, closed: empty ? 0 : 12,
                severity: empty ? [:] : ["critical":2,"high":4,"medium":8,"low":4]),
            documents: empty ? [:] : ["valid":24,"missing":3,"due_soon":5,"expired":2])
    }
}
#endif
