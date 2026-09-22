import Foundation

// Only app composition/localization are replaced. The real API and store run.
enum RDLocalizationTable { case localizable }
enum RDLocalization {
    static func string(_ key: String, table: RDLocalizationTable, fallback: String) -> String { fallback }
}
enum NovaSuccessMessage { static func serverKey(_ key: String) -> String { key } }
extension IsgWorkspaceContext {
    var selection: NovaWorkspaceSelection {
        .init(workspaceID: workspaceID, membershipID: membership.membershipID,
              userID: membership.userID, kind: kind, permissionRevision: membership.permissionRevision,
              workspaceVersion: workspaceVersion, canRead: canRead, canOperate: canOperate)
    }
}
extension IsgWorkspaceAPI {
    static func live(currentIdentity: @escaping () -> NovaSessionIdentity?,
                     currentSelection: @escaping () -> NovaWorkspaceSelection?,
                     currentEpoch: @escaping () -> UUID?) -> IsgWorkspaceAPI { fatalError("Live transport forbidden") }
}

@main @MainActor enum WorkspaceStoreCheck {
    static func main() async throws {
        let user = UUID(), workspace = UUID(), membership = UUID()
        let companyA = UUID(), companyB = UUID(), assignment = UUID()
        let context: [String: Any] = ["schema_version": 1, "workspace_id": workspace.uuidString,
            "kind": "osgb", "name": "Synthetic", "status": "active", "timezone": "Europe/Istanbul",
            "workspace_version": 1, "membership": ["membership_id": membership.uuidString,
                "user_id": user.uuidString, "role": "owner", "status": "active", "is_practicing_expert": false,
                "permission_revision": 1, "membership_version": 1],
            "can_read": true, "can_operate": true, "can_manage_members": true, "can_manage_billing": true]
        var pause = false, failSummary = false
        var pending: CheckedContinuation<Void, Never>?
        let store = IsgWorkspaceStore(rpc: { endpoint, args in
            let body: [String: Any]
            switch endpoint {
            case "isg_workspace_list_v1":
                body = ["schema_version": 1, "user_id": user.uuidString, "workspaces": [context]]
            case "isg_workspace_context_v1": body = context
            case "isg_workspace_company_list_v1":
                body = ["schema_version": 1, "workspace_id": workspace.uuidString,
                    "rows": [companyA, companyB].sorted { $0.uuidString < $1.uuidString }.map {
                        ["company_id": $0.uuidString, "name": "Synthetic", "hazard_class": "high", "status": "active", "version": 0] as [String: Any]
                    }, "next": NSNull()]
            case "isg_workspace_assignment_mutate_v1":
                guard case .string(let company) = args["p_company"] else { fatalError() }
                body = ["schema_version": 1, "workspace_id": workspace.uuidString, "company_id": company,
                    "assignment_id": assignment.uuidString, "membership_id": membership.uuidString,
                    "user_id": user.uuidString, "assignment_role": "support", "membership_role": "expert",
                    "membership_status": "active", "starts_at": "2026-09-17T08:00:00Z", "ends_at": NSNull(), "version": 0]
            case "isg_workspace_dashboard_v1":
                let company: Any
                if case .string(let value) = args["p_company"] { company = value } else { company = NSNull() }
                body = ["schema_version": 1, "workspace_id": workspace.uuidString, "company_id": company,
                    "measured": true, "companies": ["total": 2, "unassigned": 0], "experts": ["active": 1],
                    "nonconformities": ["open": 1, "overdue": 0], "visits": ["total": 0, "last_30_days": 0],
                    "training": ["planned": 0, "completed": 0], "deadlines": ["equipment_due_soon": 0, "risk_due_soon": 0]]
                if pause {
                    pause = false
                    await withCheckedContinuation { pending = $0 }
                }
                if failSummary { throw IsgWorkspaceAPIFailure.invalidResponse }
            default: fatalError("Unexpected endpoint: \(endpoint)")
            }
            return try JSONSerialization.data(withJSONObject: body)
        })
        func waitUntil(_ condition: () -> Bool) async {
            for _ in 0..<1000 { if condition() { return }; await Task.yield() }
            preconditionFailure("Store did not settle")
        }
        func mutate(_ company: UUID) async throws {
            _ = try await store.mutateAssignment(mutationID: UUID(), companyID: company,
                action: "create", membershipID: membership, role: "support",
                startsAt: "2026-09-17T08:00:00Z", reason: "Synthetic")
        }
        store.adopt(.init(userID: user, sessionID: UUID()))
        await waitUntil { store.phase == .ready }
        let routingContext = store.selection
        store.refresh()
        precondition(store.phase == .loading && store.selection == routingContext,
                     "Refresh briefly changed OSGB routing to personal")
        precondition(store.companies.isEmpty && store.dashboard == nil,
                     "Refresh retained stale workspace data")
        await waitUntil { store.phase == .ready }
        precondition(store.selection == routingContext && store.companies.count == 2,
                     "Refresh failed to recover the same workspace")
        store.selectCompany(companyA)
        await waitUntil { store.phase == .ready }
        try await mutate(companyB)
        precondition(store.dashboard?.companyID == companyA, "Explicit mutation changed dashboard scope")

        pause = true
        let mutation = Task { try await mutate(companyA) }
        await waitUntil { pending != nil }
        store.selectCompany(companyB)
        await waitUntil { store.phase == .ready }
        pending?.resume(); pending = nil
        do { try await mutation.value; fatalError("Old mutation reported success in new scope") }
        catch IsgWorkspaceAPIFailure.staleSession {}
        precondition(store.dashboard?.companyID == companyB, "Late old response cleared new dashboard")

        failSummary = true
        try await mutate(companyB)
        precondition(store.phase == .ready && store.dashboard == nil,
                     "Summary failure changed committed mutation into failure")
        print("PASS Swift workspace store: selected scope, late summary isolation, committed success")
    }
}
