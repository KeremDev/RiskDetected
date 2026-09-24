import Foundation

/// Same shape as the other module services: a plain RPC closure, a session
/// check and no SDK type in the design system.
@MainActor struct NovaKatipService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool
    private let storage: PersonnelPendingStorage
    private struct Pending: Codable {
        let company: UUID
        let action: String
        let payload: Data
        let operation: UUID
        let mutation: UUID
    }

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool,
         storage: PersonnelPendingStorage? = nil) {
        self.rpc = rpc; self.isSession = isSession; self.storage = storage ?? KeychainPersonnelPendingStorage(service: "com.riskdetected.katip.pending.v1")
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaKatipFailure.denied }
    }

    // MARK: transport rows

    private struct ContractRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        let workplace_name: String?
        let counterparty: String
        let expert_contact: String
        let scope: String
        let starts_on: String
        let ends_before: String?
        let term_state: String
        let state: String
        let notice_days: Int
        let declared_monthly_minutes: Int?
        let declared_note: String?
        let required_service_time_known: Bool
        let contract_stored: Bool
        let contract_location: String?
        let official_integration: Bool
        let official_submission_made: Bool
        let file_entry_id: UUID?
        let document_version: Int64?
        let document_title: String?
    }
    private struct WorkplaceRow: Decodable { let id: UUID; let name: String }
    private struct CatalogEnvelope: Decodable {
        let workplaces: [WorkplaceRow]
        let notice_days: Int
        let official_integration: Bool
        let official_status_checked: Bool
        let credential_collection: Bool
        let required_service_time_known: Bool
        let contract_storage_available: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [ContractRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
        let notice_days: Int
    }
    private struct DetailEnvelope: Decodable { let row: ContractRow }
    private struct MutationEnvelope: Decodable { let contract_id: UUID?; let row: ContractRow? }

    /// An unknown state word is reported as expired rather than smoothed into
    /// the calmest answer: the expert should look at the row.
    private func contract(_ entry: ContractRow) -> NovaKatipContract {
        let state = NovaKatipState(rawValue: entry.state) ?? .expired
        return NovaKatipContract(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            counterparty: entry.counterparty, expertContact: entry.expert_contact, scope: entry.scope,
            startsOn: entry.starts_on, endsBefore: entry.ends_before,
            term: NovaKatipTerm(rawValue: entry.term_state) ?? .fixedTerm,
            state: state, group: NovaKatipGroup.of(state), noticeDays: entry.notice_days,
            declaredMonthlyMinutes: entry.declared_monthly_minutes,
            declaredNote: entry.declared_note,
            requiredServiceTimeKnown: entry.required_service_time_known,
            contractStored: entry.contract_stored, contractLocation: entry.contract_location,
            officialIntegration: entry.official_integration,
            officialSubmissionMade: entry.official_submission_made,
            fileEntryID: entry.file_entry_id, documentVersion: entry.document_version ?? 0, documentTitle: entry.document_title)
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_katip_read_v1", payload)
    }

    // MARK: reads

    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaKatipCatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return .init(workplaces: envelope.workplaces.map { .init(id: $0.id, name: $0.name) },
                     noticeDays: envelope.notice_days,
                     officialIntegration: envelope.official_integration,
                     officialStatusChecked: envelope.official_status_checked,
                     credentialCollection: envelope.credential_collection,
                     requiredServiceTimeKnown: envelope.required_service_time_known,
                     contractStorageAvailable: envelope.contract_storage_available)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaKatipQuery) async throws -> NovaKatipBoard {
        try check(identity)
        let needle = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_kind": .string("list"),
            "p_query": needle.isEmpty ? .null : .string(needle),
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_workplace": query.workplace.map { .id($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(rows: envelope.rows.map(contract), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset,
                     noticeDays: envelope.notice_days)
    }

    func detail(_ identity: NovaSessionIdentity, contract id: UUID) async throws -> NovaKatipContract {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return contract(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    func hasPending(_ identity: NovaSessionIdentity) throws -> Bool {
        try check(identity)
        return try storage.read(account: identity.userID.uuidString.lowercased()) != nil
    }

    private struct SavedValue: Decodable {
        let value: PersonnelRPCValue
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { value = .null }
            else if let string = try? container.decode(String.self) { value = .string(string) }
            else { value = .number(try container.decode(Int64.self)) }
        }
    }

    func resume(_ identity: NovaSessionIdentity) async throws -> NovaKatipContract? {
        try check(identity)
        guard let data = try storage.read(account: identity.userID.uuidString.lowercased()) else { return nil }
        let pending = try JSONDecoder().decode(Pending.self, from: data)
        let payload = try JSONDecoder().decode([String: SavedValue].self, from: pending.payload).mapValues(\.value)
        return try await mutate(identity, company: pending.company, action: pending.action, payload: payload)
    }

    // MARK: writes

    private func mutate(_ identity: NovaSessionIdentity, company: UUID, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaKatipContract? {
        try check(identity)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(payload)
        let account = identity.userID.uuidString.lowercased()
        let pending: Pending
        if let saved = try storage.read(account: account) {
            pending = try JSONDecoder().decode(Pending.self, from: saved)
            guard pending.company == company, pending.action == action, pending.payload == encoded
            else { throw NovaKatipFailure.conflict }
        } else {
            pending = Pending(company: company, action: action, payload: encoded, operation: UUID(), mutation: UUID())
            try storage.write(encoder.encode(pending), account: account)
        }
        do {
            let data = try await rpc("isg_katip_mutate_v1", [
                "p_company": .id(company), "p_action": .string(action),
                "p_operation": .id(pending.operation), "p_mutation": .id(pending.mutation),
                "p_payload": .object(payload)])
            try check(identity)
            let row = try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(contract)
            try storage.remove(account: account)
            NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
            return row
        } catch {
            // Network, decoding and changed-session outcomes keep the original
            // request IDs. A retry must not create a second logical write.
            if let failure = error as? NovaKatipFailure,
               [.validation, .endsBeforeStart, .archived, .planRequired, .featureUnavailable, .moduleUnavailable].contains(failure) {
                try storage.remove(account: account)
            }
            throw error
        }
    }

    /// Nothing sent here reaches the official system, and nothing here takes a
    /// credential: the payload has no field for one and the server refuses any.
    func record(_ identity: NovaSessionIdentity, company: UUID,
                draft: NovaKatipDraft) async throws -> NovaKatipContract? {
        guard NovaDayField.date(draft.startsOn) != nil,
              !draft.counterparty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.expertContact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.scope.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw NovaKatipFailure.validation }
        let end = draft.endsBefore.trimmingCharacters(in: .whitespacesAndNewlines)
        let minutesText = draft.declaredMonthlyMinutes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard end.isEmpty || NovaDayField.date(end) != nil,
              minutesText.isEmpty || Int(minutesText).map({ (1...100000).contains($0) }) == true
        else { throw NovaKatipFailure.validation }
        if !end.isEmpty && end <= draft.startsOn { throw NovaKatipFailure.endsBeforeStart }
        var payload: [String: PersonnelRPCValue] = [
            "workplace_id": draft.workplaceID.map(PersonnelRPCValue.id) ?? .null,
            "counterparty": .string(draft.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)),
            "expert_contact": .string(draft.expertContact.trimmingCharacters(in: .whitespacesAndNewlines)),
            "scope": .string(draft.scope.trimmingCharacters(in: .whitespacesAndNewlines)),
            "starts_on": .string(draft.startsOn)]
        if !end.isEmpty { payload["ends_before"] = .string(end) }
        if let minutes = Int(minutesText) {
            payload["declared_monthly_minutes"] = .number(Int64(minutes))
        }
        let note = draft.declaredNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { payload["declared_note"] = .string(note) }
        let location = draft.contractLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { payload["contract_location"] = .string(location) }
        return try await mutate(identity, company: company, action: "record_contract", payload: payload)
    }

    func linkDocument(_ identity: NovaSessionIdentity, contract: NovaKatipContract, file: UUID?) async throws -> NovaKatipContract? {
        guard let company = contract.companyID else { throw NovaKatipFailure.denied }
        return try await mutate(identity, company: company, action: "link_document", payload: [
            "contract_id": .id(contract.id), "file_entry_id": file.map { .id($0) } ?? .null,
            "expected_version": .number(contract.documentVersion)])
    }

    func end(_ identity: NovaSessionIdentity, company: UUID,
             draft: NovaKatipEndDraft) async throws -> NovaKatipContract? {
        guard let contract = draft.contractID,
              NovaDayField.date(draft.endsBefore) != nil else { throw NovaKatipFailure.validation }
        return try await mutate(identity, company: company, action: "end_contract", payload: [
            "contract_id": .id(contract), "ends_before": .string(draft.endsBefore)])
    }

    /// Archiving closes this application's own record. Nothing is filed
    /// anywhere else, and the answer says so.
    func archive(_ identity: NovaSessionIdentity, company: UUID,
                 contract id: UUID) async throws -> NovaKatipContract? {
        try await mutate(identity, company: company, action: "archive_contract",
                         payload: ["contract_id": .id(id)])
    }
}
