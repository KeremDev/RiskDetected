import Foundation
@main enum MutationOutcomeCheck {
    static func main() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        for c in cases {
            let data = try JSONSerialization.data(withJSONObject: c["input"]!, options: [.fragmentsAllowed])
            let value = IsgMutationOutcome.parse(status: c["status"] as! Int, data: data)
            guard (value != nil) == (c["valid"] as! Bool) else { fatalError("Outcome mismatch: \(c["id"]!)") }
            if let v = value {
                let summary = [v.outcome,v.code ?? "",v.version.map(String.init) ?? "",v.currentVersion.map(String.init) ?? "",v.projection ?? "",v.retryAfterSeconds.map(String.init) ?? ""].joined(separator: "|")
                guard summary == c["summary"] as! String else { fatalError("Value mismatch") }
            }
        }
        let transitions = root["transitions"] as! [[String: Any]]
        for c in transitions {
            let result = IsgMutationTransition.next(IsgMutationPhase(rawValue: c["phase"] as! String)!,IsgMutationEvent(rawValue: c["event"] as! String)!,sameContext: c["same_context"] as! Bool)
            guard result.phase.rawValue == c["next_phase"] as! String, result.effect == c["effect"] as! String else { fatalError("Transition mismatch: \(c["id"]!)") }
        }
        print("PASS Swift outcome: \(cases.count) response fixtures + \(transitions.count) transitions")
    }
}
