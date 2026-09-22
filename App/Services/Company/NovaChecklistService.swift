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
        let atomic_item_code: String?
        let section_title: String?
        let scope_key: String?
        let allows_not_applicable: Bool
        let verification_method: String?
        let help_text: String?
        let tags: [String]?
        let risk_topic: String?
        let na_reason_required: Bool?
        let evidence_recommended: Bool?
        let photo_required: Bool?
        let source_ids: [String]?
        let result: String?
        let answer: String?
        let note: String?
        let evidence_asset_id: UUID?
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
        let submitted_at: String?
        let revision: Int64?
        let revises_run_id: UUID?
        let area_label: String?
        let equipment_label: String?
        let document_number: String?
        let expected: Int
        let answered: Int
        let remaining: Int
        let conform: Int
        let nonconform: Int
        let not_applicable: Int
        let progress_percent: Double?
        let coverage_percent: Double?
        let applicable_coverage_percent: Double?
        let score_percent: Double?
        let source_ids: [String]?
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
        let catalog_template_code: String?
        let sector_code: String?
        let kind: String?
        let scope_note: String?
        let professional_review_status: String?
    }
    private struct CatalogEnvelope: Decodable {
        let workplaces: [WorkplaceRow]
        let templates: [StarterRow]
        let product_templates_offered: Bool
        let catalog_version: String?
        let publication_status: String?
        let professional_review_status: String?
    }
    private struct TemplateItemRow: Decodable {
        let item_code: String
        let prompt: String
        let position: Int
        let atomic_item_code: String?
        let section_title: String?
        let scope_key: String?
        let allows_not_applicable: Bool
        let verification_method: String?
        let help_text: String?
        let tags: [String]?
        let risk_topic: String?
        let na_reason_required: Bool?
        let evidence_recommended: Bool?
        let photo_required: Bool?
        let source_ids: [String]?
    }
    private struct TemplateVersionRow: Decodable {
        let version: Int
        let revision: Int64?
        let status: String
        let published_at: String?
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
    private struct LibrarySectorRow: Decodable { let code: String; let name: String; let count: Int }
    private struct LibraryItemRow: Decodable {
        let template_code: String
        let catalog_template_code: String
        let title: String
        let sector_code: String?
        let sector_name: String?
        let kind: String
        let aliases: [String]
        let scope_note: String
        let professional_review_status: String
        let items: Int
        let source_ids: [String]
    }
    private struct LibraryEnvelope: Decodable {
        let catalog_version: String
        let publication_status: String
        let professional_review_status: String
        let sectors: [LibrarySectorRow]
        let rows: [LibraryItemRow]
        let matched_items: [LibraryMatchRow]?
        let total: Int
        let limit: Int
        let offset: Int
    }
    private struct LibraryMatchContextRow: Decodable {
        let template_code: String
        let catalog_template_code: String
        let title: String
        let sector_code: String?
        let sector_name: String?
        let item_code: String
    }
    private struct LibraryMatchRow: Decodable {
        let atomic_item_code: String
        let prompt: String
        let verification_method: String?
        let risk_topic: String?
        let tags: [String]?
        let source_ids: [String]?
        let contexts: [LibraryMatchContextRow]
    }
    private struct AssignmentRow: Decodable {
        let id: UUID
        let company_id: UUID
        let workplace_id: UUID?
        let workplace_name: String?
        let template_code: String
        let template_title: String
        let template_version: Int
        let assigned_at: String
    }
    private struct AssignmentsEnvelope: Decodable { let rows: [AssignmentRow] }
    private struct TemplateDetailRow: Decodable {
        let template_code: String
        let catalog_template_code: String?
        let catalog_version: String?
        let title: String
        let sector_code: String?
        let kind: String?
        let aliases: [String]?
        let scope_note: String?
        let source_ids: [String]?
        let is_product: Bool
        let professional_review_status: String?
        let version: Int
        let items: [TemplateItemRow]
    }
    private struct TemplateDetailEnvelope: Decodable { let row: TemplateDetailRow }

    /// An unknown state word is reported as open rather than smoothed into the
    /// calmest answer: the expert should look at the run.
    private func run(_ entry: RunRow) -> NovaChecklistRun {
        let answers: [NovaChecklistAnswer] = (entry.items ?? []).map {
            NovaChecklistAnswer(itemCode: $0.item_code, prompt: $0.prompt, position: $0.position,
                                atomicItemCode: $0.atomic_item_code,
                                sectionTitle: $0.section_title, scopeKey: $0.scope_key,
                                allowsNotApplicable: $0.allows_not_applicable,
                                verificationMethod: $0.verification_method, helpText: $0.help_text,
                                tags: $0.tags ?? [], riskTopic: $0.risk_topic,
                                naReasonRequired: $0.na_reason_required ?? false,
                                evidenceRecommended: $0.evidence_recommended ?? false,
                                photoRequired: $0.photo_required ?? false,
                                result: ($0.answer ?? $0.result).flatMap(NovaChecklistResult.init(wireValue:)),
                                note: $0.note, evidenceAssetID: $0.evidence_asset_id,
                                nonconformityID: $0.nonconformity_id)
        }
        return NovaChecklistRun(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            templateCode: entry.template_code, templateTitle: entry.template_title,
            templateVersion: entry.template_version,
            state: NovaChecklistRunState(rawValue: entry.state) ?? .open,
            startedOn: entry.started_on, submittedAt: entry.submitted_at,
            revision: entry.revision ?? 0, revisesRunID: entry.revises_run_id,
            areaLabel: entry.area_label, equipmentLabel: entry.equipment_label,
            documentNumber: entry.document_number,
            expected: entry.expected, answered: entry.answered, remaining: entry.remaining,
            conform: entry.conform, nonconform: entry.nonconform, notApplicable: entry.not_applicable,
            progressPercent: entry.progress_percent, coveragePercent: entry.coverage_percent,
            applicableCoveragePercent: entry.applicable_coverage_percent,
            scorePercent: entry.score_percent,
            sourceIDs: entry.source_ids ?? [],
            nonconformitiesOpened: entry.nonconformities_opened, answers: answers)
    }

    private func template(_ entry: TemplateRow) -> NovaChecklistTemplate {
        let versions: [NovaChecklistTemplateVersion] = (entry.versions ?? []).map { version in
            NovaChecklistTemplateVersion(
                version: version.version, revision: version.revision ?? 0,
                status: version.status, publishedAt: version.published_at,
                approvalNote: version.approval_note,
                items: (version.items ?? []).map {
                    NovaChecklistTemplateItem(itemCode: $0.item_code, prompt: $0.prompt,
                                              position: $0.position,
                                              atomicItemCode: $0.atomic_item_code,
                                              sectionTitle: $0.section_title, scopeKey: $0.scope_key,
                                              allowsNotApplicable: $0.allows_not_applicable,
                                              verificationMethod: $0.verification_method,
                                              helpText: $0.help_text, tags: $0.tags ?? [],
                                              riskTopic: $0.risk_topic,
                                              naReasonRequired: $0.na_reason_required ?? false,
                                              evidenceRecommended: $0.evidence_recommended ?? false,
                                              photoRequired: $0.photo_required ?? false,
                                              sourceIDs: $0.source_ids ?? [])
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
                                                              isProduct: $0.is_product,
                                                              catalogTemplateCode: $0.catalog_template_code,
                                                              sectorCode: $0.sector_code, kind: $0.kind,
                                                              scopeNote: $0.scope_note,
                                                              professionalReviewStatus: $0.professional_review_status) },
                     productTemplatesOffered: envelope.product_templates_offered,
                     catalogVersion: envelope.catalog_version,
                     publicationStatus: envelope.publication_status,
                     professionalReviewStatus: envelope.professional_review_status)
    }

    func library(_ identity: NovaSessionIdentity, search: String = "", sector: String? = nil,
                 kind: String? = nil, limit: Int = 30, offset: Int = 0) async throws -> NovaChecklistLibrary {
        try check(identity)
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try await read([
            "p_kind": .string("library"), "p_query": needle.isEmpty ? .null : .string(needle),
            "p_template": sector.map { .string($0) } ?? .null,
            "p_state": kind.map { .string($0) } ?? .null,
            "p_limit": .number(Int64(limit)), "p_offset": .number(Int64(offset))])
        try check(identity)
        let envelope = try JSONDecoder().decode(LibraryEnvelope.self, from: data)
        return .init(catalogVersion: envelope.catalog_version,
            publicationStatus: envelope.publication_status,
            professionalReviewStatus: envelope.professional_review_status,
            sectors: envelope.sectors.map { .init(code: $0.code, name: $0.name, count: $0.count) },
            rows: envelope.rows.map { .init(templateCode: $0.template_code,
                catalogTemplateCode: $0.catalog_template_code, title: $0.title,
                sectorCode: $0.sector_code, sectorName: $0.sector_name, kind: $0.kind,
                aliases: $0.aliases, scopeNote: $0.scope_note,
                professionalReviewStatus: $0.professional_review_status, items: $0.items,
                sourceIDs: $0.source_ids) },
            matchedItems: (envelope.matched_items ?? []).map { match in
                .init(atomicItemCode: match.atomic_item_code, prompt: match.prompt,
                    verificationMethod: match.verification_method, riskTopic: match.risk_topic,
                    tags: match.tags ?? [], sourceIDs: match.source_ids ?? [],
                    contexts: match.contexts.map { .init(templateCode: $0.template_code,
                        catalogTemplateCode: $0.catalog_template_code, title: $0.title,
                        sectorCode: $0.sector_code, sectorName: $0.sector_name,
                        itemCode: $0.item_code) })
            }, total: envelope.total,
            limit: envelope.limit, offset: envelope.offset)
    }

    func templateDetail(_ identity: NovaSessionIdentity, template: String) async throws -> NovaChecklistTemplateDetail {
        try check(identity)
        let data = try await read(["p_kind": .string("template_detail"), "p_template": .string(template)])
        try check(identity)
        let row = try JSONDecoder().decode(TemplateDetailEnvelope.self, from: data).row
        return .init(templateCode: row.template_code, catalogTemplateCode: row.catalog_template_code,
            catalogVersion: row.catalog_version, title: row.title, sectorCode: row.sector_code,
            kind: row.kind, aliases: row.aliases ?? [], scopeNote: row.scope_note,
            sourceIDs: row.source_ids ?? [], isProduct: row.is_product,
            professionalReviewStatus: row.professional_review_status, version: row.version,
            items: row.items.map { .init(itemCode: $0.item_code, prompt: $0.prompt,
                position: $0.position, atomicItemCode: $0.atomic_item_code,
                sectionTitle: $0.section_title, scopeKey: $0.scope_key,
                allowsNotApplicable: $0.allows_not_applicable,
                verificationMethod: $0.verification_method, helpText: $0.help_text,
                tags: $0.tags ?? [], riskTopic: $0.risk_topic,
                naReasonRequired: $0.na_reason_required ?? false,
                evidenceRecommended: $0.evidence_recommended ?? false,
                photoRequired: $0.photo_required ?? false, sourceIDs: $0.source_ids ?? []) })
    }

    func assignments(_ identity: NovaSessionIdentity, company: UUID) async throws -> [NovaChecklistAssignment] {
        try check(identity)
        let data = try await read(["p_company": .id(company), "p_kind": .string("assignments")])
        try check(identity)
        return try JSONDecoder().decode(AssignmentsEnvelope.self, from: data).rows.map {
            .init(id: $0.id, companyID: $0.company_id, workplaceID: $0.workplace_id,
                workplaceName: $0.workplace_name, templateCode: $0.template_code,
                templateTitle: $0.template_title, templateVersion: $0.template_version,
                assignedAt: $0.assigned_at)
        }
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
    private func mutate(_ identity: NovaSessionIdentity, company: UUID?, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaChecklistRun? {
        try check(identity)
        return try await NovaModuleMutationJournal.run(function: "isg_checklists_mutate_v1", identity: identity,
            company: company, action: action, payload: payload, rpc: rpc,
            validate: { try check(identity) }, decode: { data in
                try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(run)
            })
    }

    // MARK: authoring

    func draftTemplate(_ identity: NovaSessionIdentity, company: UUID?, title: String) async throws {
        try await mutate(identity, company: company, action: "draft_template",
                         payload: ["title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines))])
    }

    func setItem(_ identity: NovaSessionIdentity, company: UUID?, template: String, version: Int,
                 itemCode: String, prompt: String, allowsNotApplicable: Bool, position: Int,
                 expectedRevision: Int64, sectionTitle: String = "", scopeKey: String = "") async throws {
        var payload: [String: PersonnelRPCValue] = [
            "template_code": .string(template), "version": .number(Int64(version)),
            "item_code": .string(itemCode),
            "prompt": .string(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
            "allows_not_applicable": .bool(allowsNotApplicable),
            "position": .number(Int64(position)),
            "expected_revision": .number(expectedRevision)]
        if !sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["section_title"] = .string(sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !scopeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["scope_key"] = .string(scopeKey.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try await mutate(identity, company: company, action: "set_item", payload: payload)
    }

    func copyItems(_ identity: NovaSessionIdentity, company: UUID?, template: String,
                   version: Int, expectedRevision: Int64,
                   items: [NovaChecklistItemSelection]) async throws {
        let encoded: [PersonnelRPCValue] = items.map { item in
            var fields: [String: PersonnelRPCValue] = [
                "source_template_code": .string(item.sourceTemplateCode),
                "source_item_code": .string(item.sourceItemCode),
                "allow_duplicate": .bool(item.allowDuplicate)]
            if !item.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields["section_title"] = .string(item.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if !item.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields["scope_key"] = .string(item.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .object(fields)
        }
        try await mutate(identity, company: company, action: "copy_items", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "expected_revision": .number(expectedRevision), "items": .array(encoded)])
    }

    func reorderItems(_ identity: NovaSessionIdentity, company: UUID?, template: String,
                      version: Int, expectedRevision: Int64, itemCodes: [String]) async throws {
        try await mutate(identity, company: company, action: "reorder_items", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "expected_revision": .number(expectedRevision),
            "item_codes": .array(itemCodes.map(PersonnelRPCValue.string))])
    }

    func removeItem(_ identity: NovaSessionIdentity, company: UUID?, template: String,
                    version: Int, expectedRevision: Int64, itemCode: String) async throws {
        try await mutate(identity, company: company, action: "remove_item", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "expected_revision": .number(expectedRevision), "item_code": .string(itemCode)])
    }

    /// Publishing is the expert's own approval of their own list. There is no
    /// field for naming someone else, and the server refuses one.
    func publishTemplate(_ identity: NovaSessionIdentity, company: UUID?, template: String,
                         version: Int, expectedRevision: Int64, note: String) async throws {
        try await mutate(identity, company: company, action: "publish_template", payload: [
            "template_code": .string(template), "version": .number(Int64(version)),
            "expected_revision": .number(expectedRevision),
            "approval_note": .string(note.trimmingCharacters(in: .whitespacesAndNewlines))])
    }

    func copyTemplate(_ identity: NovaSessionIdentity, company: UUID?, template: String,
                      title: String? = nil) async throws {
        var payload: [String: PersonnelRPCValue] = ["template_code": .string(template)]
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["title"] = .string(title.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        try await mutate(identity, company: company, action: "copy_template", payload: payload)
    }

    func assignTemplate(_ identity: NovaSessionIdentity, company: UUID, workplace: UUID?,
                        template: String) async throws {
        try await mutate(identity, company: company, action: "assign_template", payload: [
            "template_code": .string(template),
            "workplace_id": workplace.map { .id($0) } ?? .null])
    }

    func deactivateAssignment(_ identity: NovaSessionIdentity, company: UUID,
                              assignment: UUID) async throws {
        try await mutate(identity, company: company, action: "deactivate_assignment",
                         payload: ["assignment_id": .id(assignment)])
    }

    // MARK: runs

    func startRun(_ identity: NovaSessionIdentity, company: UUID?, workplace: UUID?,
                  template: String, startedOn: String, areaLabel: String = "",
                  equipmentLabel: String = "", documentNumber: String = "") async throws -> NovaChecklistRun? {
        var payload: [String: PersonnelRPCValue] = ["template_code": .string(template)]
        if let workplace { payload["workplace_id"] = .id(workplace) }
        if NovaDayField.date(startedOn) != nil { payload["started_on"] = .string(startedOn) }
        if !areaLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["area_label"] = .string(areaLabel.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !equipmentLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["equipment_label"] = .string(equipmentLabel.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !documentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["document_number"] = .string(documentNumber.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try await mutate(identity, company: company, action: "start_run", payload: payload)
    }

    /// Answering one question. `open_nonconformity` is only ever sent when the
    /// expert asked for a record, so a failing answer alone opens nothing.
    func recordAnswer(_ identity: NovaSessionIdentity, company: UUID?,
                      draft: NovaChecklistAnswerDraft) async throws -> NovaChecklistRun? {
        guard let run = draft.runID else { throw NovaChecklistFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "run_id": .id(run), "item_code": .string(draft.itemCode),
            "result": .string(draft.result.wireValue),
            "expected_revision": .number(draft.expectedRevision)]
        let note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { payload["note"] = .string(note) }
        if let asset = draft.evidenceAssetID { payload["evidence_asset_id"] = .id(asset) }
        if draft.result == .nonconform && draft.openNonconformity {
            payload["open_nonconformity"] = .bool(true)
            payload["severity"] = .string(draft.severity.rawValue)
            if NovaDayField.date(draft.dueOn) != nil { payload["due_on"] = .string(draft.dueOn) }
        }
        return try await mutate(identity, company: company, action: "record_item", payload: payload)
    }

    func submitRun(_ identity: NovaSessionIdentity, company: UUID?, run id: UUID,
                   expectedRevision: Int64) async throws -> NovaChecklistRun? {
        try await mutate(identity, company: company, action: "submit_run", payload: [
            "run_id": .id(id), "expected_revision": .number(expectedRevision)])
    }

    func cancelRun(_ identity: NovaSessionIdentity, company: UUID?, run id: UUID,
                   expectedRevision: Int64) async throws -> NovaChecklistRun? {
        try await mutate(identity, company: company, action: "cancel_run", payload: [
            "run_id": .id(id), "expected_revision": .number(expectedRevision)])
    }

    func reviseRun(_ identity: NovaSessionIdentity, company: UUID?, run id: UUID,
                   expectedRevision: Int64, startedOn: String) async throws -> NovaChecklistRun? {
        var payload: [String: PersonnelRPCValue] = [
            "run_id": .id(id), "expected_revision": .number(expectedRevision)]
        if NovaDayField.date(startedOn) != nil { payload["started_on"] = .string(startedOn) }
        return try await mutate(identity, company: company, action: "revise_run", payload: payload)
    }
}
