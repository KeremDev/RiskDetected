import Foundation

@main struct NovaCompanyListCheck {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rowCatalog = root["rows"] as! [String: [String: Any]]
        let responses = root["responses"] as! [String: [Any]]
        let cases = root["cases"] as! [[String: Any]]
        func uuid(_ value: String) -> UUID { UUID(uuidString: value)! }
        func actor(_ key: String) -> NovaSessionIdentity? {
            if key == "out" { return nil }
            return .init(userID: uuid(key == "b" ? "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" : "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
                         sessionID: uuid(key == "a" ? "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa" : "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"))
        }
        func row(_ raw: [String: Any]) -> NovaOwnedCompany {
            .init(id: uuid(raw["id"] as! String), ownerID: uuid(raw["ownerID"] as! String), name: raw["name"] as! String,
                  detail: raw["detail"] as! String, isArchived: raw["isArchived"] as! Bool)
        }
        for test in cases {
            let name = test["id"] as! String
            var host = NovaSessionHost(implemented: [.companies])
            func ready(_ next: NovaSessionIdentity?, enabled: Bool = true) {
                host.adopt(next)
                if let next, let ticket = host.beginAvailabilityRefresh() {
                    host.resolve(ticket, ownerID: next.userID, enabled: enabled ? [.companies] : [])
                }
            }
            ready(actor("a"))
            var state = NovaCompanyListState()
            var tickets: [String: NovaCompanyListTicket] = [:]
            var captured: [String: UUID] = [:]
            var selected = false
            var archiveScope = false
            for step in test["steps"] as! [[String: Any]] {
                let key = step["key"] as? String ?? ""
                switch step["op"] as! String {
                case "begin":
                    archiveScope = step["archived"] as? Bool ?? false
                    tickets[key] = state.begin(host: host, includeArchived: archiveScope)
                case "filter": archiveScope = step["archived"] as! Bool
                case "complete":
                    let rows = responses[step["rows"] as! String]!.map { value in row((value as? String).map { rowCatalog[$0]! } ?? (value as! [String: Any])) }
                    state.complete(tickets[key]!, rows: rows, host: host)
                case "fail": state.fail(tickets[key]!, host: host)
                case "cancel": state.cancel(tickets[key]!, host: host)
                case "ready": ready(actor(step["actor"] as! String))
                case "adopt": host.adopt(actor(step["actor"] as! String))
                case "tokenRefresh": host.adopt(host.identity)
                case "hostRefresh": _ = host.beginAvailabilityRefresh()
                case "revoke": ready(host.identity, enabled: false)
                case "capture": captured[key] = state.content(host: host, includeArchived: archiveScope).requestID
                case "select": selected = state.select(uuid(rowCatalog[step["row"] as! String]!["id"] as! String), requestID: captured[key], host: host, includeArchived: archiveScope) != nil
                default: fatalError("Unknown company fixture operation: \(name)")
                }
            }
            let expected = test["expected"] as! [String: Any]
            let actual = state.content(host: host, includeArchived: archiveScope)
            let expectedIDs = (expected["rows"] as! [String]).map { uuid(rowCatalog[$0]!["id"] as! String) }
            precondition(actual.phase.rawValue == expected["phase"] as! String, "Phase: \(name)")
            precondition(actual.rows.map(\.id) == expectedIDs, "Rows: \(name)")
            precondition((state.pending != nil) == expected["pending"] as! Bool, "Pending: \(name)")
            precondition(selected == expected["selected"] as! Bool, "Selection: \(name)")
        }
        print("Company list: \(cases.count) PASS; current-host presentation boundary, not RLS or live UI acceptance")
    }
}
