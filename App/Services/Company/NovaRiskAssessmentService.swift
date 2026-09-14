import Foundation

/// Same shape as the personnel, equipment and document tracking services: a
/// plain RPC closure, a session check and no SDK type in the design system.
@MainActor struct NovaRiskAssessmentService {
    typealias RPC = (String, [String: PersonnelRPCValue]) async throws -> Data
    private let rpc: RPC
    private let isSession: (NovaSessionIdentity) -> Bool

    init(rpc: @escaping RPC, isSession: @escaping (NovaSessionIdentity) -> Bool) {
        self.rpc = rpc; self.isSession = isSession
    }

    private func check(_ identity: NovaSessionIdentity) throws {
        guard isSession(identity) else { throw NovaRiskFailure.denied }
    }

    // MARK: transport rows

    private struct SourceRow: Decodable {
        let id: UUID
        let analysis_id: UUID
        let finding_id: UUID
        let source_version: Int
        let selected_at: Date?
    }
    private struct ImpactRow: Decodable {
        let id: UUID
        let target_kind: String
        let target_ref: String
        let action: String
        let note: String?
    }
    private struct VersionRow: Decodable {
        let version: Int
        let kind: String
        let edit_revision: Int?
        let cancellation_note: String?
        let previous_version: Int?
        let assessment_on: String
        let revision_on: String?
        let scope: [String]?
        let reason: String?
        let state: String
        let finalized_at: Date?
        let period_years: Int?
        let period_source: String?
        let period_needs_review: Bool?
        let date_needs_review: Bool?
        let valid_until: String?
        let source_drift: Bool?
        let drift_note: String?
        let file_asset_id: UUID?
        let sources: [SourceRow]?
        let impacts: [ImpactRow]?
    }
    private struct AssessmentRow: Decodable {
        let id: UUID
        var company_id: UUID?
        var company_name: String?
        let workplace_id: UUID?
        var workplace_name: String?
        let current_version: Int
        let base_assessment_on: String?
        let valid_until: String?
        let state: String
        let notice_days: Int
        let current_kind: String?
        let current_assessment_on: String?
        let current_revision_on: String?
        let period_years: Int?
        let period_source: String?
        let period_needs_review: Bool?
        let date_needs_review: Bool?
        let source_drift: Bool?
        let drift_note: String?
        let has_open_draft: Bool
        let draft_version: Int?
        let draft_kind: String?
        let draft_assessment_on: String?
        let draft_reason: String?
        let source_link_count: Int?
        let versions: [VersionRow]?
    }
    private struct WorkplaceRow: Decodable { let id: UUID; let name: String; let needs_review: Bool }
    private struct RuleRow: Decodable { let rule_code: String; let period_kind: String; let period_length: Int? }
    private struct CatalogEnvelope: Decodable {
        let workplaces: [WorkplaceRow]
        let rules: [RuleRow]
        let notice_days: Int
        let expert_period_needs_review: Bool
    }
    private struct CompanyRow: Decodable { let id: UUID; let name: String; let total: Int; let counts: [String: Int] }
    private struct ListEnvelope: Decodable {
        let rows: [AssessmentRow]
        let companies: [CompanyRow]
        let counts: [String: Int]
        let total: Int
        let has_more: Bool
        let offset: Int
        let notice_days: Int
    }
    private struct DetailEnvelope: Decodable { let row: AssessmentRow }
    private struct MutationEnvelope: Decodable { let assessment_id: UUID?; let row: AssessmentRow? }

    /// An unknown state word is reported as never assessed rather than smoothed
    /// into the calmest answer: the expert should look at the row.
    private func row(_ entry: AssessmentRow) -> NovaRiskRow {
        let state = NovaRiskState(rawValue: entry.state) ?? .neverAssessed
        let kind = entry.current_kind.flatMap(NovaRiskKind.init(rawValue:))
        let draftKind = entry.draft_kind.flatMap(NovaRiskKind.init(rawValue:))
        let source = entry.period_source.flatMap(NovaRiskPeriodSource.init(rawValue:))
        return NovaRiskRow(
            id: entry.id, companyID: entry.company_id, companyName: entry.company_name,
            workplaceID: entry.workplace_id, workplaceName: entry.workplace_name,
            currentVersion: entry.current_version, baseAssessmentOn: entry.base_assessment_on,
            validUntil: entry.valid_until, state: state, group: NovaRiskGroup.of(state),
            noticeDays: entry.notice_days,
            currentKind: kind,
            currentAssessmentOn: entry.current_assessment_on,
            currentRevisionOn: entry.current_revision_on,
            periodYears: entry.period_years,
            periodSource: source,
            periodNeedsReview: entry.period_needs_review,
            dateNeedsReview: entry.date_needs_review ?? false,
            sourceDrift: entry.source_drift ?? false, driftNote: entry.drift_note,
            hasOpenDraft: entry.has_open_draft, draftVersion: entry.draft_version,
            draftKind: draftKind,
            draftAssessmentOn: entry.draft_assessment_on, draftReason: entry.draft_reason,
            sourceLinkCount: entry.source_link_count ?? 0,
            versions: (entry.versions ?? []).map(self.version))
    }

    /// Kept apart from `row` so the type checker solves two small expressions
    /// rather than one that times out.
    private func version(_ entry: VersionRow) -> NovaRiskVersion {
        let sources: [NovaRiskSource] = (entry.sources ?? []).map {
            NovaRiskSource(id: $0.id, analysisID: $0.analysis_id, findingID: $0.finding_id,
                           sourceVersion: $0.source_version, selectedAt: $0.selected_at)
        }
        let impacts: [NovaRiskImpact] = (entry.impacts ?? []).map {
            NovaRiskImpact(id: $0.id, targetKind: $0.target_kind, targetRef: $0.target_ref,
                           action: $0.action, note: $0.note)
        }
        return NovaRiskVersion(
            version: entry.version,
            kind: NovaRiskKind(rawValue: entry.kind) ?? .full,
            previousVersion: entry.previous_version,
            assessmentOn: entry.assessment_on, revisionOn: entry.revision_on,
            scope: entry.scope ?? [], reason: entry.reason, state: entry.state,
            finalizedAt: entry.finalized_at, periodYears: entry.period_years,
            periodSource: entry.period_source.flatMap(NovaRiskPeriodSource.init(rawValue:)),
            periodNeedsReview: entry.period_needs_review ?? false,
            dateNeedsReview: entry.date_needs_review ?? false,
            validUntil: entry.valid_until, sourceDrift: entry.source_drift ?? false,
            driftNote: entry.drift_note, fileAssetID: entry.file_asset_id,
            sources: sources, impacts: impacts, editRevision: entry.edit_revision ?? 0, cancellationNote: entry.cancellation_note)
    }

    private func read(_ arguments: [String: PersonnelRPCValue]) async throws -> Data {
        var payload: [String: PersonnelRPCValue] = [
            "p_company": .null, "p_kind": .string("list"), "p_query": .null, "p_state": .null,
            "p_workplace": .null, "p_id": .null, "p_limit": .null, "p_offset": .null]
        for (key, value) in arguments { payload[key] = value }
        return try await rpc("isg_risk_versions_read_v1", payload)
    }

    // MARK: reads

    /// The workplaces this company has, the rules a period could be attributed
    /// to, and the warning window. An empty rule list is the honest answer while
    /// no rule set has been approved.
    func catalogue(_ identity: NovaSessionIdentity, company: UUID?) async throws -> NovaRiskCatalogue {
        try check(identity)
        let data = try await read(["p_company": company.map { .id($0) } ?? .null,
                                   "p_kind": .string("catalog")])
        try check(identity)
        let envelope = try JSONDecoder().decode(CatalogEnvelope.self, from: data)
        return .init(workplaces: envelope.workplaces.map { .init(id: $0.id, name: $0.name, needsReview: $0.needs_review) },
                     rules: envelope.rules.map { .init(ruleCode: $0.rule_code, periodKind: $0.period_kind,
                                                       periodLength: $0.period_length) },
                     noticeDays: envelope.notice_days,
                     expertPeriodNeedsReview: envelope.expert_period_needs_review)
    }

    func board(_ identity: NovaSessionIdentity, query: NovaRiskQuery) async throws -> NovaRiskBoard {
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
        return .init(rows: envelope.rows.map(row), counts: envelope.counts,
                     companies: envelope.companies.map { .init(id: $0.id, name: $0.name, total: $0.total,
                                                               counts: $0.counts) },
                     total: envelope.total, hasMore: envelope.has_more, offset: envelope.offset,
                     noticeDays: envelope.notice_days)
    }

    func detail(_ identity: NovaSessionIdentity, assessment: UUID) async throws -> NovaRiskRow {
        try check(identity)
        let data = try await read(["p_kind": .string("detail"), "p_id": .id(assessment)])
        try check(identity)
        return row(try JSONDecoder().decode(DetailEnvelope.self, from: data).row)
    }

    // MARK: writes

    private func mutate(_ identity: NovaSessionIdentity, company: UUID, action: String,
                        payload: [String: PersonnelRPCValue]) async throws -> NovaRiskRow? {
        try check(identity)
        return try await NovaModuleMutationJournal.run(function: "isg_risk_versions_mutate_v1", identity: identity, company: company, action: action, payload: payload, rpc: rpc, validate: { try check(identity) }, decode: { data in
            try JSONDecoder().decode(MutationEnvelope.self, from: data).row.map(row)
        })
    }

    /// Opening a workplace's record twice is the same record; the server says so
    /// rather than making a second one.
    func open(_ identity: NovaSessionIdentity, company: UUID, workplace: UUID) async throws -> NovaRiskRow? {
        try await mutate(identity, company: company, action: "open_assessment",
                         payload: ["workplace_id": .id(workplace)])
    }

    func draft(_ identity: NovaSessionIdentity, company: UUID,
               draft: NovaRiskVersionDraft) async throws -> NovaRiskRow? {
        guard let assessment = draft.assessmentID else { throw NovaRiskFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "assessment_id": .id(assessment), "kind": .string(draft.kind.rawValue),
            "expected_current": .number(Int64(draft.expectedCurrent))]
        // Only a full renewal carries a date of its own. Sending one on the
        // others is what the server calls ASSESSMENT_DATE_IMMUTABLE, so the
        // client does not send it at all.
        // The field already carries the ISO day the server stores, so it is
        // sent as typed once it parses as a real date.
        if draft.kind.carriesAssessmentDate, NovaDayField.date(draft.assessmentOn) != nil {
            payload["assessment_on"] = .string(draft.assessmentOn)
        }
        if NovaDayField.date(draft.revisionOn) != nil {
            payload["revision_on"] = .string(draft.revisionOn)
        }
        if draft.kind.needsScope { payload["scope"] = .array(draft.scope.map { .string($0) }) }
        let reason = draft.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { payload["reason"] = .string(reason) }
        if let version = draft.versionToEdit {
            payload.removeValue(forKey: "kind")
            payload["version"] = .number(Int64(version))
            payload["expected_edit_revision"] = .number(Int64(draft.editRevision))
            return try await mutate(identity, company: company, action: "edit_draft", payload: payload)
        }
        return try await mutate(identity, company: company, action: "draft_version", payload: payload)
    }

    func cancelDraft(_ identity: NovaSessionIdentity, company: UUID, row: NovaRiskRow, version: NovaRiskVersion, reason: String) async throws -> NovaRiskRow? {
        try await mutate(identity, company: company, action: "cancel_draft", payload: ["assessment_id": .id(row.id), "version": .number(Int64(version.version)), "expected_current": .number(Int64(row.currentVersion)), "expected_edit_revision": .number(Int64(version.editRevision)), "cancellation_note": .string(reason)])
    }

    /// The verification is the signed-in expert's own: there is no field for
    /// naming someone else, and the server refuses one.
    func finalize(_ identity: NovaSessionIdentity, company: UUID,
                  draft: NovaRiskFinalizeDraft) async throws -> NovaRiskRow? {
        guard let assessment = draft.assessmentID else { throw NovaRiskFailure.validation }
        var payload: [String: PersonnelRPCValue] = [
            "assessment_id": .id(assessment), "version": .number(Int64(draft.version)),
            "expected_current": .number(Int64(draft.expectedCurrent))]
        payload["expected_edit_revision"] = .number(Int64(draft.editRevision))
        let rule = draft.ruleCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rule.isEmpty {
            payload["rule_code"] = .string(rule)
        } else if let years = Int(draft.periodYears.trimmingCharacters(in: .whitespacesAndNewlines)) {
            payload["period_years"] = .number(Int64(years))
        }
        return try await mutate(identity, company: company, action: "finalize_version", payload: payload)
    }

    /// Carrying a finding over is an action the expert takes. It writes nothing
    /// back to the analysis, and the response says so.
    func attachSource(_ identity: NovaSessionIdentity, company: UUID, assessment: UUID, version: Int,
                      analysis: UUID, finding: UUID, sourceVersion: Int,
                      fields: [String: String]) async throws -> NovaRiskRow? {
        try await mutate(identity, company: company, action: "attach_source", payload: [
            "assessment_id": .id(assessment), "version": .number(Int64(version)),
            "analysis_id": .id(analysis), "finding_id": .id(finding),
            "source_version": .number(Int64(sourceVersion)),
            "copied_fields": .object(fields.mapValues { .string($0) })])
    }

    func recordImpact(_ identity: NovaSessionIdentity, company: UUID, assessment: UUID, version: Int,
                      targetKind: String, targetRef: String, action: String,
                      note: String) async throws -> NovaRiskRow? {
        var payload: [String: PersonnelRPCValue] = [
            "assessment_id": .id(assessment), "version": .number(Int64(version)),
            "target_kind": .string(targetKind), "target_ref": .string(targetRef), "action": .string(action)]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["note"] = .string(trimmed) }
        return try await mutate(identity, company: company, action: "record_impact", payload: payload)
    }

    /// A source that moved on raises a flag for review. The finalised document
    /// is never rewritten, and the server returns it unchanged to prove it.
    func flagDrift(_ identity: NovaSessionIdentity, company: UUID, assessment: UUID, version: Int,
                   analysis: UUID, currentSourceVersion: Int, note: String) async throws -> NovaRiskRow? {
        var payload: [String: PersonnelRPCValue] = [
            "assessment_id": .id(assessment), "version": .number(Int64(version)),
            "analysis_id": .id(analysis), "current_source_version": .number(Int64(currentSourceVersion))]
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { payload["note"] = .string(trimmed) }
        return try await mutate(identity, company: company, action: "flag_drift", payload: payload)
    }
}
