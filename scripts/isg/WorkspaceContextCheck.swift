import Foundation

@main enum WorkspaceContextCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("fixture path required") }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        for fixture in cases {
            let input = try JSONSerialization.data(withJSONObject: fixture["input"]!, options: [.fragmentsAllowed])
            let parsed = try? JSONDecoder().decode(IsgWorkspaceContext.self, from: input)
            precondition((parsed != nil) == (fixture["valid"] as! Bool), fixture["id"] as! String)
        }
        print("PASS Swift workspace context: \(cases.count) shared fixtures")
    }
}
