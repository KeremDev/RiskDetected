import Foundation

@main struct IsgPasswordRulesCheck {
    struct Corpus: Decodable { let cases: [Entry] }
    struct Entry: Decodable { let id: String; let password: String; let valid: Bool }
    static func main() throws {
        guard CommandLine.arguments.count == 2 else { fatalError("Fixture path required") }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let corpus = try JSONDecoder().decode(Corpus.self, from: data)
        for row in corpus.cases {
            guard IsgPasswordRules(row.password).valid == row.valid else { fatalError("Password rules mismatch: \(row.id)") }
        }
        print("Password rules: \(corpus.cases.count) PASS; client policy only, not server enforcement")
    }
}
