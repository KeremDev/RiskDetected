import Foundation

// The navigation model carries its own presentation titles. Compiling it on its
// own therefore needs the localisation entry point; this stub answers with the
// written fallback, and the corpus never reads a title.
enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key: String, table: RDLocalizationTable, fallback: String) -> String { fallback }
}

enum NovaSessionHostCorpus {
    struct Failure: Error, CustomStringConvertible { let description: String }

    static func verify(_ url: URL) throws -> (cases: Int, steps: Int) {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let identities = (root["identities"] as! [String: [String: String]]).mapValues {
            NovaSessionIdentity(userID: UUID(uuidString: $0["userID"]!)!, sessionID: UUID(uuidString: $0["sessionID"]!)!)
        }
        func destinations(_ raw: Any) -> Set<NovaDestination> {
            Set((raw as! [String]).map { NovaDestination(rawValue: $0)! })
        }
        let cases = root["cases"] as! [[String: Any]]
        var count = 0
        for test in cases {
            var host = NovaSessionHost(implemented: destinations(test["implemented"]!))
            var tickets: [String: NovaAvailabilityTicket] = [:]
            var epochs: [String: String] = [:]
            var value: NovaScopedValue<String>?
            for (index, action) in (test["steps"] as! [[String: Any]]).enumerated() {
                let previousEpoch = host.navigation.epoch
                let from = (action["from"] as? String).map { epochs[$0]! } ?? previousEpoch
                switch action["op"] as! String {
                case "adopt": host.adopt((action["identity"] as? String).map { identities[$0]! })
                case "request":
                    let key = action["key"] as! String
                    tickets[key] = host.beginAvailabilityRefresh()
                    epochs[key] = host.navigation.epoch
                case "resolve":
                    host.resolve(tickets[action["key"] as! String]!, ownerID: identities[action["owner"] as! String]!.userID,
                        enabled: destinations(action["enabled"]!))
                case "fail": host.fail(tickets[action["key"] as! String]!)
                case "navigate": host.apply(.navigate(NovaDestination(rawValue: action["destination"] as! String)!), from: from)
                case "open": host.apply(.open(NovaOverlay(rawValue: action["panel"] as! String)!), from: from)
                case "publish":
                    if let next = host.scope(action["text"] as! String, from: from) { value = next }
                default: throw Failure(description: "Unknown fixture operation")
                }
                let actual: [String: Any] = ["phase": host.phase.rawValue, "current": host.navigation.current.rawValue,
                    "overlay": host.navigation.overlay?.rawValue as Any? ?? NSNull(),
                    "available": host.navigation.available.map(\.rawValue).sorted(), "pending": host.pending != nil,
                    "value": host.value(from: value) as Any? ?? NSNull(), "epochChanged": previousEpoch != host.navigation.epoch]
                let expected = action["expected"] as! [String: Any]
                guard NSDictionary(dictionary: actual).isEqual(to: expected) else {
                    throw Failure(description: "\(test["id"]!) step \(index): expected \(expected), actual \(actual)")
                }
                count += 1
            }
        }
        return (cases.count, count)
    }
}
