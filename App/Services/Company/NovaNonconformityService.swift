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
    private struct DetailEnvelope: Decodable { let row: NovaNonconformityRow }
    private struct Outcome: Decodable { let replayed: Bool? }
    private struct MutationEnvelope: Decodable {
        let row: NovaNonconformityRow
        let replayed: Bool
        let outcome: Outcome?
    }
    /// `alreadyOpen` is the server saying this finding already had a record, which
    /// is a different sentence from "your retry replayed".
    struct OpenResult: Equatable { let row: NovaNonconformityRow; let alreadyOpen: Bool }

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
              operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> OpenResult {
        try check(scope)
        var payload: [String: PersonnelRPCValue] = [
            "workplace_id": .id(intent.workplaceID), "title": .string(intent.title)]
        if let severity = intent.severity { payload["severity"] = .string(severity.rawValue) }
        if let due = intent.dueOn { payload["due_on"] = .string(due) }
        let assignee = intent.assignee?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch intent.origin {
        case .manual:
            if !assignee.isEmpty { payload["assignee"] = .string(assignee) }
        case .finding:
            guard let finding = intent.findingID else { throw NovaNonconformityFailure.validation }
            payload["finding_id"] = .id(finding)
            payload["risk_method"] = .string((intent.sourceMethod ?? .fineKinney).rawValue)
            // Without an explicit severity the server maps the legacy band, and
            // refuses rather than guessing when that band is unreadable.
            if intent.severity == nil {
                guard let band = intent.riskBand else { throw NovaNonconformityFailure.severityUnknown }
                payload["risk_band"] = .string(band)
            }
        case .expertItem:
            // An expert-opinion item is unscored, so a severity has to have been
            // chosen by a person. There is no band to fall back on.
            guard let item = intent.expertItemID else { throw NovaNonconformityFailure.validation }
            guard intent.severity != nil else { throw NovaNonconformityFailure.severityUnknown }
            payload["item_id"] = .id(item)
            payload["record_kind"] = .string(intent.recordKind.rawValue)
            if !assignee.isEmpty { payload["assignee"] = .string(assignee) }
            if let text = Self.text(intent.hazardDescription) { payload["description"] = .string(text) }
        case .detailed:
            guard intent.severity != nil else { throw NovaNonconformityFailure.severityUnknown }
            payload["record_kind"] = .string(intent.recordKind.rawValue)
            if !assignee.isEmpty { payload["assignee"] = .string(assignee) }
            Self.merge(detail: intent, into: &payload)
            if !intent.evidenceAssetIDs.isEmpty {
                payload["evidence_asset_ids"] = .array(intent.evidenceAssetIDs.map { .id($0) })
            }
        }
        let data = try await rpc(intent.origin == .finding ? "isg_pilot_finding_file_v1" : "isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string(intent.action),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
        try check(scope)
        let envelope = try JSONDecoder().decode(MutationEnvelope.self, from: data)
        NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: scope.ownerID)
        return .init(row: envelope.row, alreadyOpen: envelope.outcome?.replayed ?? false)
    }

    /// Replaces the whole detail, exactly as the screen is showing it, so a
    /// field the expert cleared really is cleared on the record.
    func setDetail(_ scope: NovaPersonnelScope, id: UUID, description: String?, measure: String?,
                   legislation: String?, responsible: String?, score: NovaRiskScoreInput,
                   operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaNonconformityRow {
        try check(scope)
        guard score.isEmpty || score.isComplete else { throw NovaNonconformityFailure.validation }
        var payload: [String: PersonnelRPCValue] = ["nonconformity_id": .id(id)]
        var carrier = NovaNonconformityIntent(origin: .detailed, workplaceID: id, title: "")
        carrier.hazardDescription = description; carrier.controlMeasure = measure
        carrier.legislation = legislation; carrier.responsible = responsible; carrier.score = score
        Self.merge(detail: carrier, into: &payload)
        let data = try await rpc("isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string("set_detail"),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
        try check(scope)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row
    }

    func detail(_ scope: NovaPersonnelScope, id: UUID) async throws -> NovaNonconformityRow {
        try check(scope)
        let data = try await rpc("isg_nonconformity_read_v1", [
            "p_company": .id(scope.companyID), "p_kind": .string("detail"),
            "p_query": .null, "p_state": .null, "p_after": .null, "p_id": .id(id)])
        try check(scope)
        return try JSONDecoder().decode(DetailEnvelope.self, from: data).row
    }

    func addAction(_ scope: NovaPersonnelScope, id: UUID, description: String, assignee: String?, dueOn: String?,
                   operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaNonconformityRow {
        try check(scope)
        var payload: [String: PersonnelRPCValue] = ["nonconformity_id": .id(id), "description": .string(description)]
        if let value = Self.text(assignee) { payload["assignee"] = .string(value) }
        if let dueOn { payload["due_on"] = .string(dueOn) }
        let data = try await rpc("isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string("add_action"),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID), "p_payload": .object(payload)])
        try check(scope)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row
    }

    func verify(_ scope: NovaPersonnelScope, id: UUID, accepted: Bool, note: String?,
                operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaNonconformityRow {
        try check(scope)
        var payload: [String: PersonnelRPCValue] = ["nonconformity_id": .id(id),
            "outcome": .string(accepted ? "accepted" : "rejected")]
        if let value = Self.text(note) { payload["note"] = .string(value) }
        let data = try await rpc("isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string("verify"),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID), "p_payload": .object(payload)])
        try check(scope)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row
    }

    /// The published Fine-Kinney values are sent as text so no floating-point
    /// rendering can turn 0.2 into something the server's scale check refuses.
    private static func scaleText(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private static func text(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The score itself is never sent: the server generates it from these
    /// inputs, and the payload allowlist has no key for a score or a band.
    private static func merge(detail intent: NovaNonconformityIntent, into payload: inout [String: PersonnelRPCValue]) {
        if let value = text(intent.hazardDescription) { payload["description"] = .string(value) }
        if let value = text(intent.controlMeasure) { payload["control_measure"] = .string(value) }
        if let value = text(intent.legislation) { payload["legislation_ref"] = .string(value) }
        if let value = text(intent.responsible) { payload["responsible_contact"] = .string(value) }
        guard let method = intent.score.method, intent.score.isComplete else { return }
        payload["risk_method"] = .string(method.rawValue)
        switch method {
        case .fineKinney:
            payload["fk_probability"] = .string(scaleText(intent.score.probability ?? 0))
            payload["fk_frequency"] = .string(scaleText(intent.score.frequency ?? 0))
            payload["fk_severity"] = .string(scaleText(intent.score.severity ?? 0))
        case .matrix5x5:
            payload["m5_probability"] = .number(Int64(intent.score.matrixProbability ?? 0))
            payload["m5_severity"] = .number(Int64(intent.score.matrixSeverity ?? 0))
        }
    }

    /// The expected version travels with the move, so a record someone else
    /// advanced in the meantime refuses instead of jumping two states.
    func transition(_ scope: NovaPersonnelScope, id: UUID, to state: NovaNonconformityState,
                    expectedVersion: Int64, reason: String, assignee: String = "",
                    operationID: UUID = UUID(), mutationID: UUID = UUID()) async throws -> NovaNonconformityRow {
        try check(scope)
        var payload: [String: PersonnelRPCValue] = ["nonconformity_id": .id(id),
            "expected_version": .number(expectedVersion), "to_state": .string(state.rawValue)]
        if let value = Self.text(reason) { payload["reason"] = .string(value) }
        if let value = Self.text(assignee) { payload["assignee"] = .string(value) }
        let data = try await rpc("isg_nonconformity_mutate_v1", [
            "p_company": .id(scope.companyID), "p_action": .string("transition"),
            "p_operation": .id(operationID), "p_mutation": .id(mutationID),
            "p_payload": .object(payload)])
        try check(scope)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row
    }
}

