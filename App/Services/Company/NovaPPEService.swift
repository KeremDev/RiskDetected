import Foundation

/// Same shape as the other module services: a plain RPC closure, a session
/// check and no SDK type in the design system.
@MainActor struct NovaPPEService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaPPEFailure.denied }
    }

    // MARK: transport rows

    private struct ReturnRow: Decodable {
        let id: UUID
        let quantity: Double
        let returned_on: String
        let condition: String
        let note: String?
    }
    private struct HandoverRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let employee_id: UUID?
        let employee_name: String?
        let employee_archived: Bool
        let item: String
        let quantity: Double
        let unit: String
        let handed_on: String
        let external_ref: String?
        let state: String
        let returned_quantity: Double
        let outstanding: Double
        let lost_quantity: Double
        let signed_copy_stored: Bool
        let signed_copy_location: String?
        let returns: [ReturnRow]?
    }
    private struct EmployeeRow: Decodable { let id: UUID; let full_name: String }
    private struct CatalogEnvelope: Decodable {
        let employees: [EmployeeRow]
        let units: [String]
        let conditions: [String]
        let item_catalogue_offered: Bool
        let signed_copy_storage_available: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [HandoverRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
    }
    private struct DetailEnvelope: Decodable { let row: HandoverRow }
    private struct MutationEnvelope: Decodable { let handover_id: UUID?; let row: HandoverRow? }

    /// An unknown state word is reported as outstanding rather than smoothed
    /// into the calmest answer: the expert should look at the row.
    private func handover(_ entry: HandoverRow) -> NovaPPEHandover {
        NovaPPEHandover(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            employeeID: entry.employee_id, employeeName: entry.employee_name,
            employeeArchived: entry.employee_archived,
            item: entry.item, quantity: entry.quantity,
            unit: NovaPPEUnit(rawValue: entry.unit) ?? .piece,
            handedOn: entry.handed_on, externalRef: entry.external_ref,
            state: NovaPPEState(rawValue: entry.state) ?? .outstanding,
            returnedQuantity: entry.returned_quantity, outstanding: entry.outstanding,
            lostQuantity: entry.lost_quantity,
            signedCopyStored: entry.signed_copy_stored,
            signedCopyLocation: entry.signed_copy_location,
            returns: (entry.returns ?? []).map {
                NovaPPEReturn(id: $0.id, quantity: $0.quantity, returnedOn: $0.returned_on,
                              condition: NovaPPECondition(rawValue: $0.condition) ?? .reusable,
                              note: $0.note)
            })
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_employee": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_ppe_read_v1", payload)
    }

    // MARK: reads

    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaPPECatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return .init(employees: envelope.employees.map { .init(id: $0.id, fullName: $0.full_name) },
                     units: envelope.units.compactMap(NovaPPEUnit.init(rawValue:)),
                     conditions: envelope.conditions.compactMap(NovaPPECondition.init(rawValue:)),
                     itemCatalogueOffered: envelope.item_catalogue_offered,
                     signedCopyStorageAvailable: envelope.signed_copy_storage_available)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaPPEQuery) async throws -> NovaPPEBoard {
        try check(identity)
        let needle = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_kind": .string("list"),
            "p_query": needle.isEmpty ? .null : .string(needle),
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_employee": query.employee.map { .id($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(rows: envelope.rows.map(handover), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset)
    }

    func detail(_ identity: NovaSessionIdentity, handover id: UUID) async throws -> NovaPPEHandover {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return handover(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    private func mutate(_ identity: NovaSessionIdentity, company: UUID, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaPPEHandover? {
        try check(identity)
        let data = try await rpc("isg_ppe_mutate_v1", [
            "p_company": .id(company), "p_action": .string(action),
            "p_operation": .id(UUID()), "p_mutation": .id(UUID()),
            "p_payload": .object(payload)])
        try check(identity)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(handover)
    }

    /// The signed copy flag is never sent: the product holds no file, so it
    /// could only ever be refused. What is sent is where the form is kept.
    func recordHandover(_ identity: NovaSessionIdentity, company: UUID,
                        draft: NovaPPEHandoverDraft) async throws -> NovaPPEHandover? {
        guard let employee = draft.employeeID,
              let quantity = Double(draft.quantity.replacingOccurrences(of: ",", with: ".")),
              quantity > 0, NovaDayField.date(draft.handedOn) != nil,
              !draft.item.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw NovaPPEFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "employee_id": .id(employee),
            "item": .string(draft.item.trimmingCharacters(in: .whitespacesAndNewlines)),
            "quantity": .string(String(quantity)),
            "unit": .string(draft.unit.rawValue),
            "handed_on": .string(draft.handedOn)]
        let reference = draft.externalRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reference.isEmpty { payload["external_ref"] = .string(reference) }
        let location = draft.signedCopyLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { payload["signed_copy_location"] = .string(location) }
        return try await mutate(identity, company: company, action: "record_handover", payload: payload)
    }

    func recordReturn(_ identity: NovaSessionIdentity, company: UUID,
                      draft: NovaPPEReturnDraft) async throws -> NovaPPEHandover? {
        guard let handover = draft.handoverID,
              let quantity = Double(draft.quantity.replacingOccurrences(of: ",", with: ".")),
              quantity > 0, NovaDayField.date(draft.returnedOn) != nil
        else { throw NovaPPEFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "handover_id": .id(handover), "quantity": .string(String(quantity)),
            "returned_on": .string(draft.returnedOn),
            "condition": .string(draft.condition.rawValue)]
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { payload["note"] = .string(note) }
        return try await mutate(identity, company: company, action: "record_return", payload: payload)
    }

    /// Taking back a return entered by mistake. What is still out is recounted
    /// at the next read, because it was never stored.
    func removeReturn(_ identity: NovaSessionIdentity, company: UUID, handover: UUID,
                      entry: UUID) async throws -> NovaPPEHandover? {
        try await mutate(identity, company: company, action: "remove_return",
                         payload: ["handover_id": .id(handover), "return_id": .id(entry)])
    }
}
