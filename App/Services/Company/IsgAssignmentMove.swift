import Foundation

/// Domain request validation; not proof of session, ownership or capability.
struct IsgAssignmentMove: Decodable, Equatable {
    let context: IsgMutationContext
    let employeeID: String
    let previousAssignmentID: String?
    let departmentID: String
    let jobRoleID: String
    let startsOn: String

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard Set(c.allKeys.map(\.stringValue)) == ["context","employee_id","previous_assignment_id","department_id","job_role_id","starts_on"] else { throw Invalid.request }
        context = try c.decode(IsgMutationContext.self, forKey: Key("context"))
        employeeID = try c.decode(String.self, forKey: Key("employee_id"))
        previousAssignmentID = try c.decodeIfPresent(String.self, forKey: Key("previous_assignment_id"))
        departmentID = try c.decode(String.self, forKey: Key("department_id"))
        jobRoleID = try c.decode(String.self, forKey: Key("job_role_id"))
        startsOn = try c.decode(String.self, forKey: Key("starts_on"))
        guard context.scope.kind == "company", context.scope.workplaceID != nil, context.expectedVersion < 9007199254740991,
              Self.validID(employeeID), Self.validID(departmentID), Self.validID(jobRoleID),
              previousAssignmentID.map(Self.validID) ?? true, Self.validDate(startsOn) else { throw Invalid.request }
    }
    private static func validID(_ value: String) -> Bool {
        value.utf8.count == 36 && value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil
    }
    private static func validDate(_ value: String) -> Bool {
        guard value.utf8.count == 10, value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        let y = parts[0], m = parts[1], d = parts[2]
        guard y >= 1, (1...12).contains(m) else { return false }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        return (1...[31,leap ? 29 : 28,31,30,31,30,31,31,30,31,30,31][m-1]).contains(d)
    }
    private enum Invalid: Error { case request }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
