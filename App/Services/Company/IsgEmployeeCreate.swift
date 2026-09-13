import Foundation

/// Simple company intake; no employment dates, required job, or required department.
struct IsgEmployeeCreate: Decodable, Equatable {
    let context: IsgMutationContext
    let fullName: String
    let department: Department?
    enum Department: Equatable { case existing(String), new(String) }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        guard Set(c.allKeys.map(\.stringValue)).isSubset(of: ["context", "full_name", "department"]) else { throw Invalid.input }
        context = try c.decode(IsgMutationContext.self, forKey: Key("context"))
        guard context.scope.kind == "company", context.scope.workplaceID == nil, context.expectedVersion == 0,
              let name = Self.text(try c.decode(String.self, forKey: Key("full_name")), limit: 200) else { throw Invalid.input }
        fullName = name
        let hasNoDepartment = try !c.contains(Key("department")) || c.decodeNil(forKey: Key("department"))
        if hasNoDepartment { department = nil }
        else {
            let d = try c.nestedContainer(keyedBy: Key.self, forKey: Key("department"))
            let kind = try d.decode(String.self, forKey: Key("kind"))
            if kind == "existing", Set(d.allKeys.map(\.stringValue)) == ["kind", "id"] {
                let id = try d.decode(String.self, forKey: Key("id"))
                guard id.utf8.count == 36, id.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil else { throw Invalid.input }
                department = .existing(id)
            } else if kind == "new", Set(d.allKeys.map(\.stringValue)) == ["kind", "name"],
                      let value = Self.text(try d.decode(String.self, forKey: Key("name")), limit: 120) { department = .new(value) }
            else { throw Invalid.input }
        }
    }
    private static func text(_ input: String, limit: Int) -> String? {
        guard input.utf8.count <= 4096 else { return nil }
        let value = input.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.utf8.count <= limit,
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0.value == 0x200B || $0.value == 0xFEFF }) else { return nil }
        return value
    }
    private enum Invalid: Error { case input }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
