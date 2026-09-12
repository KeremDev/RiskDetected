import Foundation

/// Transport validation only; a valid scope never grants database access.
struct IsgMutationContext: Decodable, Equatable {
    let schemaVersion: Int
    let operationID: String
    let clientMutationID: String
    let platform: String
    let clientBuild: Int
    let expectedVersion: Int64
    let scope: Scope

    struct Scope: Decodable, Equatable {
        let kind: String
        let companyID: String?
        let workplaceID: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            kind = try c.decode(String.self, forKey: Key("kind"))
            if kind == "personal" {
                guard Set(c.allKeys.map(\.stringValue)) == ["kind"] else { throw Invalid.context }
                companyID = nil
                workplaceID = nil
            } else if kind == "company" {
                guard Set(c.allKeys.map(\.stringValue)).isSubset(of: ["kind", "company_id", "workplace_id"]) else { throw Invalid.context }
                let company = try c.decode(String.self, forKey: Key("company_id"))
                guard IsgMutationContext.validID(company) else { throw Invalid.context }
                companyID = company
                if c.contains(Key("workplace_id")) {
                    let workplace = try c.decode(String.self, forKey: Key("workplace_id"))
                    guard IsgMutationContext.validID(workplace) else { throw Invalid.context }
                    workplaceID = workplace
                } else { workplaceID = nil }
            } else { throw Invalid.context }
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        let allowed: Set<String> = ["schema_version", "operation_id", "client_mutation_id", "platform", "client_build", "expected_version", "scope"]
        guard Set(c.allKeys.map(\.stringValue)) == allowed else { throw Invalid.context }
        schemaVersion = try c.decode(Int.self, forKey: Key("schema_version"))
        operationID = try c.decode(String.self, forKey: Key("operation_id"))
        clientMutationID = try c.decode(String.self, forKey: Key("client_mutation_id"))
        platform = try c.decode(String.self, forKey: Key("platform"))
        clientBuild = try c.decode(Int.self, forKey: Key("client_build"))
        expectedVersion = try c.decode(Int64.self, forKey: Key("expected_version"))
        scope = try c.decode(Scope.self, forKey: Key("scope"))
        guard schemaVersion == 1, Self.validID(operationID), Self.validID(clientMutationID),
              ["ios", "android"].contains(platform), (1...2147483647).contains(clientBuild),
              (0...9007199254740991).contains(expectedVersion) else { throw Invalid.context }
    }

    private static func validID(_ value: String) -> Bool {
        value.utf8.count == 36 && value.range(of: "^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil
    }
    private enum Invalid: Error { case context }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}
