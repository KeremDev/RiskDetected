import Foundation
import Supabase

@MainActor final class NovaDirectoryService {
    private let expertTicket = NovaExpertTransport.shared.capture()
    private static var inFlight = Set<String>()
    private let isCurrent: (NovaPersonnelScope) -> Bool
    private let sdk: SupabaseClient
    private let storage: any PersonnelPendingStorage
    init(sdk: SupabaseClient, isCurrent: @escaping (NovaPersonnelScope) -> Bool, storage: any PersonnelPendingStorage) {
        self.sdk = sdk; self.isCurrent = isCurrent; self.storage = storage
    }
    private func account(_ scope: NovaPersonnelScope) -> String { "directory:\(scope.ownerID.uuidString.lowercased()):\(scope.companyID.uuidString.lowercased())" }
    private func check(_ scope: NovaPersonnelScope) throws {
        try Task.checkCancellation()
        guard isCurrent(scope), sdk.auth.currentUser?.id == scope.ownerID,
              let session = sdk.auth.currentSession,
              NovaPersonnelService.sessionID(session.accessToken) == scope.sessionID else { throw NovaPersonnelFailure.denied }
    }
    private struct Read: Encodable {
        let p_company: String; let p_kind: String; let p_parent: PersonnelRPCValue; let p_after: PersonnelRPCValue; let p_archived: Bool
    }
    private struct Write: Encodable {
        let p_company: String; let p_kind: String; let p_operation: String; let p_mutation: String; let p_id: PersonnelRPCValue
        let p_expected: Int64; let p_body: [String: NovaDirectoryValue]
        init(_ value: NovaDirectoryIntent) {
            p_company = value.scope.companyID.uuidString.lowercased(); p_kind = value.kind.rawValue
            p_operation = value.operationID.uuidString.lowercased(); p_mutation = value.mutationID.uuidString.lowercased()
            p_id = .id(value.entityID); p_expected = value.expectedVersion; p_body = value.body
        }
    }
    private struct Page: Decodable { let rows: [[String: NovaDirectoryValue]]; let next: UUID?; let parent_version: Int64? }
    private struct Commit: Decodable { let schema_version: Int; let operation_id: UUID; let entity_id: UUID; let owner_id: UUID; let company_id: UUID; let kind: String; let version: Int64 }
    private struct Saved: Codable { let schema: Int; let intent: NovaDirectoryIntent }
    var client: NovaDirectoryClient {
        .init(read: { scope, kind, parent, after, archived in
            try self.check(scope)
            let data = try await NovaExpertTransport.shared.execute("isg_directory_read_v1", params: Read(p_company: scope.companyID.uuidString.lowercased(), p_kind: kind.rawValue, p_parent: .id(parent), p_after: .id(after), p_archived: archived), ticket: self.expertTicket)
            guard data.count <= 262144 else { throw NovaPersonnelFailure.unavailable }
            let dto = try JSONDecoder().decode(Page.self, from: data)
            try self.check(scope)
            let rows = try dto.rows.map { raw -> NovaDirectoryRow in
                guard raw["owner_id"]?.text == scope.ownerID.uuidString.lowercased(), raw["company_id"]?.text == scope.companyID.uuidString.lowercased(),
                      let idString = raw["id"]?.text, let id = UUID(uuidString: idString) else { throw NovaPersonnelFailure.unavailable }
                return .init(id: id, fields: raw)
            }
            let ids = rows.map { $0.id.uuidString.lowercased() }
            guard rows.count <= 50, Set(ids).count == ids.count, ids == ids.sorted(), dto.next == nil || dto.next == rows.last?.id,
                  after == nil || ids.allSatisfy({ $0 > after!.uuidString.lowercased() }) else { throw NovaPersonnelFailure.unavailable }
            return .init(rows: rows, next: dto.next, parentVersion: dto.parent_version)
        }, save: { try await self.save($0) }, pending: { try self.pending($0) })
    }
    private func pending(_ scope: NovaPersonnelScope) throws -> NovaDirectoryIntent? {
        try check(scope); guard let data = try storage.read(account: account(scope)) else { return nil }
        let value = try JSONDecoder().decode(Saved.self, from: data)
        guard value.schema == 1, value.intent.scope.ownerID == scope.ownerID, value.intent.scope.companyID == scope.companyID else { throw NovaPersonnelFailure.unavailable }
        let i = value.intent
        return .init(scope: scope, kind: i.kind, operationID: i.operationID, mutationID: i.mutationID, entityID: i.entityID, expectedVersion: i.expectedVersion, body: i.body)
    }
    private func save(_ intent: NovaDirectoryIntent) async throws -> NovaDirectoryCommit {
        try check(intent.scope)
        guard (0..<9007199254740991).contains(intent.expectedVersion), intent.body.count <= 12 else { throw NovaPersonnelFailure.validation }
        let key = account(intent.scope); guard Self.inFlight.insert(key).inserted else { throw NovaPersonnelFailure.unavailable }
        defer { Self.inFlight.remove(key) }
        if let old = try pending(intent.scope), old != intent { throw NovaPersonnelFailure.unavailable }
        try storage.write(JSONEncoder().encode(Saved(schema: 1, intent: intent)), account: key)
        do {
            let data = try await NovaExpertTransport.shared.execute("isg_directory_mutate_v1", params: Write(intent), ticket: self.expertTicket)
            guard data.count <= 16384 else { throw NovaPersonnelFailure.unavailable }
            let r = try JSONDecoder().decode(Commit.self, from: data)
            try check(intent.scope)
            let expected = intent.entityID == nil && (intent.kind.isCatalog || intent.kind == .engagements) ? 0 : intent.expectedVersion + 1
            guard r.schema_version == 1, r.operation_id == intent.operationID, r.owner_id == intent.scope.ownerID, r.company_id == intent.scope.companyID,
                  r.kind == intent.kind.rawValue, intent.entityID == nil || intent.entityID == r.entity_id, r.version == expected else { throw NovaPersonnelFailure.unavailable }
            try storage.remove(account: key)
            NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: intent.scope.ownerID)
            return .init(operationID: r.operation_id, entityID: r.entity_id, version: r.version)
        } catch {
            try Task.checkCancellation()
            try check(intent.scope)
            if let error = error as? PostgrestError, let code = error.code,
               ["23503", "23505", "23514", "23P01", "22007", "22008", "22P02"].contains(code) ||
               (["P0001", "28000"].contains(code) && Self.terminal.contains(error.message)) {
                // These SQL transaction errors are definite rollbacks; unknown network failures are not.
                try storage.remove(account: key)
                throw NovaPersonnelFailure.validation
            }
            throw NovaPersonnelFailure.unavailable
        }
    }
    private static let terminal: Set<String> = ["AUTH_REQUIRED", "ACCESS_DENIED", "PAID_PLAN_REQUIRED", "VALIDATION_ERROR", "VERSION_CONFLICT", "DEPARTMENT_SCOPE_INVALID", "EMPLOYER_SCOPE_INVALID", "ASSIGNMENT_SCOPE_INVALID", "CONTEXT_SCOPE_INVALID", "TIMEZONE_INVALID", "IMMUTABLE_SCOPE", "HIERARCHY_CYCLE", "ASSIGNMENT_IMMUTABLE", "CONTEXT_IMMUTABLE", "EMPLOYMENT_INTERVAL_INVALID", "ASSIGNMENT_CHANGE_REQUIRED"]
}
