import Foundation

// Compiles only the pure transport type, never launches the production app.
@main
enum MutationContextCheck {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Supply the shared fixture path") }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        var checked = 0
        for fixture in cases {
            let id = fixture["id"] as! String
            let expected = fixture["valid"] as! Bool
            let input = try JSONSerialization.data(withJSONObject: fixture["input"]!, options: [.fragmentsAllowed])
            let result = try? JSONDecoder().decode(IsgMutationContext.self, from: input)
            guard (result != nil) == expected else { fatalError("ISG fixture outcome mismatch: \(id)") }
            checked += 1
        }
        print("PASS Swift ISG context: \(checked) shared fixtures; no application launch or network")
    }
}
