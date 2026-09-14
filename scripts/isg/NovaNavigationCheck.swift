import Foundation

// The navigation model carries its own presentation titles, and those titles
// are what the catalogue pins. Compiling it on its own therefore needs the
// localisation entry point; this stub answers with the written fallback, which
// is exactly the Turkish string the catalogue records.
enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key: String, table: RDLocalizationTable, fallback: String) -> String { fallback }
}

@main struct NovaNavigationCheck {
    static func main() throws {
        let root = CommandLine.arguments.dropFirst().first ?? "contracts/isg/v1"
        func json(_ path: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: root + path))) as! [String: Any]
        }
        let catalog = try json("/design/nova-navigation.json")
        let destinations = catalog["destinations"] as! [[String: String]]
        precondition(destinations.map { $0["id"]! } == NovaDestination.allCases.map(\.rawValue))
        for item in destinations {
            let d = NovaDestination(rawValue: item["id"]!)!
            precondition(d.title == item["title"] && d.tab.rawValue == item["tab"] && d.symbol == item["iosSymbol"])
        }
        precondition((catalog["tabs"] as! [[String: String]]) == NovaTab.allCases.map { ["id": $0.rawValue, "title": $0.title] })
        precondition(catalog["drawer"] as! [String] == NovaDestination.drawer.map(\.rawValue))
        precondition(catalog["quickAdd"] as! [String] == NovaDestination.quickAdd.map(\.rawValue))
        func values(_ raw: Any) -> Set<NovaDestination> { Set((raw as! [String]).map { NovaDestination(rawValue: $0)! }) }
        let cases = try json("/fixtures/nova-navigation.json")["cases"] as! [[String: Any]]
        var count = 0
        for test in cases {
            var state = NovaNavigationState(epoch: "account-a", available: values(test["available"]!))
            for (index, action) in (test["steps"] as! [[String: Any]]).enumerated() {
                let from = action["from"] as! String
                switch action["op"] as! String {
                case "select": state.apply(.select(NovaTab(rawValue: action["arg"] as! String)!), from: from)
                case "open": state.apply(.open(NovaOverlay(rawValue: action["arg"] as! String)!), from: from)
                case "navigate": state.apply(.navigate(NovaDestination(rawValue: action["arg"] as! String)!), from: from)
                case "back": state.apply(.back, from: from)
                case "dismiss": state.apply(.dismiss, from: from)
                case "availability": state.updateAvailability(values(action["arg"]!), from: from)
                case "reset":
                    let arg = action["arg"] as! [String: Any]
                    state.resetAccount(to: arg["epoch"] as! String, available: values(arg["available"]!))
                case "path":
                    let arg = action["arg"] as! [String: Any]
                    state.acceptBackPath((arg["path"] as! [String]).map { NovaDestination(rawValue: $0)! }, tab: NovaTab(rawValue: arg["tab"] as! String)!, from: from)
                default: fatalError("Unknown fixture operation")
                }
                let actual: [String: Any] = ["epoch": state.epoch, "selected": state.selected.rawValue,
                    "overlay": state.overlay.map { $0.rawValue as Any } ?? NSNull(),
                    "current": state.current.rawValue, "canGoBack": state.canGoBack,
                    "paths": Dictionary(uniqueKeysWithValues: NovaTab.allCases.map { ($0.rawValue, state.paths[$0]!.map(\.rawValue)) })]
                precondition(NSDictionary(dictionary: actual).isEqual(to: action["expected"] as! [String: Any]), "\(test["id"]!) step \(index): \(actual)")
                precondition(state.canOpen(state.current), "Current destination must remain available")
                count += 1
            }
        }
        print("NOVA navigation PASS: catalog + \(cases.count) scenarios / \(count) state transitions")
    }
}
