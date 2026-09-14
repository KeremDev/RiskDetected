import Foundation

// Navigation's labels are not exercised by this Foundation-only service test.
enum RDLocalization {
    enum Table { case localizable }
    static func string(_ key: String, table: Table, fallback: String) -> String { fallback }
}
@MainActor final class PilotMemoryStorage: PersonnelPendingStorage {
    var values: [String: Data] = [:]
    var failWrite = false
    func read(account: String) throws -> Data? { values[account] }
    func write(_ data: Data, account: String) throws {
        if failWrite { throw NovaPersonnelFailure.unavailable }
        values[account] = data
    }
    func remove(account: String) throws { values[account] = nil }
}

@main struct NovaPilotCompanyCheck {
    @MainActor static func main() async throws {
        let identity = NovaSessionIdentity(userID: UUID(), sessionID: UUID())
        var current: NovaSessionIdentity? = identity
        let storage = PilotMemoryStorage()
        var mode = "timeout"
        var requests: [[String: PersonnelRPCValue]] = []
        var checks = 0
        func check(_ value: Bool) { precondition(value, "check \(checks + 1)"); checks += 1 }
        let intent = try NovaPilotCompanyIntent.make(ownerID: identity.userID, name: "  Yeni   Firma  ", hazard: "medium")
        check(intent.name == "Yeni Firma")
        for value in ["", "  ", String(repeating: "a", count: 201), "x\u{200b}"] {
            check((try? NovaPilotCompanyIntent.make(ownerID: identity.userID, name: value, hazard: "low")) == nil)
        }
        check((try? NovaPilotCompanyIntent.make(ownerID: identity.userID, name: "Firma", hazard: "unknown")) == nil)
        let company = UUID()
        func response(owner: UUID) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["schema_version": 1, "replayed": true,
                "company": ["id": company.uuidString, "user_id": owner.uuidString,
                    "name": "Güncel Ad", "hazard_class": "medium", "is_archived": false]])
        }
        let rpc: NovaPilotCompanyService.RPC = { endpoint, args in
            precondition(endpoint == "isg_pilot_company_create_v1")
            precondition(storage.values[identity.userID.uuidString.lowercased()] != nil)
            precondition(Set(args.keys) == Set(["p_mutation", "p_name", "p_hazard_class"]))
            requests.append(args)
            switch mode {
            case "timeout": throw URLError(.timedOut)
            case "invalid": return Data("{}".utf8)
            case "large": return Data(repeating: 32, count: 16385)
            case "other": return try response(owner: UUID())
            case "late": current = nil; return try response(owner: identity.userID)
            default: return try response(owner: identity.userID)
            }
        }
        func service() -> NovaPilotCompanyService { .init(rpc: rpc, currentIdentity: { current }, storage: storage) }
        check(try service().pending(identity: identity) == nil)
        storage.failWrite = true
        do { _ = try await service().create(intent, identity: identity); preconditionFailure() } catch {}
        check(requests.isEmpty)
        storage.failWrite = false
        for outcome in ["timeout", "invalid", "large", "other", "late"] {
            mode = outcome; current = identity
            do { _ = try await service().create(intent, identity: identity); preconditionFailure() } catch {}
            current = identity
            check(try service().pending(identity: identity) == intent)
        }
        check(requests.count == 5)
        check(requests.allSatisfy { $0 == requests.first })
        let changed = try NovaPilotCompanyIntent.make(ownerID: identity.userID, name: "Başka", hazard: "high")
        do { _ = try await service().create(changed, identity: identity); preconditionFailure() } catch {}
        check(requests.count == 5)
        let other = NovaSessionIdentity(userID: UUID(), sessionID: UUID())
        current = other
        check(try service().pending(identity: other) == nil)
        do { _ = try await service().create(intent, identity: other); preconditionFailure() } catch {}
        check(requests.count == 5)
        let relogin = NovaSessionIdentity(userID: identity.userID, sessionID: UUID())
        current = relogin
        do { _ = try await service().create(intent, identity: identity); preconditionFailure() } catch {}
        check(requests.count == 5)
        check(try service().pending(identity: relogin) == intent)
        mode = "success"
        let id = try await service().create(intent, identity: relogin)
        check(id == company)
        check(try service().pending(identity: relogin) == nil)
        check(requests.count == 6 && requests.last == requests.first)
        let profile = try NovaPilotCompanyIntent.makeProfile(ownerID: identity.userID, name: " Firma ", hazard: "low",
            sector: "  Metal  sanayi ", email: "info@example.test", employeeCount: "25", responsibleName: " Ada  Kaya ")
        check(profile.sector == "Metal sanayi" && profile.responsibleName == "Ada Kaya" && profile.employeeCount == 25)
        for sector in ["", "  ", String(repeating: "x", count: 121)] {
            check((try? NovaPilotCompanyIntent.makeProfile(ownerID: identity.userID, name: "Firma", hazard: "low", sector: sector, email: "", employeeCount: "", responsibleName: "")) == nil)
        }
        for count in ["-1", "1.5", "10000001", "abc"] {
            check((try? NovaPilotCompanyIntent.makeProfile(ownerID: identity.userID, name: "Firma", hazard: "low", sector: "Metal", email: "", employeeCount: count, responsibleName: "")) == nil)
        }
        check((try? NovaPilotCompanyIntent.makeProfile(ownerID: identity.userID, name: "Firma", hazard: "low", sector: "Metal", email: "bad", employeeCount: "", responsibleName: "")) == nil)
        let v2 = NovaPilotCompanyService(rpc: { endpoint, args in
            precondition(endpoint == "isg_pilot_company_create_v2" && args["p_sector"] == .string("Metal sanayi") && args["p_employee_count"] == .number(25))
            precondition(args["p_responsible_name"] == .string("Ada Kaya"))
            var json = try JSONSerialization.jsonObject(with: response(owner: identity.userID)) as! [String: Any]
            json["schema_version"] = 2
            return try JSONSerialization.data(withJSONObject: json)
        }, currentIdentity: { current }, storage: storage)
        check(try await v2.create(profile, identity: relogin) == company)
        check(try v2.pending(identity: relogin) == nil)
        print("\(checks) pilot company checks PASS")
    }
}
