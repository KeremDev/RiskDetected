import Foundation

/// Same shape as the personnel service: a plain RPC closure, a scope check and
/// no SDK type in the design system. The composition root injects the live one.
@MainActor struct NovaNonconformityService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isCurrent: (NovaPersonnelScope) -> Bool

    init(rpc: @escaping RPC, isCurrent: @escaping (NovaPersonnelScope) -> Bool) {
        self.rpc = rpc; self.isCurrent = isCurrent
    }

    private func check(_ scope: NovaPersonnelScope) throws {
        guard isCurrent(scope) else { throw NovaNonconformityFailure.denied }
    }

    private struct ListEnvelope: Decodable { let rows: [NovaNonconformityRow] }
    private struct WorkplaceEnvelope: Decodable { let rows: [NovaNonconformityWorkplace] }
    private struct MutationEnvelope: Decodable { let row: NovaNonconformityRow; let replayed: Bool }

    func list(_ scope: NovaPersonnelScope, state: NovaNonconformityState? = nil,
              query: String = "") async throws -> [NovaNonconformityRow] {
        try check(scope)
        let data = try await rpc("isg_nonconformity_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("list"),
            "p_query": .string(query), "p_state": state.map { .string($0.rawValue) } ?? .null,
            "p_after": .null, "p_id": .null])
        try check(scope)
        return try JSONDecoder().decode(ListEnvelope.self, from: data).rows
    }

    func workplaces(_ scope: NovaPersonnelScope) async throws -> [NovaNonconformityWorkplace] {
        try check(scope)
        let data = try await rpc("isg_nonconformity_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("workplaces"),
            "p_query": .null, "p_state": .null, "p_after": .null, "p_id": .null])
        try check(scope)
        return try JSONDecoder().decode(WorkplaceEnvelope.self, from: data).rows
    }

    /// The operation and mutation identifiers travel with the request, so a retry
    /// returns the first answer instead of opening a second record.
    func open(_ scope: NovaPersonnelScope, intent: NovaNonconformityIntent,
              operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaNonconformityRow {
        try check(scope)
        var payload: [String: PersonnelRPCValue] = [
            "workplace_id": .id(intent.workplaceID), "title": .string(intent.title)]
        if let severity = intent.severity { payload["severity"] = .string(severity.rawValue) }
        if let due = intent.dueOn { payload["due_on"] = .string(due) }
        switch intent.origin {
        case .manual:
            if let assignee = intent.assignee, !assignee.isEmpty { payload["assignee"] = .string(assignee) }
        case .finding:
            guard let finding = intent.findingID else { throw NovaNonconformityFailure.validation }
            payload["finding_id"] = .id(finding)
            // Without an explicit severity the server maps the legacy band, and
            // refuses rather than guessing when that band is unreadable.
            if intent.severity == nil {
                guard let band = intent.riskBand else { throw NovaNonconformityFailure.severityUnknown }
                payload["risk_band"] = .string(band)
            }
        }
        let data = try await rpc("isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID),
            "p_action": .string(intent.origin == .manual ? "open_manual" : "open_from_finding"),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
        try check(scope)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row
    }

    func transition(_ scope: NovaPersonnelScope, id: UUID, to state: NovaNonconformityState,
                    expectedVersion: Int64, reason: String,
                    operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaNonconformityRow {
        try check(scope)
        let data = try await rpc("isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string("transition"),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(["nonconformity_id": .id(id), "expected_version": .number(expectedVersion),
                                  "to_state": .string(state.rawValue), "reason": .string(reason)])])
        try check(scope)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row
    }
}
