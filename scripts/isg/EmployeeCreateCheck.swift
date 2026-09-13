import Foundation
@main enum EmployeeCreateCheck {
    static func main() throws {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let cases = root["cases"] as! [[String: Any]]
        for fixture in cases {
            let data = try JSONSerialization.data(withJSONObject: fixture["input"]!, options: [.fragmentsAllowed])
            let value = try? JSONDecoder().decode(IsgEmployeeCreate.self, from: data)
            guard (value != nil) == fixture["valid"] as! Bool else { fatalError("Employee fixture mismatch: \(fixture["id"]!)") }
            if let value { guard value.fullName == fixture["normalized_name"] as! String else { fatalError("Normalization mismatch") } }
        }
        print("Swift employee intake: \(cases.count) PASS")
    }
}
