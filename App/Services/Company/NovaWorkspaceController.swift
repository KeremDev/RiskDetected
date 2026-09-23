import Foundation
import Supabase

/// Owned by the management presentation, not by any individual form. No user metadata grants access.
@MainActor final class NovaWorkspaceController: ObservableObject {
    @Published private(set) var host = NovaSessionHost(implemented: [.companies])
    @Published private(set) var selectedCompanyID: UUID?
    @Published private(set) var capability: Capability?
    @Published private(set) var resolving = true
    private var request: Task<Void, Never>?
    private let sdk = SupabaseService.shared.client
    private var observing = false
    private weak var workspaceStore: IsgWorkspaceStore?
    private var transportTicket: NovaExpertTransport.Ticket?
    init(workspaceStore: IsgWorkspaceStore? = nil) {
        self.workspaceStore = workspaceStore
    }
    typealias Capability = NovaWorkspaceCapability
    var isAvailable: Bool { capability?.can_read == true && host.phase == .ready }
    var canWrite: Bool { scope != nil && capability?.can_write == true }
    /// Personnel has its own pilot grant. The general workspace capability
    /// still reflects paid access for the other company modules.
    var canWritePersonnel: Bool {
        scope != nil && capability?.can_read == true && capability?.is_archived != true
    }
    var scope: NovaPersonnelScope? {
        guard isAvailable, let identity = host.identity, let company = selectedCompanyID, capability?.company_id == company else { return nil }
        return .init(ownerID: identity.userID, sessionID: identity.sessionID, companyID: company, epoch: host.navigation.epoch)
    }
    lazy var personnel = NovaPersonnelService.live(currentScope: { [weak self] in self?.scope }).client
    lazy var directory = NovaDirectoryService(sdk: sdk, isCurrent: { [weak self] in self?.scope == $0 }, storage: KeychainPersonnelPendingStorage()).client
    var personnelClient: NovaPersonnelClient {
        let client = personnel
        return .init(employees: client.employees, departments: client.departments, detail: client.detail, save: { [weak self] intent in
            guard let self, self.scope == intent.scope, self.canWritePersonnel else { throw NovaPersonnelFailure.denied }
            return try await client.save(intent)
        }, pending: client.pending)
    }
    var directoryClient: NovaDirectoryClient {
        let client = directory
        return .init(read: client.read, save: { [weak self] intent in
            guard let self, self.scope == intent.scope, self.canWrite else { throw NovaPersonnelFailure.denied }
            return try await client.save(intent)
        }, pending: client.pending)
    }
    private func identity() -> NovaSessionIdentity? {
        guard let session = sdk.auth.currentSession, let id = NovaPersonnelService.sessionID(session.accessToken) else { return nil }
        return .init(userID: session.user.id, sessionID: id)
    }
    func observe() async {
        guard !observing else { return }; observing = true
        guard let identity = identity() else { resolving = false; observing = false; return }
        transportTicket = NovaExpertTransport.shared.bind(identity: identity,
            workspace: workspaceStore?.selection,
            store: workspaceStore,
            currentWorkspace: { [weak workspaceStore] in workspaceStore?.selection })
        adopt()
        defer { stop() }
        for await _ in sdk.auth.authStateChanges {
            guard !Task.isCancelled else { return }
            adopt()
        }
    }
    private func adopt() {
        let next = identity()
        guard host.identity != next || (capability == nil && request == nil) else { return }
        request?.cancel(); request = nil; capability = nil; selectedCompanyID = nil
        host.adopt(next)
        if next == nil { resolving = false } else { refresh() }
    }
    func select(_ company: UUID?) { selectedCompanyID = company; refresh() }
    func refresh() {
        request?.cancel(); capability = nil
        guard identity() == host.identity, let ticket = host.beginAvailabilityRefresh(), let expectedIdentity = host.identity else { resolving = false; return }
        resolving = true
        let company = selectedCompanyID
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await NovaExpertTransport.shared.execute("isg_workspace_availability_v1",
                    params: ["p_company": PersonnelRPCValue.id(company)], ticket: transportTicket)
                try Task.checkCancellation()
                guard identity() == expectedIdentity, selectedCompanyID == company, data.count <= 16384 else { throw NovaPersonnelFailure.denied }
                let value = try Capability.decode(data, owner: expectedIdentity.userID, company: company)
                guard host.resolve(ticket, ownerID: value.owner_id, enabled: value.can_read ? [.companies] : []) else { return }
                capability = value; resolving = false; request = nil
            } catch {
                if !Task.isCancelled && host.fail(ticket) { capability = nil; resolving = false; request = nil }
            }
        }
    }
    func stop() {
        if let transportTicket { NovaExpertTransport.shared.release(transportTicket) }
        transportTicket = nil
        request?.cancel(); request = nil; capability = nil; selectedCompanyID = nil
        host.adopt(nil); observing = false; resolving = false
    }
}
