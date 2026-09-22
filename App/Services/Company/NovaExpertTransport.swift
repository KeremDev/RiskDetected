import Foundation
import Supabase

/// Composition boundary for the existing expert services. Each service captures
/// a ticket, so a response from a previous workspace cannot enter the new one.
/// A failed organization request must never fall back to personal RPCs.
@MainActor final class NovaExpertTransport {
    static let shared = NovaExpertTransport()

    struct Ticket: Equatable {
        let generation: UUID
        let access: NovaExpertAccess
    }

    private var ticket: Ticket?
    private weak var workspaceStore: IsgWorkspaceStore?
    private var currentWorkspace: () -> NovaWorkspaceSelection? = { nil }

    @discardableResult
    func bind(identity: NovaSessionIdentity, workspace: NovaWorkspaceSelection?,
              store: IsgWorkspaceStore? = nil,
              currentWorkspace: @escaping () -> NovaWorkspaceSelection?) -> Ticket {
        let value = Ticket(generation: UUID(), access: .init(identity: identity, workspace: workspace))
        self.currentWorkspace = currentWorkspace
        self.workspaceStore = store
        ticket = value
        return value
    }

    func release(_ expected: Ticket) {
        guard ticket == expected else { return }
        ticket = nil
        workspaceStore = nil
        currentWorkspace = { nil }
    }

    func capture() -> Ticket? { ticket }

    func organizationStore(ticket expected: Ticket?) throws -> IsgWorkspaceStore? {
        try validate(expected)
        guard expected?.access.workspaceID != nil else { return nil }
        guard let workspaceStore else { throw NovaPersonnelFailure.denied }
        return workspaceStore
    }

    func validate(_ expected: Ticket?) throws {
        try Task.checkCancellation()
        guard expected == ticket else { throw NovaPersonnelFailure.denied }
        if let expected {
            try expected.access.validate(identity: novaCurrentSessionIdentity(), workspace: currentWorkspace())
        }
    }

    func execute<P: Encodable>(_ name: String, params: P, ticket expected: Ticket?) async throws -> Data {
        try validate(expected)
        let result: Data
        if let workspace = expected?.access.workspaceID {
            let envelope = try await SupabaseService.shared.client.rpc("isg_expert_rpc_v1", params:
                WorkspaceRequest(p_workspace: workspace, p_function: name, p_arguments: params)).execute().data
            guard envelope.count <= 25_165_824,
                  let object = try JSONSerialization.jsonObject(with: envelope) as? [String: Any],
                  let value = object["_expert_workspace_id"] as? String, UUID(uuidString: value) == workspace,
                  let payload = object["payload"] else { throw NovaPersonnelFailure.denied }
            result = try JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])
        } else {
            result = try await SupabaseService.shared.client.rpc(name, params: params).execute().data
        }
        try validate(expected)
        return result
    }

    private struct WorkspaceRequest<P: Encodable>: Encodable {
        let p_workspace: UUID
        let p_function: String
        let p_arguments: P
    }
}
