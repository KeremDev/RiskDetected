import Foundation

@MainActor final class MemoryPersonnelStorage: PersonnelPendingStorage {
    var values: [String: Data] = [:]
    var writes = 0
    var failWrite = false
    func read(account: String) throws -> Data? { values[account] }
    func write(_ data: Data, account: String) throws { if failWrite { throw NovaPersonnelFailure.unavailable }; writes += 1; values[account] = data }
    func remove(account: String) throws { values[account] = nil }
}
@main struct NovaPersonnelServiceCheck {
    @MainActor static func main() async throws {
        let scope = NovaPersonnelScope(ownerID: UUID(), sessionID: UUID(), companyID: UUID(), epoch: "first")
        let intent = NovaEmployeeIntent(operationID: UUID(), mutationID: UUID(), scope: scope, action: .create, employeeID: nil, expectedVersion: 0, name: "Ada Kaya", department: .none)
        let storage = MemoryPersonnelStorage()
        var current = scope
        var requests: [[String: PersonnelRPCValue]] = []
        var outcome = "timeout"
        var checks = 0
        func check(_ condition: Bool) { precondition(condition); checks += 1 }
        func response() throws -> Data { try JSONSerialization.data(withJSONObject: ["schema_version":1,"operation_id":intent.operationID.uuidString,"employee_id":UUID().uuidString,"owner_id":scope.ownerID.uuidString,"company_id":scope.companyID.uuidString,"version":0,"is_archived":false]) }
        let rpc: NovaPersonnelService.RPC = { name,args in
            precondition(name == "isg_personnel_mutate_v1"); requests.append(args)
            precondition(!storage.values.isEmpty) // journal must precede network
            switch outcome {
            case "timeout": throw URLError(.timedOut)
            case "invalid": return Data("{}".utf8)
            case "oversize": return Data(repeating: 32, count: 16385)
            case "denied": throw NovaPersonnelFailure.denied
            case "late": current = NovaPersonnelScope(ownerID: scope.ownerID, sessionID: UUID(), companyID: scope.companyID, epoch: "replaced"); return try response()
            default: return try response()
            }
        }
        func service() -> NovaPersonnelService { .init(rpc: rpc, isCurrent: { $0 == current }, storage: storage) }
        let first = service().client
        do { _ = try await first.save(intent); fatalError("timeout must fail") } catch {}
        check(storage.values.count == 1 && requests.count == 1)
        current = NovaPersonnelScope(ownerID: scope.ownerID, sessionID: UUID(), companyID: scope.companyID, epoch: "restart")
        let restarted = service().client
        let recovered = try await restarted.pending(current)!
        check(recovered.operationID == intent.operationID && recovered.mutationID == intent.mutationID && recovered.scope == current)
        let changed = NovaEmployeeIntent(operationID: UUID(), mutationID: UUID(), scope: current, action: .create, employeeID: nil, expectedVersion: 0, name: "Başka", department: .none)
        do { _ = try await restarted.save(changed); fatalError("pending overwrite") } catch {}
        check(requests.count == 1)
        for mode in ["invalid","oversize"] {
            outcome = mode
            do { _ = try await restarted.save(recovered); fatalError("invalid response") } catch {}
            check(storage.values.count == 1)
        }
        outcome = "ok"
        _ = try await restarted.save(recovered)
        check(storage.values.isEmpty && requests.allSatisfy { $0 == requests[0] })
        check(try await restarted.pending(current) == nil)
        current = scope; outcome = "denied"
        do { _ = try await first.save(intent); fatalError("denied") } catch {}
        check(storage.values.isEmpty)
        outcome = "late"
        do { _ = try await first.save(intent); fatalError("late response") } catch {}
        check(storage.values.count == 1)
        current = NovaPersonnelScope(ownerID: UUID(), sessionID: UUID(), companyID: scope.companyID, epoch: "other")
        check(try await service().client.pending(current) == nil)
        let blockedStorage = MemoryPersonnelStorage(); blockedStorage.failWrite = true
        var called = false
        let blocked = NovaPersonnelService(rpc: { _,_ in called = true; return Data() }, isCurrent: { _ in true }, storage: blockedStorage)
        do { _ = try await blocked.client.save(intent); fatalError("storage failure") } catch {}
        check(!called)
        check(NovaPersonnelService.sessionID("invalid") == nil)
        let archived = NovaEmployeeRow(id: UUID(), ownerID: scope.ownerID, companyID: scope.companyID,
            name: "Ada Kaya", departmentID: nil, departmentName: nil, version: 3, isArchived: true)
        var editor = NovaEmployeeEditorState(); editor.name = archived.name
        check(editor.begin(scope: scope, original: archived) == nil)
        let restore = editor.begin(scope: scope, original: archived, restore: true)!
        check(restore.action == .restore && restore.department == .keep && restore.expectedVersion == 3)
        let restoreArgs = try NovaPersonnelService.arguments(restore)
        check(restoreArgs["p_name"] == .null && restoreArgs["p_department_name"] == .null && restoreArgs["p_department"] == .null)
        check(restoreArgs["p_change_department"] == .bool(false))
        check(editor.complete(restore, row: .init(operationID: restore.operationID, id: archived.id,
            ownerID: scope.ownerID, companyID: scope.companyID, version: 4, isArchived: false), scope: scope))
        print("Nova personnel service \(checks) checks PASS · injected transport/memory journal, no live SDK or Keychain access")
    }
}
