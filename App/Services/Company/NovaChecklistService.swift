import Foundation

/// Same shape as the other module services: a plain RPC closure, a session
/// check and no SDK type in the design system.
@MainActor struct NovaChecklistService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaChecklistFailure.denied }
    }

    // MARK: transport rows

    private struct AnswerRow: Decodable {
        let item_code: String
        let prompt: String
        let position: Int
        let allows_not_applicable: Bool
        let result: String?
        let note: String?
        let nonconformity_id: UUID?
    }
    private struct RunRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        var workplace_name: String?
        let template_code: String
        let template_title: String?
        let template_version: Int
        let state: String
        let started_on: String
        let submitted_at: Date?
        let expected: Int
        let answered: Int
        let remaining: Int
        let conform: Int
        let nonconform: Int
        let not_applicable: Int
        let nonconformities_opened: Int
        let items: [AnswerRow]?
    }
    private struct WorkplaceRow: Decodable { let id: UUID; let name: String; let needs_review: Bool }
    private struct StarterRow: Decodable {
        let template_code: String
        let title: String
        let version: Int
        let items: Int
        let is_product: Bool
    }
    private struct CatalogEnvelope: Decodable {
        let workplaces: [WorkplaceRow]
        let templates: [StarterRow]
        let product_templates_offered: Bool
    }
    private struct TemplateItemRow: Decodable {
        let item_code: String
        let prompt: String
        let position: Int
        let allows_not_applicable: Bool
    }
    private struct TemplateVersionRow: Decodable {
        let version: Int
        let status: String
        let published_at: Date?
        let approval_note: String?
        let items: [TemplateItemRow]?
    }
    private struct TemplateRow: Decodable {
        let template_code: String
        let title: String
        let is_product: Bool
        let is_archived: Bool
        let versions: [TemplateVersionRow]?
    }
    private struct TemplatesEnvelope: Decodable { let rows: [TemplateRow] }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [RunRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
    }
    private struct DetailEnvelope: Decodable { let row: RunRow }
    private struct MutationEnvelope: Decodable { let run_id: UUID?; let row: RunRow? }

    /// An unknown state word is reported as open rather than smoothed into the
    /// calmest answer: the expert should look at the run.
    private func run(_ entry: RunRow) -> NovaChecklistRun {
        let answers: [NovaChecklistAnswer] = (entry.items ?? []).map {
            NovaChecklistAnswer(itemCode: $0.item_code, prompt: $0.prompt, position: $0.position,
                                allowsNotApplicable: $0.allows_not_applicable,
                                result: $0.result.flatMap(NovaChecklistResult.init(rawValue:)),
                                note: $0.note, nonconformityID: $0.nonconformity_id)
        }
        return NovaChecklistRun(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            templateCode: entry.template_code, templateTitle: entry.template_title,
            templateVersion: entry.template_version,
            state: NovaChecklistRunState(rawValue: entry.state) ?? .open,
            startedOn: entry.started_on, submittedAt: entry.submitted_at,
            expected: entry.expected, answered: entry.answered, remaining: entry.remaining,
            conform: entry.conform, nonconform: entry.nonconform, notApplicable: entry.not_applicable,
            nonconformitiesOpened: entry.nonconformities_opened, answers: answers)
    }

    private func template(_ entry: TemplateRow) -> NovaChecklistTemplate {
        let versions: [NovaChecklistTemplateVersion] = (entry.versions ?? []).map { version in
            NovaChecklistTemplateVersion(
                version: version.version, status: version.status, publishedAt: version.published_at,
                approvalNote: version.approval_note,
                items: (version.items ?? []).map {
                    NovaChecklistTemplateItem(itemCode: $0.item_code, prompt: $0.prompt,
                                              position: $0.position,
                                              allowsNotApplicable: $0.allows_not_applicable)
                })
        }
        return NovaChecklistTemplate(templateCode: entry.template_code, title: entry.title,
                                     isProduct: entry.is_product, isArchived: entry.is_archived,
                                     versions: versions)
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_template": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_checklists_read_v1", payload)
    }

    // MARK: reads

    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaChecklistCatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return .init(workplaces: envelope.workplaces.map { .init(id: $0.id, name: $0.name, needsReview: $0.needs_review) },
                     starters: envelope.templates.map { .init(templateCode: $0.template_code, title: $0.title,
                                                              version: $0.version, items: $0.items,
                                                              isProduct: $0.is_product) },
                     productTemplatesOffered: envelope.product_templates_offered)
    }

    /// The lists this expert wrote, with every version and its questions.
    func templates(_ identity: NovaSessionIdentity, company: UUID?) async throws -> [NovaChecklistTemplate] {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("templates")])
        try check(identity)
        return try JSONDecoder().decode(TemplatesEnvelope.self, from: data).rows.map(template)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaChecklistQuery) async throws -> NovaChecklistBoard {
        try check(identity)
        let needle = query.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_company": query.company.map { .id($0) } ?? .null,
            "p_kind": .string("list"),
            "p_query": needle.isEmpty ? .null : .string(needle),
            "p_state": query.state.map { .string($0) } ?? .null,
            "p_workplace": query.workplace.map { .id($0) } ?? .null,
            "p_template": query.template.map { .string($0) } ?? .null,
            "p_limit": .number(Int64(query.limit)), "p_offset": .number(Int64(query.offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: data)
        return .init(rows: envelope.rows.map(run), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset)
    }

    func detail(_ identity: NovaSessionIdentity, run id: UUID) async throws -> NovaChecklistRun {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(id)])
        try check(identity)
        return run(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    @discardableResult
    private func mutate(_ identity: NovaSessionIdentity, company: UUID, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaChecklistRun? {
        try check(identity)
        let data = try await rpc("isg_checklists_mutate_v1", [
            "p_company": .id(company), "p_action": .string(action),
            "p_operation": .id(UUID()), "p_mutation": .id(UUID()),
            "p_payload": .object(payload)])
        try check(identity)
        return try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(run)
    }

    // MARK: authoring

    func draftTemplate(_ identity: NovaSessionIdentity, company: UUID, title: String) async throws {
        try await mutate(identity, company: company, action: "draft_template",
                         payload: ["title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines))])
    }

    func setItem(_ identity: NovaSessionIdentity, company: UUID, template: String, version: Int,
                 itemCode: String, prompt: String, allowsNotApplicable: Bool, position: Int) async throws {
        try await mutate(identity, company: company, action: "set_item", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "item_code": .string(itemCode),
            "prompt": .string(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
            "allows_not_applicable": .bool(allowsNotApplicable),
            "position": .number(Int64(position))])
    }

    func removeItem(_ identity: NovaSessionIdentity, company: UUID, template: String,
                    version: Int, itemCode: String) async throws {
        try await mutate(identity, company: company, action: "remove_item", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "item_code": .string(itemCode)])
    }

    /// Publishing is the expert's own approval of their own list. There is no
    /// field for naming someone else, and the server refuses one.
    func publishTemplate(_ identity: NovaSessionIdentity, company: UUID, template: String,
                         version: Int, note: String) async throws {
        try await mutate(identity, company: company, action: "publish_template", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "approval_note": .string(note.trimmingCharacters(in: .whitespacesAndNewlines))])
    }

    // MARK: runs

    func startRun(_ identity: NovaSessionIdentity, company: UUID, workplace: UUID,
                  template: String, startedOn: String) async throws -> NovaChecklistRun? {
        var payload: [String: PersonnelRPCValue] = [
            "workplace_id": .id(workplace), "template_code": .string(template)]
        if NovaDayField.date(startedOn) != nil { payload["started_on"] = .string(startedOn) }
        return try await mutate(identity, company: company, action: "start_run", payload: payload)
    }

    /// Answering one question. `open_nonconformity` is only ever sent when the
    /// expert asked for a record, so a failing answer alone opens nothing.
    func recordAnswer(_ identity: NovaSessionIdentity, company: UUID,
                      draft: NovaChecklistAnswerDraft) async throws -> NovaChecklistRun? {
        guard let run = draft.runID else { throw NovaChecklistFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "run_id": .id(run), "item_code": .string(draft.itemCode),
            "result": .string(draft.result.rawValue)]
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { payload["note"] = .string(note) }
        if draft.result == .nonconform && draft.openNonconformity {
            payload["open_nonconformity"] = .bool(true)
            payload["severity"] = .string(draft.severity.rawValue)
            if NovaDayField.date(draft.dueOn) != nil { payload["due_on"] = .string(draft.dueOn) }
        }
        return try await mutate(identity, company: company, action: "record_item", payload: payload)
    }

    func submitRun(_ identity: NovaSessionIdentity, company: UUID, run id: UUID) async throws -> NovaChecklistRun? {
        try await mutate(identity, company: company, action: "submit_run", payload: ["run_id": .id(id)])
    }

    func cancelRun(_ identity: NovaSessionIdentity, company: UUID, run id: UUID) async throws -> NovaChecklistRun? {
        try await mutate(identity, company: company, action: "cancel_run", payload: ["run_id": .id(id)])
    }
}
