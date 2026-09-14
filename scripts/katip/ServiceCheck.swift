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
@main struct ServiceCheck {
    @MainActor static func main() async throws {
        let identity = NovaSessionIdentity(userID: UUID(), sessionID: UUID())
        let company = UUID()
        var sent: [[String: PersonnelRPCValue]] = []
        var validSession = true
        var fail = false
        let storage = KeychainPersonnelPendingStorage(service: "test")
        let service = NovaKatipService(rpc: { _, args in
            sent.append(args)
            if fail { throw NovaKatipFailure.unavailable }
            return Data("{}".utf8)
        }, isSession: { _ in validSession }, storage: storage)
        var base = NovaKatipDraft()
        base.workplaceID = UUID(); base.counterparty = "Firma"; base.expertContact = "Uzman"
        base.scope = "İSG hizmeti"; base.startsOn = "2026-09-14"
        var checks = 0
        func rejects(_ draft: NovaKatipDraft, _ expected: NovaKatipFailure) async throws {
            let count = sent.count
            do { _ = try await service.record(identity, company: company, draft: draft); preconditionFailure("Expected rejection") }
            catch let error as NovaKatipFailure { precondition(error == expected) }
            precondition(sent.count == count); checks += 1
        }
        for minutes in ["abc", "0", "-1", "1.5", "100001", "99999999999999999999999"] {
            var draft = base; draft.declaredMonthlyMinutes = minutes
            try await rejects(draft, .validation)
        }
        for date in ["abc", "2026-02-30"] {
            var draft = base; draft.endsBefore = date
            try await rejects(draft, .validation)
        }
        for date in ["2026-09-13", "2026-09-14"] {
            var draft = base; draft.endsBefore = date
            try await rejects(draft, .endsBeforeStart)
        }
        _ = try await service.record(identity, company: company, draft: base)
        guard case .object(let empty) = sent.last?["p_payload"] else { fatalError() }
        precondition(empty["ends_before"] == nil && empty["declared_monthly_minutes"] == nil); checks += 1
        for minutes in [1,12,100000] {
            var draft = base; draft.declaredMonthlyMinutes = " \(minutes) "; draft.endsBefore = " 2026-10-14 "
            _ = try await service.record(identity, company: company, draft: draft)
            guard case .object(let payload) = sent.last?["p_payload"] else { fatalError() }
            precondition(payload["declared_monthly_minutes"] == .number(Int64(minutes)))
            precondition(payload["ends_before"] == .string("2026-10-14")); checks += 1
        }
        fail = true
        do { _ = try await service.record(identity, company: company, draft: base) } catch {}
        let original = sent.last!
        precondition(!storage.values.isEmpty)
        var changed = base; changed.scope = "Değişik kapsam"
        try await rejects(changed, .conflict)
        let other = NovaSessionIdentity(userID: UUID(), sessionID: UUID())
        let otherPending = try service.hasPending(other)
        precondition(!otherPending); checks += 1
        fail = false
        let restored = NovaKatipService(rpc: { _, args in
            precondition(args["p_mutation"] == original["p_mutation"])
            precondition(args["p_operation"] == original["p_operation"])
            return Data("{}".utf8)
        }, isSession: { _ in true }, storage: storage)
        let hasPending = try restored.hasPending(identity)
        precondition(hasPending)
        _ = try await restored.resume(identity)
        precondition(storage.values.isEmpty); checks += 1
        let contract = NovaKatipContract(id: UUID(), companyID: company, companyName: nil,
            workplaceID: base.workplaceID, workplaceName: nil, counterparty: "Firma", expertContact: "Uzman",
            scope: "İSG", startsOn: base.startsOn, endsBefore: nil, term: .openEnded, state: .active,
            group: .current, noticeDays: 30, declaredMonthlyMinutes: nil, declaredNote: nil,
            requiredServiceTimeKnown: false, contractStored: false, contractLocation: nil,
            officialIntegration: false, officialSubmissionMade: false, documentVersion: 4)
        for file in [UUID?.some(UUID()), nil] {
            fail = true
            do { _ = try await service.linkDocument(identity, contract: contract, file: file) } catch {}
            let originalLink = sent.last!
            guard case .object(let linkPayload) = originalLink["p_payload"] else { fatalError() }
            precondition(linkPayload["expected_version"] == .number(4))
            precondition(linkPayload["file_entry_id"] == (file.map { .id($0) } ?? .null))
            let recovery = NovaKatipService(rpc: { _, args in
                precondition(args == originalLink)
                return Data("{}".utf8)
            }, isSession: { _ in true }, storage: storage)
            _ = try await recovery.resume(identity)
            precondition(storage.values.isEmpty); checks += 1
        }
        validSession = false
        try await rejects(base, .denied)
        print("PASS: \(checks) KATIP client behavior checks")
    }
}
