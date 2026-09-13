import SwiftUI
import Security
#if !targetEnvironment(simulator)
#error("This isolated journal harness may only run in a simulator")
#endif

@main struct JournalHarness: App {
    @State private var result = "RUNNING"
    var body: some Scene { WindowGroup { Text(result).accessibilityIdentifier("journal.result").task {
        do { result = try await checkJournal() } catch { result = "FAIL storage-or-core" }
    } } }
    @MainActor private func checkJournal() async throws -> String {
        let service = "com.riskdetected.qa.journal-proof.v1"
        let storage = KeychainPersonnelPendingStorage(service: service)
        let owner = UUID(uuidString:"11111111-1111-4111-8111-111111111111")!, company = UUID(uuidString:"22222222-2222-4222-8222-222222222222")!
        let key = "\(owner.uuidString.lowercased()):\(company.uuidString.lowercased())"
        let scope = NovaPersonnelScope(ownerID: owner, sessionID: UUID(), companyID: company, epoch: UUID().uuidString)
        let write = ProcessInfo.processInfo.arguments.contains("--write")
        if write {
            let probe: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service+".probe",kSecAttrAccount as String:"probe",kSecValueData as String:Data([1]),kSecAttrAccessible as String:kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let status = SecItemAdd(probe as CFDictionary,nil)
            if status != errSecSuccess && status != errSecDuplicateItem { return "FAIL keychain-status \(status)" }
            SecItemDelete([kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service+".probe",kSecAttrAccount as String:"probe"] as CFDictionary)
            try storage.remove(account: key)
            let intent = NovaEmployeeIntent(operationID: UUID(), mutationID: UUID(), scope: scope, action: .create, employeeID: nil, expectedVersion: 0, name: "Sentetik Ada", department: .none)
            let core = NovaPersonnelService(rpc: { _, _ in throw NovaPersonnelFailure.unavailable }, isCurrent: { $0 == scope }, storage: storage)
            do { _ = try await core.client.save(intent); return "FAIL unexpected success" } catch {}
            guard let data = try storage.read(account: key), !data.isEmpty else { return "FAIL missing pending" }
            let q: [String:Any] = [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:key,kSecReturnAttributes as String:true]
            var attrs: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary,&attrs) == errSecSuccess,
                  let a = attrs as? [String:Any], a[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
                  (a[kSecAttrSynchronizable as String] as? Bool) != true else { return "FAIL attributes" }
            do { try storage.write(Data(repeating:0,count:16385),account:key); return "FAIL bound" } catch {}
            guard try storage.read(account:key) == data, try storage.read(account: "other:" + key) == nil else { return "FAIL isolation" }
            return "PASS durable-write attributes size-bound isolation"
        }
        let core = NovaPersonnelService(rpc: { name, args in
            guard name == "isg_personnel_mutate_v1" else { throw NovaPersonnelFailure.unavailable }
            var output: [String:Any] = ["schema_version":1,"employee_id":UUID().uuidString,"owner_id":owner.uuidString,"company_id":company.uuidString,"version":0,"is_archived":false]
            if case .string(let operation) = args["p_operation"] { output["operation_id"] = operation }
            return try JSONSerialization.data(withJSONObject:output)
        }, isCurrent: { $0 == scope }, storage:storage)
        guard let pending = try await core.client.pending(scope), pending.scope == scope, pending.name == "Sentetik Ada" else { return "FAIL restart" }
        _ = try await core.client.save(pending)
        guard try storage.read(account:key) == nil else { return "FAIL cleanup" }
        return "PASS restart-rebind same-intent commit-clear"
    }
}
