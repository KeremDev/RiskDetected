import Foundation
@main enum AssignmentMoveCheck {
    static func main() throws {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        for fixture in cases {
            let data = try JSONSerialization.data(withJSONObject: fixture["input"]!, options: [.fragmentsAllowed])
            let value = try? JSONDecoder().decode(IsgAssignmentMove.self, from: data)
            guard (value != nil) == fixture["valid"] as! Bool else { fatalError("Assignment fixture mismatch: \(fixture["id"]!)") }
            if let value { guard value.context.operationID != value.context.clientMutationID else { fatalError("Distinct operation/mutation fixture lost") } }
        }
        print("Swift assignment move: \(cases.count) PASS")
    }
}
