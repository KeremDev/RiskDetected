import Foundation
import Security

/// JSON scalars preserve explicit SQL NULL arguments (Encodable optionals omit keys).
enum PersonnelRPCValue: Encodable, Equatable {
    case string(String), number(Int64), bool(Bool), null
    /// A jsonb argument. The server validates its keys against a per-action
    /// allowlist, so this is a transport shape and never a free-form escape.
    indirect case object([String: PersonnelRPCValue])
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    static func id(_ value: UUID?) -> Self { value.map { .string($0.uuidString.lowercased()) } ?? .null }
}

@MainActor protocol PersonnelPendingStorage {
    func read(account: String) throws -> Data?
    func write(_ data: Data, account: String) throws
    func remove(account: String) throws
}

/// Device-only Keychain; no token, analytics event, Cloud sync, or plain preferences.
@MainActor final class KeychainPersonnelPendingStorage: PersonnelPendingStorage {
    private let service: String
    init(service: String = "com.riskdetected.personnel.pending.v1") { self.service = service }
    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: account, kSecAttrSynchronizable as String: false]
    }
    func read(account: String) throws -> Data? {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = value as? Data, data.count <= 16384 else { throw NovaPersonnelFailure.unavailable }
        return data
    }
    func write(_ data: Data, account: String) throws {
        guard data.count <= 16384 else { throw NovaPersonnelFailure.validation }
        let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(query(account).merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw NovaPersonnelFailure.unavailable }
        } else if status != errSecSuccess { throw NovaPersonnelFailure.unavailable }
    }
    func remove(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw NovaPersonnelFailure.unavailable }
    }
}

/// SDK/session adapter. Do not instantiate at a production root until its rollout gate is ready.
@MainActor final class NovaPersonnelService {
    private static var inFlight = Set<String>()
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isCurrent: (NovaPersonnelScope) -> Bool
    private let storage: any PersonnelPendingStorage
    init(rpc: @escaping RPC, isCurrent: @escaping (NovaPersonnelScope) -> Bool, storage: any PersonnelPendingStorage) {
        self.rpc = rpc; self.isCurrent = isCurrent; self.storage = storage
    }
    static func sessionID(_ token: String) -> UUID? {
        let pieces = token.split(separator: "."); guard pieces.count == 3 else { return nil }
        var raw = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        raw += String(repeating: "=", count: (4 - raw.count % 4) % 4)
        guard let data = Data(base64Encoded: raw), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = claims["session_id"] as? String else { return nil }
        return UUID(uuidString: value) // Local identity correlation only; server verifies signature/freshness.
    }
    var client: NovaPersonnelClient {
        NovaPersonnelClient(employees: { scope, query, archived, cursor in
            let page: EmployeePage = try await self.read(scope, kind: "employees", query: query, archived: archived, cursor: cursor)
            let rows = try page.rows.map { try $0.row(scope) }
            try Self.pageCheck(rows.map(\.id), next: page.next, after: cursor)
            guard archived || rows.allSatisfy({ !$0.isArchived }) else { throw NovaPersonnelFailure.unavailable }
            return NovaEmployeePage(rows: rows, next: page.next)
        }, departments: { scope, query, cursor in
            let page: DepartmentPage = try await self.read(scope, kind: "departments", query: query, cursor: cursor)
            let rows = try page.rows.map { try $0.row(scope) }
            try Self.pageCheck(rows.map(\.id), next: page.next, after: cursor)
            return NovaDepartmentPage(rows: rows, next: page.next)
        }, detail: { scope, id in
            let dto: Employee = try await self.read(scope, kind: "detail", id: id)
            let row = try dto.row(scope); guard row.id == id else { throw NovaPersonnelFailure.unavailable }; return row
        }, save: { try await self.save($0) }, pending: { try self.pending($0) })
    }
    private func check(_ scope: NovaPersonnelScope) throws {
        try Task.checkCancellation(); guard isCurrent(scope) else { throw NovaPersonnelFailure.denied }
    }
    private func read<T: Decodable>(_ scope: NovaPersonnelScope, kind: String, query: String = "", archived: Bool = false, cursor: UUID? = nil, id: UUID? = nil) async throws -> T {
        try check(scope); guard query.utf8.count <= 200 else { throw NovaPersonnelFailure.validation }
        let data = try await rpc("isg_personnel_read_v1", ["p_company": .id(scope.companyID), "p_kind": .string(kind), "p_query": .string(query), "p_archived": .bool(archived), "p_after": .id(cursor), "p_id": .id(id)])
        try check(scope); guard data.count <= 262144 else { throw NovaPersonnelFailure.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
    static func arguments(_ intent: NovaEmployeeIntent) throws -> [String: PersonnelRPCValue] {
        guard intent.expectedVersion >= 0, intent.expectedVersion < 9007199254740991,
              (intent.action == .create ? intent.employeeID == nil && intent.expectedVersion == 0 : intent.employeeID != nil) else { throw NovaPersonnelFailure.validation }
        var department: UUID?, departmentName: String?, change = true
        switch intent.department {
        case .keep: change = false
        case .none: break
        case .existing(let id): department = id
        case .new(let name): departmentName = try text(name, limit: 120)
        }
        if intent.action == .create && !change { throw NovaPersonnelFailure.validation }
        if intent.action == .archive || intent.action == .restore { change = false; department = nil; departmentName = nil }
        return ["p_company": .id(intent.scope.companyID), "p_action": .string(intent.action.rawValue),
            "p_operation": .id(intent.operationID), "p_mutation": .id(intent.mutationID), "p_employee": .id(intent.employeeID),
            "p_expected": .number(intent.expectedVersion), "p_name": [.archive, .restore].contains(intent.action) ? .null : .string(try text(intent.name, limit: 200)),
            "p_change_department": .bool(change), "p_department": .id(department), "p_department_name": departmentName.map(PersonnelRPCValue.string) ?? .null]
    }
    private static func text(_ input: String, limit: Int) throws -> String {
        let value = input.precomposedStringWithCanonicalMapping.replacingOccurrences(of: "[ \\t\\r\\n]+", with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        guard input.utf8.count <= 4096, value.utf8.count <= limit, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0.value == 0x200B || $0.value == 0xFEFF }) else { throw NovaPersonnelFailure.validation }
        return value
    }
    private func account(_ scope: NovaPersonnelScope) -> String { "\(scope.ownerID.uuidString.lowercased()):\(scope.companyID.uuidString.lowercased())" }
    private struct Pending: Codable { let schema: Int; let intent: NovaEmployeeIntent }
    private func pending(_ scope: NovaPersonnelScope) throws -> NovaEmployeeIntent? {
        try check(scope); guard let data = try storage.read(account: account(scope)) else { return nil }
        let saved = try JSONDecoder().decode(Pending.self, from: data)
        guard saved.schema == 1, saved.intent.scope.ownerID == scope.ownerID, saved.intent.scope.companyID == scope.companyID else { throw NovaPersonnelFailure.unavailable }
        let old = saved.intent
        let rebound = NovaEmployeeIntent(operationID: old.operationID, mutationID: old.mutationID, scope: scope, action: old.action,
            employeeID: old.employeeID, expectedVersion: old.expectedVersion, name: old.name, department: old.department)
        _ = try Self.arguments(rebound); return rebound
    }
    private func save(_ intent: NovaEmployeeIntent) async throws -> NovaEmployeeCommit {
        try check(intent.scope); let args = try Self.arguments(intent)
        let key = account(intent.scope)
        guard Self.inFlight.insert(key).inserted else { throw NovaPersonnelFailure.unavailable }
        defer { Self.inFlight.remove(key) }
        if let existing = try pending(intent.scope), try Self.arguments(existing) != args { throw NovaPersonnelFailure.unavailable }
        try storage.write(JSONEncoder().encode(Pending(schema: 1, intent: intent)), account: account(intent.scope))
        do {
            let data = try await rpc("isg_personnel_mutate_v1", args)
            try check(intent.scope)
            guard data.count <= 16384 else { throw NovaPersonnelFailure.unavailable }
            let dto = try JSONDecoder().decode(Commit.self, from: data)
            guard dto.schema_version == 1, dto.operation_id == intent.operationID, dto.owner_id == intent.scope.ownerID,
                  dto.company_id == intent.scope.companyID, intent.employeeID == nil || dto.employee_id == intent.employeeID,
                  dto.version == (intent.action == .create ? 0 : intent.expectedVersion + 1), dto.is_archived == (intent.action == .archive) else { throw NovaPersonnelFailure.unavailable }
            try storage.remove(account: account(intent.scope))
            return .init(operationID: dto.operation_id, id: dto.employee_id, ownerID: dto.owner_id, companyID: dto.company_id, version: dto.version, isArchived: dto.is_archived)
        } catch {
            // A late scope change or cancellation leaves the original account's durable receipt request intact.
            if isCurrent(intent.scope), !Task.isCancelled, let failure = error as? NovaPersonnelFailure, failure != .unavailable {
                try storage.remove(account: account(intent.scope))
            }
            throw error
        }
    }
    private static func pageCheck(_ ids: [UUID], next: UUID?, after: UUID?) throws {
        let keys = ids.map { $0.uuidString.lowercased() }
        guard ids.count <= 50, Set(ids).count == ids.count, keys == keys.sorted(), next == nil || next == ids.last,
              after == nil || keys.allSatisfy({ $0 > after!.uuidString.lowercased() }) else { throw NovaPersonnelFailure.unavailable }
    }
    private struct EmployeePage: Decodable { let rows: [Employee]; let next: UUID? }
    private struct DepartmentPage: Decodable { let rows: [Department]; let next: UUID? }
    private struct Department: Decodable {
        let id: UUID; let owner_id: UUID; let company_id: UUID; let name: String
        func row(_ scope: NovaPersonnelScope) throws -> NovaDepartmentRow {
            guard owner_id == scope.ownerID, company_id == scope.companyID else { throw NovaPersonnelFailure.denied }
            return .init(id: id, ownerID: owner_id, companyID: company_id, name: name)
        }
    }
    private struct Employee: Decodable {
        let id: UUID; let owner_id: UUID; let company_id: UUID; let name: String; let department_id: UUID?; let department_name: String?; let job_title: String?; let version: Int64; let is_archived: Bool
        func row(_ scope: NovaPersonnelScope) throws -> NovaEmployeeRow {
            guard owner_id == scope.ownerID, company_id == scope.companyID, (0...9007199254740991).contains(version),
                  (department_id == nil) == (department_name == nil) else { throw NovaPersonnelFailure.unavailable }
            return .init(id: id, ownerID: owner_id, companyID: company_id, name: name, departmentID: department_id, departmentName: department_name, jobTitle: job_title, version: version, isArchived: is_archived)
        }
    }
    private struct Commit: Decodable { let schema_version: Int; let operation_id: UUID; let employee_id: UUID; let owner_id: UUID; let company_id: UUID; let version: Int64; let is_archived: Bool }
}
