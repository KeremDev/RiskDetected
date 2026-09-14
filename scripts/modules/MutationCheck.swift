import Foundation

enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key: String, table: RDLocalizationTable, fallback: String) -> String { fallback }
}
struct NovaSessionIdentity { let userID: UUID; let sessionID: UUID }
enum PersonnelRPCValue: Equatable, Encodable {
    case string(String), number(Int64), null
    indirect case object([String: PersonnelRPCValue])
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .object(let v): try c.encode(v)
        }
    }
    static func id(_ value: UUID) -> Self { .string(value.uuidString.lowercased()) }
}
@MainActor protocol PersonnelPendingStorage {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func remove(account: String) throws
}
@MainActor final class KeychainPersonnelPendingStorage: PersonnelPendingStorage {
    var values: [String: Data] = [:]
    init(service: String) {}
    func read(account: String) throws -> Data? { values[account] }
    func write(_ data: Data, account: String) throws { values[account] = data }
    func remove(account: String) throws { values.removeValue(forKey: account) }
}
enum NovaDayField {
    static func date(_ value: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: value)
    }
}
@main struct MutationCheck {
 @MainActor static func main() async throws {
  let storage = KeychainPersonnelPendingStorage(service: "test")
  let identity = NovaSessionIdentity(userID: UUID(), sessionID: UUID())
  let company = UUID()
  var sent: [[String: PersonnelRPCValue]] = []
  var fail = true
  var current = true
  func send(_ who: NovaSessionIdentity, _ value: String) async throws -> Int {
   try await NovaModuleMutationJournal.run(function: "test", identity: who, company: company,
    action: "record", payload: ["value": .string(value)], rpc: { _, args in
     sent.append(args)
     if fail { throw NSError(domain: "network", code: 1) }
     return Data("7".utf8)
    }, validate: { if !current { throw NSError(domain: "session", code: 1) } },
    decode: { try JSONDecoder().decode(Int.self, from: $0) }, storage: storage)
  }
  do { _ = try await send(identity,"a") } catch {}
  let first=sent.last!; precondition(storage.values.count==1)
  do { _ = try await send(identity,"a") } catch {}
  precondition(sent.last! == first)
  do { _ = try await send(identity,"b") } catch {}
  precondition(sent.last!["p_mutation"] != first["p_mutation"])
  let other=NovaSessionIdentity(userID: UUID(),sessionID: UUID())
  do { _ = try await send(other,"a") } catch {}
  precondition(sent.last!["p_mutation"] != first["p_mutation"])
  fail=false
  let result=try await send(identity,"a"); precondition(result==7 && sent.last! == first)
  precondition(storage.values.count==2)
  _ = try await send(identity,"a")
  precondition(sent.last!["p_mutation"] != first["p_mutation"])
  current=false; let before=sent.count
  do { _ = try await send(identity,"a"); fatalError() } catch {}
  precondition(sent.count==before)
  print("PASS: 8 module mutation journal checks")
 }
}
