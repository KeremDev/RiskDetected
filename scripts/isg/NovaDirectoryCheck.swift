import Foundation

// The model carries its own presentation strings. Compiling it on its own
// therefore needs the localisation entry point; this stub answers with the
// written fallback.
enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key: String, table: RDLocalizationTable, fallback: String) -> String { fallback }
    static func format(_ key: String, table: RDLocalizationTable, fallback: String, arguments: [String]) -> String {
        String(format: fallback, arguments: arguments)
    }
}

@main struct NovaDirectoryCheck {
    @MainActor static func main() throws {
        let scope = NovaPersonnelScope(ownerID: UUID(), sessionID: UUID(), companyID: UUID(), epoch: UUID().uuidString)
        var checks = 0
        func check(_ value: Bool) { precondition(value); checks += 1 }
        for kind in NovaDirectoryKind.allCases {
            let i = NovaDirectoryIntent(scope: scope, kind: kind, operationID: UUID(), mutationID: UUID(), entityID: nil, expectedVersion: 0,
                body: ["name": .string("İş Sağlığı"), "code": .string("001"), "parent_id": .null, "is_archived": .bool(false)])
            let data = try JSONEncoder().encode(i)
            check(try JSONDecoder().decode(NovaDirectoryIntent.self, from: data) == i)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let body = json["body"] as! [String: Any]
            check(body["parent_id"] is NSNull)
            check(body["code"] as? String == "001")
            check(body["name"] as? String == "İş Sağlığı")
        }
        for raw in ["{}", "[]", "1.25"] {
            check((try? JSONDecoder().decode(NovaDirectoryValue.self, from: Data(raw.utf8))) == nil)
        }
        check(try JSONDecoder().decode(NovaDirectoryValue.self, from: Data("true".utf8)) == .bool(true))
        check(try JSONDecoder().decode(NovaDirectoryValue.self, from: Data("1".utf8)) == .number(1))
        check(try JSONDecoder().decode(NovaDirectoryValue.self, from: Data("\"1\"".utf8)) == .string("1"))
        print("Nova directory \(checks) checks PASS")
    }
}
