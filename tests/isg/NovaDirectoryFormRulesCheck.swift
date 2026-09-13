import Foundation

@main struct NovaDirectoryFormRulesCheck {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); count += 1 }
        for value in ["0001-01-01", "9999-12-31", "2000-02-29", "2024-02-29", "2026-09-13", "1900-02-28"] { check(NovaDirectoryFormRules.isDate(value), value) }
        for value in ["", "2026-2-01", "2026-02-1", "2026-02-29", "1900-02-29", "2100-02-29", "2026-04-31", "2026-00-01", "2026-13-01", "2026-01-00", "2026-01-32", "0000-01-01", "10000-01-01", " 2026-01-01", "2026-01-01\n", "２０２６-01-01", "2026/01/01", "2026-01-01T00:00:00Z"] { check(!NovaDirectoryFormRules.isDate(value), value) }
        let root = UUID(), child = UUID(), grandchild = UUID(), other = UUID()
        func row(_ id: UUID, _ fields: [String: String]) -> NovaDirectoryRow { .init(id: id, fields: fields.mapValues { .string($0) }) }
        for end in ["", "2026-09-14", "2026-09-13", "2026-09-12", "2026-02-30"] {
            let error = NovaDirectoryFormRules.validation(kind: .engagements, fields: ["starts_on": "2026-09-13", "ends_before": end], options: [:], originalID: nil)
            check((error == nil) == ["", "2026-09-14"].contains(end), "half-open \(end)")
        }
        let prior = row(root, ["starts_on": "2026-01-01", "ends_before": "2026-12-31"])
        for kind in [NovaDirectoryKind.contexts, .assignments] {
            for day in ["2026-06-01", "2026-01-01", "2026-12-31", "2027-01-01"] {
                let error = NovaDirectoryFormRules.validation(kind: kind, fields: ["starts_on": day, "previous_id": root.uuidString], options: ["previous_id": [prior]], originalID: nil)
                check((error == nil) == (day == "2026-06-01"), "split \(kind) \(day)")
            }
            check(NovaDirectoryFormRules.validation(kind: kind, fields: ["starts_on": "2026-06-01", "previous_id": root.uuidString], options: [:], originalID: nil) != nil, "unloaded prior")
        }
        let rows = [row(grandchild, ["parent_id": child.uuidString, "workplace_id": "a"]), row(child, ["parent_id": root.uuidString, "workplace_id": "a"]), row(root, ["workplace_id": "a"]), row(other, ["workplace_id": "b"])]
        check(NovaDirectoryFormRules.allowedOptions(rows, field: "parent_id", workplace: "a", originalID: root).isEmpty, "descendants")
        check(NovaDirectoryFormRules.allowedOptions(rows, field: "parent_id", workplace: "b", originalID: root).map(\.id) == [other], "foreign workplace")
        check(NovaDirectoryFormRules.allowedOptions(rows, field: "department_id", workplace: "a", originalID: nil).count == 3, "assignment options")
        check(NovaDirectoryFormRules.validation(kind: .departments, fields: ["workplace_id": "a", "parent_id": child.uuidString], options: ["parent_id": rows], originalID: root) != nil, "cycle feedback")
        let cycle = [row(root, ["parent_id": child.uuidString, "workplace_id": "a"]), row(child, ["parent_id": root.uuidString, "workplace_id": "a"])]
        check(NovaDirectoryFormRules.allowedOptions(cycle, field: "parent_id", workplace: "a", originalID: root).isEmpty, "cycle terminates")
        let fields = ["workplace_id": "a", "parent_id": "p", "department_id": "d", "name": "Ada"]
        check(NovaDirectoryFormRules.selecting("workplace_id", value: "a", in: fields) == fields, "reselect keeps")
        let changed = NovaDirectoryFormRules.selecting("workplace_id", value: "b", in: fields)
        check(changed["parent_id"] == "" && changed["department_id"] == "" && changed["name"] == "Ada", "change clears links only")
        print("NOVA directory form rules: \(count) checks PASS")
    }
}
