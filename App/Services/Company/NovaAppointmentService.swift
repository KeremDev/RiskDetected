import Foundation

/// Same shape as the other module services: a plain RPC closure, a session
/// check and no SDK type in the design system.
@MainActor struct NovaAppointmentService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaAppointmentFailure.denied }
    }

    // MARK: transport rows

    private struct AppointmentRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let employee_id: UUID?
        let employee_name: String?
        let employee_archived: Bool
        let workplace_id: UUID?
        let workplace_name: String?
        let kind: String
        let usual_basis: String?
        let starts_on: String
        let ends_before: String?
        let state: String
        let basis: String?
        let basis_note: String?
        let asset_id: UUID?
        let asset_download: AssetDownloadRow?
        let qualification_verified: Bool
    }
    private struct AssetDownloadRow: Decodable { let bucket: String; let path: String }
    private struct KindRow: Decodable { let code: String; let ordinal: Int; let usual_basis: String }
    private struct WorkplaceRow: Decodable { let id: UUID; let name: String }
    private struct EmployeeRow: Decodable { let id: UUID; let full_name: String }
    private struct CatalogEnvelope: Decodable {
        let kinds: [KindRow]
        let bases: [String]
        let workplaces: [WorkplaceRow]
        let employees: [EmployeeRow]
        let required_count_known: Bool
        let qualification_check_available: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [AppointmentRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
    }
    private struct DetailEnvelope: Decodable { let row: AppointmentRow }
    private struct MutationEnvelope: Decodable { let appointment_id: UUID?; let row: AppointmentRow? }

    /// An unknown state word is reported as active rather than smoothed into
    /// the calmest answer: the expert should look at the row.
    private func appointment(_ entry: AppointmentRow) -> NovaAppointment {
        NovaAppointment(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            employeeID: entry.employee_id, employeeName: entry.employee_name,
            employeeArchived: entry.employee_archived,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            kind: NovaAppointmentKind(rawValue: entry.kind) ?? .representative,
            usualBasis: entry.usual_basis.flatMap(NovaAppointmentBasis.init(rawValue:)),
            startsOn: entry.starts_on, endsBefore: entry.ends_before,
            state: NovaAppointmentState(rawValue: entry.state) ?? .active,
            basis: entry.basis.flatMap(NovaAppointmentBasis.init(rawValue:)),
            basisNote: entry.basis_note,
            assetID: entry.asset_id,
            assetDownload: entry.asset_download.map { .init(bucket: $0.bucket, path: $0.path) },
            qualificationVerified: entry.qualification_verified)
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_role": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_appointments_read_v1", payload)
    }

    // MARK: reads

    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaAppointmentCatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        let roles: [NovaAppointmentCatalogue.Role] = envelope.kinds
            .sorted { $0.ordinal < $1.ordinal }
            .compactMap { row in
                guard let kind = NovaAppointmentKind(rawValue: row.code),
                      let basis = NovaAppointmentBasis(rawValue: row.usual_basis) else { return nil }
                return .init(kind: kind, usualBasis: basis)
            }
        return .init(roles: roles,
                     bases: envelope.bases.compactMap(NovaAppointmentBasis.init(rawValue:)),
                     workplaces: envelope.workplaces.map { .init(id: $0.id, name: $0.name) },
                     employees: envelope.employees.map { .init(id: $0.id, fullName: $0.full_name) },
                     requiredCountKnown: envelope.required_count_known,
                     qualificationCheckAvailable: envelope.qualification_check_available)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaAppointmentQuery) async throws -> NovaAppointmentBoard {
        try check(identity)
        let needle = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_kind": .string("list"),
            "p_query": needle.isEmpty ? .null : .string(needle),
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_workplace": query.workplace.map { .id($0) } ?? .null,
            "p_role": query.role.map { .string($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(rows: envelope.rows.map(appointment), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset)
    }

    func detail(_ identity: NovaSessionIdentity, appointment id: UUID) async throws -> NovaAppointment {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return appointment(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    private func mutate(_ identity: NovaSessionIdentity, company: UUID, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaAppointment? {
        try check(identity)
        return try await NovaModuleMutationJournal.run(function: "isg_appointments_mutate_v1", identity: identity,
            company: company, action: action, payload: payload, rpc: rpc,
            validate: { try check(identity) }, decode: { data in
                return try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(appointment)
            })
    }

    /// Saying why the person holds the role is required; there is no field of
    /// any kind for claiming they are qualified for it.
    func record(_ identity: NovaSessionIdentity, company: UUID,
                draft: NovaAppointmentDraft) async throws -> NovaAppointment? {
        guard let employee = draft.employeeID, let workplace = draft.workplaceID,
              NovaDayField.date(draft.startsOn) != nil else { throw NovaAppointmentFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "employee_id": .id(employee), "workplace_id": .id(workplace),
            "kind": .string(draft.kind.rawValue), "basis": .string(draft.basis.rawValue),
            "starts_on": .string(draft.startsOn)]
        if NovaDayField.date(draft.endsBefore) != nil { payload["ends_before"] = .string(draft.endsBefore) }
        let note = draft.basisNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { payload["basis_note"] = .string(note) }
        let location = draft.letterLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty { payload["letter_location"] = .string(location) }
        return try await mutate(identity, company: company, action: "record_appointment", payload: payload)
    }

    /// Ending it, or correcting the date it ended. The exclusion constraint,
    /// not this side, is what keeps a corrected date off the person's next
    /// appointment in the same role.
    func end(_ identity: NovaSessionIdentity, company: UUID,
             draft: NovaAppointmentEndDraft) async throws -> NovaAppointment? {
        guard let appointment = draft.appointmentID,
              NovaDayField.date(draft.endsBefore) != nil else { throw NovaAppointmentFailure.validation }
        return try await mutate(identity, company: company, action: "end_appointment", payload: [
            "appointment_id": .id(appointment), "ends_before": .string(draft.endsBefore)])
    }
}
