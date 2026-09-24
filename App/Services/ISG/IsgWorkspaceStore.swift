import Foundation
import Combine

/// Session-owned workspace state for the opt-in OSGB shell. This store is not
/// wired into the legacy personal root while the rollout flag is off.
@MainActor final class IsgWorkspaceStore: ObservableObject {
    enum Phase: Equatable { case signedOut, loading, choosing, ready, failed }

    @Published private(set) var phase: Phase = .signedOut
    @Published private(set) var contexts: [IsgWorkspaceContext] = []
    @Published private(set) var selection: NovaWorkspaceSelection?
    @Published private(set) var selectedCompanyID: UUID?
    @Published private(set) var dashboard: IsgWorkspaceDashboard?
    @Published private(set) var companies: [IsgWorkspaceCompany] = []

    private var identity: NovaSessionIdentity?
    private var generation = UUID()
    private var request: Task<Void, Never>?
    private let rpc: IsgWorkspaceAPI.RPC?
    private lazy var api: IsgWorkspaceAPI = {
        if let rpc {
            return IsgWorkspaceAPI(rpc: rpc, currentIdentity: { [weak self] in self?.identity },
                isCurrentWorkspace: { [weak self] in self?.selection == $0 },
                currentEpoch: { [weak self] in self?.generation })
        }
        return .live(currentIdentity: { [weak self] in self?.identity },
                     currentSelection: { [weak self] in self?.selection },
                     currentEpoch: { [weak self] in self?.generation })
    }()

    init(rpc: IsgWorkspaceAPI.RPC? = nil) { self.rpc = rpc }

    deinit { request?.cancel() }

    func adopt(_ next: NovaSessionIdentity?) {
        guard identity != next else { return }
        identity = next
        invalidate()
        guard let next else { phase = .signedOut; return }
        phase = .loading
        let token = generation
        request = Task { [weak self] in await self?.load(identity: next, preferredWorkspaceID: nil, token: token) }
    }

    func select(_ context: IsgWorkspaceContext) {
        guard context.membership.userID == identity?.userID, context.canRead,
              contexts.contains(context) else { return }
        invalidateContent()
        selection = context.selection
        phase = .loading
        let token = generation
        request = Task { [weak self] in await self?.resolve(context: context, token: token) }
    }

    func select(workspaceID: UUID) {
        guard let context = contexts.first(where: { $0.workspaceID == workspaceID }) else { return }
        select(context)
    }

    func refresh() {
        guard let identity else { return }
        let preferredWorkspaceID = selection?.workspaceID
        // Revalidation is not a workspace switch. Keep the routing identity
        // while invalidating requests/content; otherwise the shared expert
        // transport briefly becomes personal and rejects its availability load.
        invalidateContent()
        phase = .loading
        let token = generation
        request = Task { [weak self] in
            await self?.load(identity: identity, preferredWorkspaceID: preferredWorkspaceID, token: token)
        }
    }

    func selectCompany(_ companyID: UUID?) {
        guard let identity, let selection, phase == .ready,
              companyID == nil || companies.contains(where: { $0.id == companyID }) else { return }
        let role = contexts.first(where: { $0.workspaceID == selection.workspaceID })?.membership.role
        if selection.kind == "osgb", role == "expert", companyID == nil { return }
        generation = UUID(); request?.cancel(); request = nil
        selectedCompanyID = companyID; dashboard = nil; phase = .loading
        let token = generation
        request = Task { [weak self] in
            await self?.loadDashboard(identity: identity, selection: selection,
                                      companyID: companyID, token: token)
        }
    }

    func createWorkspace(mutationID: UUID, name: String,
                         timezone: String = TimeZone.current.identifier) async throws -> IsgWorkspaceContext {
        let identity = try expectedIdentity()
        let context = try await api.createWorkspace(identity: identity, mutationID: mutationID,
                                                     name: name, timezone: timezone)
        guard self.identity == identity else { throw IsgWorkspaceAPIFailure.staleSession }
        contexts.removeAll { $0.workspaceID == context.workspaceID }
        contexts.append(context)
        contexts.sort { $0.workspaceID.uuidString.lowercased() < $1.workspaceID.uuidString.lowercased() }
        select(context)
        return context
    }

    func acceptInvitation(mutationID: UUID, token: String) async throws -> IsgWorkspaceContext {
        let identity = try expectedIdentity()
        let context = try await api.acceptInvitation(identity: identity, mutationID: mutationID, token: token)
        guard self.identity == identity else { throw IsgWorkspaceAPIFailure.staleSession }
        contexts.removeAll { $0.workspaceID == context.workspaceID }
        contexts.append(context)
        contexts.sort { $0.workspaceID.uuidString.lowercased() < $1.workspaceID.uuidString.lowercased() }
        select(context)
        return context
    }

    func members(status: String = "all") async throws -> [IsgWorkspaceMember] {
        let selection = try expectedSelection()
        var rows: [IsgWorkspaceMember] = []
        var cursor: UUID?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 100 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let page = try await api.members(selection: selection, status: status, after: cursor, limit: 100)
            rows.append(contentsOf: page.rows)
            cursor = page.next
        } while cursor != nil
        try requireCurrent(selection)
        return rows
    }

    func invitations(status: String = "all") async throws -> [IsgWorkspaceInvitation] {
        let selection = try expectedSelection()
        var rows: [IsgWorkspaceInvitation] = []
        var cursor: UUID?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 100 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let page = try await api.invitations(selection: selection, status: status, after: cursor, limit: 100)
            rows.append(contentsOf: page.rows)
            cursor = page.next
        } while cursor != nil
        try requireCurrent(selection)
        return rows
    }

    func invite(mutationID: UUID, email: String, role: String,
                expiresAt: String) async throws -> IsgWorkspaceInvitationToken {
        let selection = try expectedSelection()
        return try await api.invite(selection: selection, mutationID: mutationID,
                                    email: email, role: role, expiresAt: expiresAt)
    }

    func resendInvitation(mutationID: UUID, invitation: IsgWorkspaceInvitation,
                          expiresAt: String) async throws -> IsgWorkspaceInvitationToken {
        let selection = try expectedSelection()
        return try await api.resendInvitation(selection: selection, mutationID: mutationID,
            invitationID: invitation.id, expectedVersion: invitation.version, expiresAt: expiresAt)
    }

    func revokeInvitation(mutationID: UUID, invitation: IsgWorkspaceInvitation) async throws {
        let selection = try expectedSelection()
        try await api.revokeInvitation(selection: selection, mutationID: mutationID,
            invitationID: invitation.id, expectedVersion: invitation.version)
    }

    func mutateMember(mutationID: UUID, member: IsgWorkspaceMember, action: String,
                      value: String? = nil, reason: String? = nil) async throws -> IsgWorkspaceMember {
        let selection = try expectedSelection()
        return try await api.mutateMember(selection: selection, mutationID: mutationID,
            membershipID: member.id, expectedVersion: member.version,
            action: action, value: value, reason: reason)
    }

    func createCompany(mutationID: UUID, profileMutationID: UUID,
                       draft: IsgWorkspaceCompanyDraft) async throws -> IsgWorkspaceCompany {
        let selection = try expectedSelection(operate: true)
        let company = try await api.createCompany(selection: selection, mutationID: mutationID,
                                                  profileMutationID: profileMutationID, draft: draft)
        try requireCurrent(selection)
        companies.removeAll { $0.id == company.id }
        companies.append(company)
        companies.sort { $0.id.uuidString.lowercased() < $1.id.uuidString.lowercased() }
        selectedCompanyID = company.id
        // The mutation is already committed at this point. A transient summary
        // failure must not turn a successful create into a false failure.
        try await refreshDashboardAfterMutation(selection)
        return company
    }

    func updateCompany(mutationID: UUID, profileMutationID: UUID, companyID: UUID,
                       expectedVersion: Int64, expectedProfileVersion: Int64,
                       draft: IsgWorkspaceCompanyDraft) async throws -> IsgWorkspaceCompany {
        let selection = try expectedSelection(operate: true)
        let company = try await api.updateCompany(selection: selection, mutationID: mutationID,
            profileMutationID: profileMutationID, companyID: companyID, expectedVersion: expectedVersion,
            expectedProfileVersion: expectedProfileVersion, draft: draft)
        try requireCurrent(selection)
        if let index = companies.firstIndex(where: { $0.id == companyID }) { companies[index] = company }
        if selectedCompanyID == companyID {
            try await refreshDashboardAfterMutation(selection)
        }
        return company
    }

    func archiveCompany(mutationID: UUID, companyID: UUID, expectedVersion: Int64,
                        reason: String) async throws {
        let selection = try expectedSelection(operate: true)
        try await api.archiveCompany(selection: selection, mutationID: mutationID,
            companyID: companyID, expectedVersion: expectedVersion, reason: reason)
        try requireCurrent(selection)
        companies.removeAll { $0.id == companyID }
        if selectedCompanyID == companyID { selectedCompanyID = nil }
        try await refreshDashboardAfterMutation(selection)
    }

    func assignments(companyID: UUID? = nil, status: String = "all") async throws
        -> [IsgWorkspaceCompanyAssignment] {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        var rows: [IsgWorkspaceCompanyAssignment] = []
        var cursor: UUID?
        var pageCount = 0
        repeat {
            pageCount += 1
            guard pageCount <= 100 else { throw IsgWorkspaceAPIFailure.invalidResponse }
            let page = try await api.assignments(selection: selection, companyID: companyID,
                                                 status: status, after: cursor, limit: 100)
            rows.append(contentsOf: page.rows)
            cursor = page.next
        } while cursor != nil
        try requireCurrent(selection)
        return rows
    }

    func mutateAssignment(mutationID: UUID, companyID: UUID? = nil, action: String,
                          assignmentID: UUID? = nil, membershipID: UUID? = nil,
                          expectedVersion: Int64 = 0, role: String? = nil,
                          startsAt: String? = nil, endsAt: String? = nil,
                          reason: String) async throws -> IsgWorkspaceCompanyAssignment {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else {
            throw IsgWorkspaceAPIFailure.invalidRequest
        }
        let result = try await api.mutateAssignment(selection: selection, mutationID: mutationID,
            companyID: companyID, action: action, assignmentID: assignmentID,
            membershipID: membershipID, expectedVersion: expectedVersion, role: role,
            startsAt: startsAt, endsAt: endsAt, reason: reason)
        try requireCurrent(selection)
        try await refreshDashboardAfterMutation(selection)
        return result
    }

    func personnelMetrics(companyID: UUID? = nil) async throws -> IsgPersonnelMetrics {
        let selection = try expectedSelection()
        return try await api.personnelMetrics(selection: selection, companyID: companyID ?? selectedCompanyID)
    }

    /// Experts are authorized company-by-company, so the server deliberately
    /// rejects a workspace-wide dashboard request for that role. Build the
    /// home summary from the expert's already-filtered company directory and
    /// add the authorized company snapshots. This keeps the overview useful
    /// without weakening the tenant boundary or requiring a company picker on
    /// the home page.
    func aggregateExpertDashboard() async throws -> IsgWorkspaceDashboard {
        let selection = try expectedSelection()
        let assignedCompanies = companies
        var nonconformities = IsgWorkspaceDashboard.Pair(first: 0, second: 0)
        var visits = IsgWorkspaceDashboard.Pair(first: 0, second: 0)
        var training = IsgWorkspaceDashboard.Pair(first: 0, second: 0)
        var deadlines = IsgWorkspaceDashboard.Pair(first: 0, second: 0)

        for company in assignedCompanies {
            let value = try await api.dashboard(selection: selection, companyID: company.id)
            nonconformities = add(nonconformities, value.nonconformities)
            visits = add(visits, value.visits)
            training = add(training, value.training)
            deadlines = add(deadlines, value.deadlines)
        }
        try requireCurrent(selection)
        return .init(workspaceID: selection.workspaceID, companyID: nil,
                     companies: .init(first: Int64(assignedCompanies.count), second: nil),
                     experts: nil, nonconformities: nonconformities, visits: visits,
                     training: training, deadlines: deadlines)
    }

    func aggregateExpertPersonnelMetrics() async throws -> IsgPersonnelMetrics {
        let selection = try expectedSelection()
        let assignedCompanies = companies
        var workplaces = IsgPersonnelMetrics.Counts(active: 0, archived: 0)
        var departments = IsgPersonnelMetrics.Counts(active: 0, archived: 0)
        var employees = IsgPersonnelMetrics.Counts(active: 0, archived: 0)
        var jobRoles = IsgPersonnelMetrics.Counts(active: 0, archived: 0)
        var contractors = IsgPersonnelMetrics.Counts(active: 0, archived: 0)
        var assignments = IsgPersonnelMetrics.AssignmentCounts(current: 0, historical: 0)

        for company in assignedCompanies {
            let value = try await api.personnelMetrics(selection: selection, companyID: company.id)
            workplaces = add(workplaces, value.workplaces)
            departments = add(departments, value.departments)
            employees = add(employees, value.employees)
            jobRoles = add(jobRoles, value.jobRoles)
            contractors = add(contractors, value.contractors)
            assignments = .init(current: assignments.current + value.assignments.current,
                                historical: assignments.historical + value.assignments.historical)
        }
        try requireCurrent(selection)
        return .init(workspaceID: selection.workspaceID, companyID: nil,
                     workplaces: workplaces, departments: departments, employees: employees,
                     jobRoles: jobRoles, contractors: contractors, assignments: assignments)
    }

    func domain(_ domain: IsgWorkspaceDomain, companyID: UUID? = nil,
                limit: Int = 100) async throws -> IsgWorkspaceDomainSnapshot {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let result = try await api.domain(selection: selection, companyID: companyID,
                                          domain: domain, limit: limit)
        try requireCurrent(selection)
        return result
    }

    func domainDetail(_ domain: IsgWorkspaceDomain, id: UUID,
                      companyID: UUID? = nil) async throws -> IsgWorkspaceDomainRecord {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let row = try await api.domainDetail(selection: selection, companyID: companyID,
                                             domain: domain, id: id)
        try requireCurrent(selection)
        return row
    }

    func checklistTemplates(companyID: UUID? = nil) async throws -> [IsgWorkspaceChecklistTemplate] {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let rows = try await api.checklistTemplates(selection: selection, companyID: companyID)
        try requireCurrent(selection)
        return rows
    }

    func equipmentCatalog(companyID: UUID? = nil) async throws -> IsgWorkspaceEquipmentCatalog {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let value = try await api.equipmentCatalog(selection: selection, companyID: companyID)
        try requireCurrent(selection)
        return value
    }

    func directory(_ kind: IsgWorkspaceDirectoryKind, companyID: UUID? = nil,
                   includeArchived: Bool = false) async throws -> [IsgWorkspaceDirectoryEntry] {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        return try await api.directory(selection: selection, companyID: companyID,
                                       kind: kind, includeArchived: includeArchived)
    }

    func employees(companyID: UUID? = nil, includeArchived: Bool = false) async throws
        -> [IsgWorkspaceEmployeeEntry] {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        return try await api.employees(selection: selection, companyID: companyID,
                                       includeArchived: includeArchived)
    }

    func personnelAdvanced(_ kind: IsgWorkspacePersonnelAdvancedKind,
                           companyID: UUID? = nil) async throws -> [IsgWorkspaceAdvancedRecord] {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let rows = try await api.personnelAdvanced(selection: selection, companyID: companyID, kind: kind)
        try requireCurrent(selection)
        return rows
    }

    func trainingAdvanced(_ kind: IsgWorkspaceTrainingAdvancedKind,
                          companyID: UUID? = nil) async throws -> [IsgWorkspaceAdvancedRecord] {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let rows = try await api.trainingAdvanced(selection: selection, companyID: companyID, kind: kind)
        try requireCurrent(selection)
        return rows
    }

    func mutatePersonnelAdvanced(mutationID: UUID, payload: [String: IsgWorkspaceRPCValue],
                                 companyID: UUID? = nil) async throws {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        try await api.mutatePersonnelAdvanced(selection: selection, mutationID: mutationID,
                                              companyID: companyID, payload: payload)
        try requireCurrent(selection)
        try await refreshDashboardAfterMutation(selection)
    }

    func mutateTrainingAdvanced(mutationID: UUID, payload: [String: IsgWorkspaceRPCValue],
                                companyID: UUID? = nil) async throws {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        try await api.mutateTrainingAdvanced(selection: selection, mutationID: mutationID,
                                             companyID: companyID, payload: payload)
        try requireCurrent(selection)
        try await refreshDashboardAfterMutation(selection)
    }

    func mutateDirectory(mutationID: UUID, kind: IsgWorkspaceDirectoryKind, action: String,
                         entryID: UUID?, expectedVersion: Int64, workplaceID: UUID?,
                         code: String?, name: String?, companyID: UUID? = nil) async throws {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        try await api.mutateDirectory(selection: selection, mutationID: mutationID, companyID: companyID,
                                      kind: kind, action: action, entryID: entryID,
                                      expectedVersion: expectedVersion, workplaceID: workplaceID,
                                      code: code, name: name)
        try requireCurrent(selection)
    }

    @discardableResult
    func mutateEmployee(mutationID: UUID, action: String, employeeID: UUID?,
                        expectedVersion: Int64, code: String?, name: String?, departmentID: UUID?,
                        hiredOn: String?, endsBefore: String?, companyID: UUID? = nil) async throws
        -> IsgWorkspaceEmployeeEntry? {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let result = try await api.mutateEmployee(selection: selection, mutationID: mutationID, companyID: companyID,
                                                  action: action, employeeID: employeeID,
                                                  expectedVersion: expectedVersion, code: code, name: name,
                                                  departmentID: departmentID, hiredOn: hiredOn, endsBefore: endsBefore)
        try requireCurrent(selection)
        return result
    }

    @discardableResult
    func mutateDomain(mutationID: UUID, domain: IsgWorkspaceDomain,
                      payload: [String: IsgWorkspaceRPCValue], companyID: UUID? = nil) async throws
        -> IsgWorkspaceMutationResult {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let result = try await api.mutateDomain(selection: selection, mutationID: mutationID,
                                                companyID: companyID, domain: domain, payload: payload)
        try requireCurrent(selection)
        try await refreshDashboardAfterMutation(selection)
        return result
    }

    @discardableResult
    func uploadFile(mutationID: UUID, title: String, filename: String,
                    category: String, data: Data, companyID: UUID? = nil) async throws
        -> IsgWorkspaceFileUploadResult {
        let selection = try expectedSelection(operate: true)
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let result = try await api.uploadFile(selection: selection, mutationID: mutationID,
                                              companyID: companyID, title: title,
                                              filename: filename, category: category, data: data)
        try requireCurrent(selection)
        try await refreshDashboardAfterMutation(selection)
        return result
    }

    /// Links an already-uploaded workspace file entry to the record created by
    /// the same form. The file remains a first-class archive entry while the
    /// parent module can surface it without asking the user to visit Files.
    @discardableResult
    func attachFile(mutationID: UUID, entryID: UUID, parentKind: String,
                    parentID: UUID, fieldName: String,
                    companyID: UUID? = nil) async throws -> IsgWorkspaceMutationResult {
        try await mutateDomain(mutationID: mutationID, domain: .files, payload: [
            "action": .string("attach"), "entry_id": .id(entryID),
            "parent_kind": .string(parentKind), "parent_id": .id(parentID),
            "field_name": .string(fieldName)
        ], companyID: companyID)
    }

    func downloadFile(_ row: IsgWorkspaceDomainRecord, companyID: UUID? = nil) async throws
        -> IsgWorkspaceFileDownload {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let result = try await api.downloadFile(selection: selection, companyID: companyID, row: row)
        try requireCurrent(selection)
        return result
    }

    func archiveFile(_ row: IsgWorkspaceDomainRecord, mutationID: UUID, companyID: UUID? = nil) async throws {
        guard let version = row.version else { throw IsgWorkspaceAPIFailure.invalidRequest }
        _ = try await mutateDomain(mutationID: mutationID, domain: .files, payload: [
            "action": .string("archive"), "entry_id": .id(row.id),
            "expected_version": .number(Int(version))
        ], companyID: companyID)
    }

    func search(companyID: UUID, query: String, afterKind: String? = nil,
                afterID: UUID? = nil, limit: Int = 30) async throws -> IsgWorkspaceSearchPage {
        let selection = try expectedSelection()
        return try await api.search(selection: selection, companyID: companyID, query: query,
                                    afterKind: afterKind, afterID: afterID, limit: limit)
    }

    func analyses(companyID: UUID? = nil, offset: Int = 0,
                  limit: Int = 30) async throws -> IsgWorkspaceAnalysisPage {
        let selection = try expectedSelection()
        guard let companyID = companyID ?? selectedCompanyID else { throw IsgWorkspaceAPIFailure.invalidRequest }
        let page = try await api.analyses(selection: selection, companyID: companyID,
                                          offset: offset, limit: limit)
        try requireCurrent(selection)
        return page
    }

    func analysis(companyID: UUID, analysisID: UUID) async throws -> IsgWorkspaceAnalysisResult {
        let selection = try expectedSelection()
        return try await api.analysis(selection: selection, companyID: companyID, analysisID: analysisID)
    }

    func downloadAsset(_ assetID: UUID, filename: String) async throws -> Data {
        let selection = try expectedSelection()
        let result = try await api.downloadAsset(selection: selection, assetID: assetID, filename: filename)
        try requireCurrent(selection)
        return result.data
    }

    func submitPhotoAnalysis(mutationID: UUID, companyID: UUID,
                             assetID: UUID) async throws -> IsgWorkspacePhotoAnalysisJob {
        let selection = try expectedSelection(operate: true)
        let job = try await api.submitPhotoAnalysis(selection: selection, mutationID: mutationID,
                                                     companyID: companyID, assetID: assetID)
        try requireCurrent(selection)
        return job
    }

    func photoAnalysisJob(companyID: UUID, jobID: UUID) async throws -> IsgWorkspacePhotoAnalysisJob {
        let selection = try expectedSelection()
        let job = try await api.photoAnalysisJob(selection: selection, companyID: companyID, jobID: jobID)
        try requireCurrent(selection)
        return job
    }

    func fileAnalysisItem(mutationID: UUID, companyID: UUID, workplaceID: UUID?,
                          sourceScope: String, analysisID: UUID, itemKind: String, itemID: UUID,
                          severity: String?, openedOn: String, dueOn: String?) async throws
        -> (result: IsgWorkspaceFilingResult, successMessage: String) {
        let selection = try expectedSelection(operate: true)
        let result = try await api.fileAnalysisItem(selection: selection, mutationID: mutationID,
            companyID: companyID, workplaceID: workplaceID, sourceScope: sourceScope,
            analysisID: analysisID, itemKind: itemKind, itemID: itemID, severity: severity,
            openedOn: openedOn, dueOn: dueOn)
        return (result, NovaSuccessMessage.serverKey(result.successMessageKey))
    }

    func createExport(mutationID: UUID, companyID: UUID, analysisID: UUID,
                      format: String, findingIDs: [UUID], expertItemIDs: [UUID],
                      trainingItemIDs: [UUID]) async throws -> IsgWorkspaceExportResult {
        let selection = try expectedSelection(operate: true)
        return try await api.createExport(selection: selection, mutationID: mutationID,
            companyID: companyID, analysisID: analysisID, format: format,
            findingIDs: findingIDs, expertItemIDs: expertItemIDs, trainingItemIDs: trainingItemIDs)
    }

    func export(companyID: UUID, jobID: UUID) async throws -> IsgWorkspaceExportResult {
        let selection = try expectedSelection()
        return try await api.export(selection: selection, companyID: companyID, jobID: jobID)
    }

    func changes(companyID: UUID? = nil, after: Int64 = 0,
                 limit: Int = 100) async throws -> IsgWorkspaceChangePage {
        let selection = try expectedSelection()
        return try await api.changes(selection: selection, companyID: companyID ?? selectedCompanyID,
                                     after: after, limit: limit)
    }

    private func load(identity expected: NovaSessionIdentity, preferredWorkspaceID: UUID?, token: UUID) async {
        do {
            let values = try await api.list(identity: expected)
            guard isCurrent(token, identity: expected) else { return }
            contexts = values
            if let preferredWorkspaceID,
               let previous = values.first(where: { $0.workspaceID == preferredWorkspaceID }) {
                select(previous)
            } else if values.count == 1, let only = values.first {
                select(only)
            } else {
                selection = nil; phase = .choosing; request = nil
            }
        } catch {
            guard isCurrent(token, identity: expected) else { return }
            phase = .failed; request = nil
        }
    }

    private func resolve(context expected: IsgWorkspaceContext, token: UUID) async {
        do {
            let current = try expectedIdentity()
            let confirmed = try await api.context(identity: current, workspaceID: expected.workspaceID)
            guard isCurrent(token, identity: current), selection?.workspaceID == expected.workspaceID,
                  confirmed.membership.userID == current.userID, confirmed.canRead else { return }
            selection = confirmed.selection
            var loadedCompanies: [IsgWorkspaceCompany] = []
            var cursor: UUID?
            while true {
                let page = try await api.companies(selection: confirmed.selection, after: cursor, limit: 100)
                guard isCurrent(token, identity: current) else { return }
                loadedCompanies.append(contentsOf: page)
                if page.count < 100 { break }
                cursor = page.last?.id
            }
            guard isCurrent(token, identity: current), confirmed.selection == selection else { return }
            let retainedCompany = selectedCompanyID.flatMap { selectedID in
                loadedCompanies.contains(where: { $0.id == selectedID }) ? selectedID : nil
            }
            // A single-company workspace should open ready for work for every
            // role. Previously owners/admins always landed with a nil company,
            // which disabled every operational module even though the company
            // was visible on screen.
            let dashboardCompany: UUID?
            if confirmed.membership.role == "expert" {
                dashboardCompany = retainedCompany ?? loadedCompanies.first?.id
            } else {
                dashboardCompany = retainedCompany ?? (loadedCompanies.count == 1 ? loadedCompanies.first?.id : nil)
            }
            let loadedDashboard: IsgWorkspaceDashboard?
            if dashboardCompany == nil && confirmed.membership.role == "expert" {
                loadedDashboard = nil
            } else {
                loadedDashboard = try await api.dashboard(selection: confirmed.selection, companyID: dashboardCompany)
            }
            guard isCurrent(token, identity: current), selection == confirmed.selection else { return }
            contexts = contexts.map { $0.workspaceID == confirmed.workspaceID ? confirmed : $0 }
            companies = loadedCompanies; selectedCompanyID = dashboardCompany
            dashboard = loadedDashboard; phase = .ready; request = nil
        } catch {
            guard token == generation else { return }
            invalidateContent(); selection = nil; phase = .failed; request = nil
        }
    }

    private func loadDashboard(identity expectedIdentity: NovaSessionIdentity,
                               selection expectedSelection: NovaWorkspaceSelection,
                               companyID: UUID?, token: UUID) async {
        do {
            let value = try await api.dashboard(selection: expectedSelection, companyID: companyID)
            guard isCurrent(token, identity: expectedIdentity), selection == expectedSelection,
                  selectedCompanyID == companyID else { return }
            dashboard = value; phase = .ready; request = nil
        } catch {
            guard token == generation else { return }
            dashboard = nil; phase = .failed; request = nil
        }
    }

    /// A committed mutation remains successful if only the summary fails. Never
    /// publish its late summary (including nil) into a newer session or company.
    private func refreshDashboardAfterMutation(_ expected: NovaWorkspaceSelection) async throws {
        let token = generation
        let companyID = selectedCompanyID
        let value = try? await api.dashboard(selection: expected, companyID: companyID)
        guard token == generation, selectedCompanyID == companyID else {
            throw IsgWorkspaceAPIFailure.staleSession
        }
        try requireCurrent(expected)
        dashboard = value
    }

    private func expectedIdentity() throws -> NovaSessionIdentity {
        guard let identity else { throw IsgWorkspaceAPIFailure.staleSession }
        return identity
    }

    private func expectedSelection(operate: Bool = false) throws -> NovaWorkspaceSelection {
        guard phase == .ready, let selection, selection.canRead, !operate || selection.canOperate else {
            throw IsgWorkspaceAPIFailure.staleSession
        }
        return selection
    }

    private func requireCurrent(_ expected: NovaWorkspaceSelection) throws {
        guard selection == expected, phase == .ready else { throw IsgWorkspaceAPIFailure.staleSession }
    }

    private func add(_ lhs: IsgWorkspaceDashboard.Pair,
                     _ rhs: IsgWorkspaceDashboard.Pair) -> IsgWorkspaceDashboard.Pair {
        .init(first: (lhs.first ?? 0) + (rhs.first ?? 0),
              second: (lhs.second ?? 0) + (rhs.second ?? 0))
    }

    private func add(_ lhs: IsgPersonnelMetrics.Counts,
                     _ rhs: IsgPersonnelMetrics.Counts) -> IsgPersonnelMetrics.Counts {
        .init(active: lhs.active + rhs.active, archived: lhs.archived + rhs.archived)
    }

    private func isCurrent(_ token: UUID, identity expected: NovaSessionIdentity) -> Bool {
        token == generation && identity == expected
    }

    private func invalidate() {
        generation = UUID(); request?.cancel(); request = nil
        contexts = []; selection = nil; invalidateContent()
    }

    private func invalidateContent() {
        generation = UUID(); request?.cancel(); request = nil
        selectedCompanyID = nil; dashboard = nil; companies = []
    }
}
