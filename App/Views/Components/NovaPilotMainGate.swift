import SwiftUI
import PhotosUI
import UIKit

/// Private device build only. This UUID is a presentation selector, NOT authority.
/// Ordinary Debug/Release builds execute exactly the existing MainTabView route.
struct NovaPilotMainGate: View {
    @ObservedObject var auth: AuthService
    @State private var previewIdentity = NovaSessionIdentity(userID: UUID(), sessionID: UUID())

    var body: some View {
        #if DEBUG && NOVA_PILOT_BUILD
        if let session = auth.session,
           Self.canOpenNovaPilot(userID: session.user.id),
           let sessionID = NovaPersonnelService.sessionID(session.accessToken) {
            NovaIntegratedWorkspaceGate(identity: .init(userID: session.user.id, sessionID: sessionID))
                .id("\(session.user.id):\(sessionID)")
        } else {
            #if targetEnvironment(simulator)
            if CommandLine.arguments.contains("RD_UI_TEST_NOVA_REVIEW") {
                NovaPilotReviewHarness()
            } else if CommandLine.arguments.contains("RD_UI_TEST_NOVA_PILOT") {
                NovaPilotRoot(identity: previewIdentity, previewOnly: true)
            } else { MainTabView() }
            #else
            MainTabView()
            #endif
        }
        #else
        MainTabView()
        #endif
    }

    /// The dedicated OSGB pilot app is isolated by bundle identifier, build
    /// condition and staging backend. Its authenticated managers and experts
    /// share Nova; workspace RPCs remain the tenant-data authority.
    private static func canOpenNovaPilot(userID: UUID) -> Bool {
        if Bundle.main.bundleIdentifier == "com.riskdetected.app.osgbpilot" {
            return true
        }
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "NOVAPilotOwnerID") as? String else {
            return false
        }
        return UUID(uuidString: configured) == userID
    }
}

/// Adds the multi-workspace entry point without replacing the proven personal
/// experience. If the additive OSGB RPCs are not deployed, the personal root
/// remains the only visible path.
struct NovaIntegratedWorkspaceGate: View {
    let identity: NovaSessionIdentity
    @StateObject private var store = IsgWorkspaceStore()
    @State private var choosing = false

    var body: some View {
        Group {
            if store.selection == nil && (store.phase == .signedOut || store.phase == .loading) {
                NovaPageSurface {
                    NovaLoadingView(message: "Çalışma alanı yükleniyor…")
                }
            } else if choosing || store.phase == .choosing || (store.phase == .failed && !store.contexts.isEmpty) {
                IsgWorkspaceChooser(identity: identity, store: store, canCancel: store.selection != nil) { choosing = false }
            } else if store.selection?.kind == "osgb" {
                if selectedContext?.membership.role == "expert" {
                    // Keep the normal expert root mounted while a company-
                    // scoped dashboard is loading. Removing this view during
                    // `selectCompany` resets navigation and makes a company
                    // row look as if it returned to the home page.
                    NovaPilotRoot(identity: identity,
                        workspaceLabel: selectedContext?.name,
                        onWorkspaceSwitch: { choosing = true },
                        workspaceStore: store)
                        .id("expert:\(identity.userID):\(selectedContext?.workspaceID.uuidString ?? "none"):\(store.selection?.permissionRevision ?? 0):\(store.selection?.workspaceVersion ?? 0)")
                } else if store.phase == .ready || !store.companies.isEmpty {
                    IsgOSGBWorkspaceRoot(identity: identity, store: store) { choosing = true }
                } else {
                    NovaPageSurface {
                        NovaLoadingView(message: RDLocalization.string("localizable.nova.workspace.loading", table: .localizable,
                            fallback: "Çalışma alanı yükleniyor…"))
                    }
                }
            } else {
                NovaPilotRoot(identity: identity,
                    workspaceLabel: !store.contexts.isEmpty ? selectedContext?.name : nil,
                    onWorkspaceSwitch: !store.contexts.isEmpty ? { choosing = true } : nil)
            }
        }
        .task(id: identity) { store.adopt(identity) }
    }

    private var selectedContext: IsgWorkspaceContext? {
        guard let id = store.selection?.workspaceID else { return nil }
        return store.contexts.first { $0.workspaceID == id }
    }
}

private struct IsgWorkspaceChooser: View {
    let identity: NovaSessionIdentity
    @ObservedObject var store: IsgWorkspaceStore
    let canCancel: Bool
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var accessRoute: IsgWorkspaceAccessRoute?

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        if canCancel { NovaBackButton { onClose() } }
                        NovaText(text: RDLocalization.string("localizable.nova.workspace.choose.title", table: .localizable,
                            fallback: "Çalışma Alanı"), style: .screenTitle)
                        Spacer(minLength: 0)
                        Button { store.refresh() } label: {
                            Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                        }.buttonStyle(NovaRowPressStyle())
                            .accessibilityLabel(RDLocalization.string("localizable.nova.workspace.refresh", table: .localizable,
                                fallback: "Çalışma alanlarını yenile"))
                    }
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.choose.hint", table: .localizable,
                        fallback: "Yetkili olduğunuz çalışma alanını seçin."))
                    HStack(spacing: 8) {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.create", table: .localizable,
                            fallback: "OSGB oluştur"), symbol: "building.2.crop.circle", prominent: true) {
                            accessRoute = .create
                        }
                        NovaCompactActionButton(title: RDLocalization.string("localizable.nova.workspace.invitation.accept", table: .localizable,
                            fallback: "Davete katıl"), symbol: "envelope.open") {
                            accessRoute = .accept
                        }
                    }
                    if store.phase == .failed {
                        NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.load.failed", table: .localizable,
                                fallback: "Çalışma alanları yüklenemedi"),
                            message: RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                fallback: "Bağlantınızı kontrol edip yeniden deneyin."))
                    }
                    // Personal records stay as the default backend scope, but
                    // are not presented as a separate workspace card.
                    ForEach(store.contexts.filter { $0.kind == "osgb" }, id: \.workspaceID) { context in
                        Button {
                            store.select(context)
                            onClose()
                        } label: {
                            NovaCard(padding: 14) {
                                HStack(spacing: 12) {
                                    NovaIcon(symbol: context.kind == "osgb" ? "building.2" : "person", size: 22)
                                        .foregroundStyle(Color.black)
                                        .frame(width: 44, height: 44)
                                        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 13))
                                    VStack(alignment: .leading, spacing: 3) {
                                        NovaText(text: context.name, style: .cardTitle)
                                        NovaText(text: role(context.membership.role), style: .metaQuiet)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                }.frame(maxWidth: .infinity, minHeight: 52)
                            }
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }.padding(18)
            }
        }
        .preferredColorScheme(.light)
        .novaPopupCover(item: $accessRoute) { route in
            NovaPopup {
                IsgWorkspaceAccessEditor(mode: route.mode) { value in
                    switch route.mode {
                    case .create:
                        _ = try await store.createWorkspace(mutationID: route.mutationID, name: value)
                    case .accept:
                        _ = try await store.acceptInvitation(mutationID: route.mutationID, token: value)
                    }
                    accessRoute = nil
                    onClose()
                }
            }
        }
        .modifier(NovaSuccessPresentation(account: identity.userID))
    }

    private func role(_ value: String) -> String {
        switch value {
        case "owner": return RDLocalization.string("localizable.nova.workspace.role.owner", table: .localizable, fallback: "OSGB sahibi")
        case "admin": return RDLocalization.string("localizable.nova.workspace.role.admin", table: .localizable, fallback: "OSGB yöneticisi")
        default: return RDLocalization.string("localizable.nova.workspace.role.expert", table: .localizable, fallback: "İSG uzmanı")
        }
    }
}

private struct IsgWorkspaceAccessRoute: Identifiable {
    enum Mode { case create, accept }
    let id = UUID()
    let mutationID = UUID()
    let mode: Mode
    static var create: Self { .init(mode: .create) }
    static var accept: Self { .init(mode: .accept) }
}

private struct IsgWorkspaceAccessEditor: View {
    let mode: IsgWorkspaceAccessRoute.Mode
    let onSave: (String) async throws -> Void
    @State private var value = ""
    @State private var saving = false
    @State private var error: String?
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaText(text: mode == .create
                ? RDLocalization.string("localizable.nova.workspace.create.title", table: .localizable, fallback: "OSGB çalışma alanı oluştur")
                : RDLocalization.string("localizable.nova.workspace.invitation.accept.title", table: .localizable, fallback: "OSGB davetini kabul et"),
                style: .sectionTitle)
            NovaHelpHint(text: mode == .create
                ? RDLocalization.string("localizable.nova.workspace.create.hint", table: .localizable, fallback: "Firmalarınızı ve uzman ekibinizi kişisel kayıtlardan ayrı yönetin.")
                : RDLocalization.string("localizable.nova.workspace.invitation.accept.hint", table: .localizable, fallback: "Size iletilen 64 karakterli davet kodunu girin."))
            NovaCard(padding: 14) {
                TextField(mode == .create
                    ? RDLocalization.string("localizable.nova.workspace.name", table: .localizable, fallback: "OSGB adı")
                    : RDLocalization.string("localizable.nova.workspace.invitation.code", table: .localizable, fallback: "Davet kodu"),
                    text: $value, axis: mode == .accept ? .vertical : .horizontal)
                    .font(NovaFont.font(.body))
                    .textInputAutocapitalization(mode == .accept ? .never : .words)
                    .autocorrectionDisabled(mode == .accept)
            }
            if let error { NovaHelpHint(text: error) }
            NovaButton(label: saving
                ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…")
                : RDLocalization.string("localizable.nova.personnel.save", table: .localizable, fallback: "Kaydet"),
                symbol: saving ? "hourglass" : "checkmark", isEnabled: valid && !saving) { save() }
        }.padding(18).novaPopupContentSize()
    }

    private var clean: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool { mode == .create ? !clean.isEmpty : clean.count == 64 }
    private func save() {
        saving = true; error = nil
        Task {
            do {
                try await onSave(clean)
                celebrate(mode == .create
                    ? RDLocalization.string("localizable.nova.workspace.created", table: .localizable, fallback: "OSGB çalışma alanı oluşturuldu.")
                    : RDLocalization.string("localizable.nova.workspace.invitation.accepted", table: .localizable, fallback: "OSGB daveti kabul edildi."))
            } catch {
                self.error = RDLocalization.string("localizable.nova.workspace.save.failed", table: .localizable,
                    fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
                saving = false
            }
        }
    }
}

private struct IsgOSGBWorkspaceRoot: View {
    let identity: NovaSessionIdentity
    @ObservedObject var store: IsgWorkspaceStore
    let onSwitchWorkspace: () -> Void
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.novaCelebrate) private var celebrate
    @State private var navigation = NovaNavigationState(epoch: UUID().uuidString,
        // Keep the shared route catalog available to the shell. Company
        // creation is still capability-gated by the manager callback, while
        // experts receive the same operational menu without that action.
        available: NovaWorkspaceRole.osgbManager.destinations)
    @State private var editor: IsgCompanyEditorRoute?
    @State private var personnel: IsgPersonnelMetrics?
    @State private var query = ""
    @State private var searchRows: [IsgWorkspaceSearchRow]?
    @State private var searchError: String?
    @State private var searching = false
    @State private var showingSearch = false
    @State private var showingMembers = false
    @State private var showingAssignments = false
    @State private var dashboardDomain: IsgWorkspaceDomain?
    @State private var companyWorkspaceID: UUID?
    @State private var companyWorkspaceDomain: IsgWorkspaceDomain?
    @State private var companyWorkspaceAnalyses = false
    @State private var companyPersonnel: IsgPersonnelMetrics?
    @State private var companyDomainSnapshots: [String: IsgWorkspaceDomainSnapshot] = [:]
    @State private var companyOverviewLoading = false
    @State private var companyOverviewError: String?
    @State private var companyLogo: UIImage?
    @State private var companyLogoEntryID: UUID?
    @State private var companyLogoPicker: PhotosPickerItem?
    @State private var companyLogoSaving = false
    @State private var companyLogoError: String?
    @State private var companyLogoUploadAttempt = IsgWorkspaceMutationAttempt()
    @State private var companyLogoLinkAttempt = IsgWorkspaceMutationAttempt()
    @State private var expertDashboard: IsgWorkspaceDashboard?
    @State private var recentAnalyses: [NovaAnalysisSummary] = []
    @State private var profileAvatarImage: Image?
    /// A company can be created successfully even if a following assignment
    /// request loses its response. Keep the same receipt IDs and start instant
    /// across a retry so the server replays instead of duplicating the access.
    @State private var companyAssignmentMutationIDs: [String: UUID] = [:]
    @State private var companyAssignmentStarts: [String: String] = [:]

    private var context: IsgWorkspaceContext? {
        guard let id = store.selection?.workspaceID else { return nil }
        return store.contexts.first { $0.workspaceID == id }
    }
    private var selectedCompany: IsgWorkspaceCompany? {
        store.companies.first { $0.id == store.selectedCompanyID }
    }
    private var canManageCompanies: Bool {
        guard let context else { return false }
        return context.canOperate && ["owner", "admin"].contains(context.membership.role)
    }
    private var canManageCompanyLogo: Bool { context?.canOperate == true }
    private var isExpert: Bool { context?.membership.role == "expert" }
    private var companyWorkspace: IsgWorkspaceCompany? {
        guard let companyWorkspaceID else { return nil }
        return store.companies.first { $0.id == companyWorkspaceID }
    }
    private var summaryTaskKey: String {
        let companyIDs = store.companies.map(\.id.uuidString).joined(separator: ",")
        return "\(context?.workspaceID.uuidString ?? "none"):\(context?.membership.role ?? "none"):\(store.phase):\(store.selectedCompanyID?.uuidString ?? "none"):\(companyIDs)"
    }
    private var companyTaskKey: String {
        "\(companyWorkspaceID?.uuidString ?? "none"):\(store.selectedCompanyID?.uuidString ?? "none"):\(store.phase)"
    }
    private var menuBoard: IsgWorkspaceDashboard? { isExpert ? expertDashboard : store.dashboard }
    private var menuProgressCompleted: Int {
        guard !store.companies.isEmpty else { return 0 }
        var completed = 1 // firma bilgileri
        if (menuBoard?.nonconformities.first ?? 0) > 0 { completed += 1 }
        if (personnel?.employees.active ?? 0) > 0 { completed += 1 }
        if (menuBoard?.training.second ?? 0) > 0 { completed += 1 }
        if (menuBoard?.visits.first ?? 0) > 0 { completed += 1 }
        return min(completed, 8)
    }
    private var menuStats: [NovaMenuStat] {
        let board = menuBoard
        return [
            .init(id: "upcoming", title: "Yaklaşan İşler",
                  value: board.map { String(($0.deadlines.first ?? 0) + ($0.deadlines.second ?? 0)) } ?? "—",
                  symbol: "calendar.badge.clock", destination: .periodicChecks),
            .init(id: "overdue", title: "Süresi biten",
                  value: board?.nonconformities.second.map(String.init) ?? "—",
                  symbol: "exclamationmark.triangle", destination: .findings),
            .init(id: "analyses", title: "Analiz",
                  value: board?.nonconformities.first.map(String.init) ?? "—",
                  symbol: "photo.on.rectangle.angled", destination: .analyses)
        ]
    }
    private var menuNextAction: NovaMenuNextAction? {
        if store.companies.isEmpty {
            return .init(title: "Firma ekle", symbol: "building.2.crop.circle",
                destination: canManageCompanies ? .newCompany : .companies, completed: 0, total: 1)
        }
        let analysisCount = Int(menuBoard?.nonconformities.first ?? 0)
        if analysisCount == 0 {
            return .init(title: "Fotoğraf analiz et", symbol: "camera", destination: .newAnalysis,
                completed: 0, total: 8)
        }
        return .init(title: "Risk analizi ekle", symbol: "shield.lefthalf.filled", destination: .riskAssessments,
            completed: menuProgressCompleted, total: 8)
    }
    private struct CompanyNextAction: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let status: NovaStatus
        let domain: IsgWorkspaceDomain
    }

    var body: some View {
        NovaExpertShell(navigation: $navigation, userName: app.profile?.fullName ?? "",
            profileAvatar: profileAvatarImage,
            menuRoleTitle: canManageCompanies ? "OSGB Yetkilisi" : "İSG Uzmanı",
            menuStats: menuStats, menuNextAction: menuNextAction,
            onInvite: { app.requestProfileDestination(.referral); navigate(.profile) },
            connectionLabel: context.map { "\($0.name) · \(role($0.membership.role))" } ?? "",
            onCompanyCreate: canManageCompanies ? { editor = .create } : nil,
            isManager: canManageCompanies,
            onExpertCreate: canManageCompanies ? { showingMembers = true } : nil,
            onAssignmentOpen: canManageCompanies ? { openAssignments() } : nil,
            onDestination: { destination in
                if destination == .companies {
                    companyWorkspaceID = nil
                    companyWorkspaceDomain = nil
                    companyWorkspaceAnalyses = false
                }
            },
            onLogout: { app.signOut() }) { destination in
            switch destination {
            case .home: dashboard
            case .activity: ExpertActivityDestination(onClose: { navigate(.home) })
            case .notebook, .newNote: NotebookDestination(onClose: { navigate(.home) })
            case .statistics: statistics
            case .companies: companies
            case .reports: reportCenter
            case .reportArchive: NovaProcessArchive(identity: identity, onBack: { navigate(.reports) })
            case .findings: domain(.nonconformity)
            case .newFinding: domain(.nonconformity, startInAddMode: true)
            case .analyses: analyses()
            case .newAnalysis: analyses(startInCreateMode: true)
            case .training: domain(.training)
            case .newTraining: domain(.training, startInAddMode: true)
            case .riskAssessments: domain(.risk)
            case .checklists: domain(.checklist)
            case .emergencyPlans: domain(.emergencyPlan)
            case .drills: domain(.drill)
            case .ppeHandovers: domain(.ppe)
            case .appointments: domain(.appointment)
            case .katipContracts: domain(.katip)
            case .annualWorkPlans: domain(.annualPlan)
            case .boardMeetings: domain(.board)
            case .visits: domain(.visit)
            case .workPermits: domain(.workPermit)
            case .periodicChecks: domain(.equipment)
            case .documentChecklist, .documents: domain(.files)
            case .newDocument: domain(.files, startInAddMode: true)
            case .newVisit: domain(.visit, startInAddMode: true)
            case .newCompany: companies
            case .contractors: personnelScreen(initialSection: .contractor)
            case .memory: changes
            case .notifications: changes
            case .profile:
                NovaPageSurface(onEdgeBack: { navigate(.home) }) {
                    VStack(spacing: 0) {
                        NovaPageHeading(title: RDLocalization.string("localizable.nova.navigation.profile", table: .localizable,
                            fallback: "Profil"), onBack: { navigate(.home) }).padding(.horizontal, 20)
                        ProfileView()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .task(id: summaryTaskKey) {
            guard store.phase == .ready else { return }
            if isExpert {
                async let dashboardValue = store.aggregateExpertDashboard()
                async let personnelValue = store.aggregateExpertPersonnelMetrics()
                expertDashboard = try? await dashboardValue
                personnel = try? await personnelValue
            } else {
                expertDashboard = nil
                personnel = try? await store.personnelMetrics()
            }
            query = ""; searchRows = nil; searchError = nil
        }
        .task(id: "\(summaryTaskKey):recent-analyses") {
            guard store.phase == .ready else { recentAnalyses = []; return }
            do {
                recentAnalyses = try await NovaAnalysisWorkspace.summaries(
                    identity: identity, method: .fineKinney, limit: 6).rows
            } catch {
                recentAnalyses = []
            }
        }
        .task(id: app.profile?.avatarURL) { await loadProfileAvatarImage() }
        .task(id: companyTaskKey) {
            guard let companyWorkspaceID, store.phase == .ready,
                  store.selectedCompanyID == companyWorkspaceID else { return }
            await loadCompanyOverview(companyWorkspaceID)
        }
        .onChange(of: companyLogoPicker) { item in
            guard let item else { return }
            Task { await saveCompanyLogo(item) }
        }
        .novaFullScreenCover(item: $editor) { route in
            IsgWorkspaceCompanyEditor(company: route.company, store: store,
                    onClose: { editor = nil },
                    onSave: { mutationID, profileMutationID, draft, selectedExpertIDs, assignmentRole in
                        if let company = route.company {
                            _ = try await store.updateCompany(mutationID: mutationID,
                                profileMutationID: profileMutationID, companyID: company.id,
                                expectedVersion: company.version,
                                expectedProfileVersion: company.profileVersion ?? 0, draft: draft)
                        } else {
                            let created = try await store.createCompany(mutationID: mutationID,
                                profileMutationID: profileMutationID, draft: draft)
                            let starts = companyAssignmentStarts[created.id.uuidString]
                                ?? ISO8601DateFormatter().string(from: Date())
                            companyAssignmentStarts[created.id.uuidString] = starts
                            for membershipID in selectedExpertIDs {
                                let key = "(created.id.uuidString):(membershipID.uuidString):(assignmentRole)"
                                let assignmentMutationID: UUID
                                if let existing = companyAssignmentMutationIDs[key] {
                                    assignmentMutationID = existing
                                } else {
                                    assignmentMutationID = UUID()
                                    companyAssignmentMutationIDs[key] = assignmentMutationID
                                }
                                _ = try await store.mutateAssignment(mutationID: assignmentMutationID,
                                    companyID: created.id, action: "create", membershipID: membershipID,
                                    role: assignmentRole, startsAt: starts,
                                    reason: "Firma ekleme sırasında hızlı atama")
                            }
                        }
                    },
                    onArchive: route.company.map { company in
                        { reason in
                            try await store.archiveCompany(mutationID: route.archiveMutationID, companyID: company.id,
                                expectedVersion: company.version, reason: reason)
                            editor = nil
                        }
                    })
        }
        .novaPopupCover(isPresented: $showingMembers) {
            NovaPopup { IsgWorkspaceMemberManagement(store: store, onOpenRecord: { detail, _ in
                guard let company = detail.link_company_id else { return }
                showingMembers = false
                companyWorkspaceID = company
                store.selectCompany(company)
                navigate(.companies)
            }) }
        }
        .novaPopupCover(isPresented: $showingAssignments) {
            if let company = selectedCompany {
                NovaPopup { IsgWorkspaceAssignmentManagement(store: store, company: company) }
            }
        }
        .modifier(NovaSuccessPresentation(account: identity.userID))
    }

    private func loadProfileAvatarImage() async {
        guard let path = app.profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            profileAvatarImage = nil
            return
        }
        do {
            if let image = try await app.auth.profileAvatarImage(path: path) {
                profileAvatarImage = Image(uiImage: image)
            } else {
                profileAvatarImage = nil
            }
        } catch {
            profileAvatarImage = nil
        }
    }

    @ViewBuilder private var dashboard: some View {
        if showingSearch {
            search
        } else if let dashboardDomain {
            domain(dashboardDomain, onBack: { self.dashboardDomain = nil })
        } else {
            NovaDashboardScreen(data: osgbDashboardData,
                onNavigate: navigate,
                onPhoto: { navigate(.newAnalysis) },
                onAssistant: { },
                footer: isExpert ? nil : AnyView(osgbHomeFooter),
                showsPhotoCapture: true,
                showsAssistant: !isExpert)
        }
    }

    /// The same dashboard component used by the personal/personnel workspace.
    /// Only the data adapter and the tenant-scoped footer differ by role.
    private var osgbDashboardData: NovaDashboardData {
        let board = isExpert ? expertDashboard : store.dashboard
        let firstName = app.profile?.fullName?.split(separator: " ").first.map(String.init) ?? "İSGADA"
        let metrics: [NovaMetricItem]
        if isExpert {
            metrics = [
                .init(id: "companies", value: board?.companies.first.map(String.init) ?? "—", label: "Firmalar", footer: "Atanmış", symbol: "building.2", tone: .accent, destination: .companies),
                .init(id: "personnel", value: personnel.map { String($0.employees.active) } ?? "—", label: "Personel", footer: "Toplam", symbol: "person.2", tone: .accent, destination: .companies),
                .init(id: "open", value: board?.nonconformities.first.map(String.init) ?? "—", label: "Açık uygunsuzluk", footer: "Tüm firmalar", symbol: "checklist", tone: .accent, destination: .findings),
                .init(id: "overdue", value: board?.nonconformities.second.map(String.init) ?? "—", label: "Süresi geçen", footer: "Tüm firmalar", symbol: "exclamationmark.triangle", tone: .accent, destination: .findings),
                .init(id: "training", value: board?.training.second.map(String.init) ?? "—", label: "Tamamlanan eğitim", footer: "Toplam", symbol: "graduationcap", tone: .accent, destination: .training),
                .init(id: "deadlines", value: board.map { String(($0.deadlines.first ?? 0) + ($0.deadlines.second ?? 0)) } ?? "—", label: "Yaklaşan kontroller", footer: "Tüm firmalar", symbol: "calendar.badge.clock", tone: .accent, destination: .periodicChecks)
            ]
        } else {
            metrics = [
                .init(id: "companies", value: board?.companies.first.map(String.init) ?? "—", label: "Firmalar", footer: "Aktif", symbol: "building.2", tone: .accent, destination: .companies),
                .init(id: "experts", value: board?.experts.map(String.init) ?? "—", label: "Uzmanlar", footer: "Aktif", symbol: "person.badge.shield.checkmark", tone: .accent, destination: .companies),
                .init(id: "open", value: board?.nonconformities.first.map(String.init) ?? "—", label: "Açık uygunsuzluk", footer: "Takipte", symbol: "checklist", tone: .accent, destination: .findings),
                .init(id: "overdue", value: board?.nonconformities.second.map(String.init) ?? "—", label: "Süresi geçen", footer: "Kontrol", symbol: "exclamationmark.triangle", tone: .accent, destination: .findings),
                .init(id: "training", value: board?.training.second.map(String.init) ?? "—", label: "Tamamlanan eğitim", footer: "Kayıt", symbol: "graduationcap", tone: .accent, destination: .training),
                .init(id: "deadlines", value: board.map { String(($0.deadlines.first ?? 0) + ($0.deadlines.second ?? 0)) } ?? "—", label: "Yaklaşan kontroller", footer: "Takvim", symbol: "calendar.badge.clock", tone: .accent, destination: .periodicChecks)
            ]
        }
        return .init(firstName: firstName,
            openCount: board?.nonconformities.first.map(Int.init),
            metrics: metrics,
            activity: isExpert ? nil : selectedCompany.map { "\($0.name) firması için güncel kayıtlar" },
            trainingMessage: "Gerçekleşen eğitimler ve katılımcı kayıtları",
            recentAnalyses: recentAnalyses.map { analysis in
                NovaRecentAnalysis(id: analysis.id.uuidString.lowercased(),
                    title: NovaAnalysisPresentation.title(analysis.title),
                    companyName: analysis.companyName ?? "Firmasız",
                    createdOn: NovaAnalysisPresentation.dateOnly(analysis.createdOn))
            },
            summaryMessage: context.map { isExpert
                ? "Atandığınız firmalardaki toplam güncel kayıtlar."
                : "\($0.name) için güncel kayıtlar."
            } ?? "Özet yükleniyor…")
    }

    private var osgbHomeFooter: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let company = selectedCompany {
                NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.workspace.company.active", table: .localizable,
                    fallback: "%@ firması için yetkili kayıtları görüntülüyorsunuz."), company.name))
            }
            companySelector
            if selectedCompany != nil {
                NovaCard(padding: 12) {
                    Button { showingSearch = true } label: {
                        HStack(spacing: 10) {
                            NovaIcon(symbol: "magnifyingglass", size: 19)
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: RDLocalization.string("localizable.nova.workspace.search.title", table: .localizable, fallback: "Firma Kayıtlarında Ara"), style: .bodyStrong)
                                NovaText(text: RDLocalization.string("localizable.nova.workspace.search.company.hint", table: .localizable, fallback: "Personel, uygunsuzluk, ekipman ve dosyalarda arayın."), style: .metaQuiet)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }.contentShape(Rectangle())
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
            if context?.canManageMembers == true {
                NovaCard(padding: 12) {
                    Button { showingMembers = true } label: {
                        HStack(spacing: 10) {
                            NovaIcon(symbol: "person.2.badge.gearshape", size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: RDLocalization.string("localizable.nova.workspace.members.title", table: .localizable, fallback: "Uzman ve yönetici ekibi"), style: .bodyStrong)
                                NovaText(text: RDLocalization.string("localizable.nova.workspace.members.hint", table: .localizable, fallback: "Davetleri, rolleri ve erişim durumlarını yönetin."), style: .metaQuiet)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }.contentShape(Rectangle())
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
            moduleGrid
        }
    }

    private var welcomeCard: some View {
        NovaCard(padding: 16, tint: NovaColorToken.surface.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: "Merhaba, \(app.profile?.fullName?.split(separator: " ").first.map(String.init) ?? "İSGADA")", style: .cardTitle)
                    }
                    Spacer(minLength: 0)
                    NovaIcon(symbol: "hand.wave", size: 20)
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                }
                if canManageCompanies {
                    HStack(spacing: 8) {
                        NovaCompactActionButton(title: "Firma ekle", symbol: "building.2.crop.circle", prominent: true) { editor = .create }
                        NovaCompactActionButton(title: "Uzman ekle", symbol: "person.badge.plus") { showingMembers = true }
                        NovaCompactActionButton(title: "Atama", symbol: "person.2.badge.gearshape") { openAssignments() }
                    }
                }
            }
        }
    }

    private var reportCenter: some View {
        NovaReportCenter(identity: identity, onBack: { navigate(.home) })
    }

    private var statistics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPageHeading(title: NovaDestination.statistics.title, onBack: { navigate(.home) })
                NovaHelpHint(text: "Firma, uzman ve operasyon göstergeleri.")
                if let board = isExpert ? expertDashboard : store.dashboard {
                    statGrid(board)
                    if let personnel { personnelGrid(personnel) }
                } else if store.phase == .loading {
                    NovaLoadingView(message: "İstatistikler yükleniyor…")
                } else {
                    NovaEmptyState(title: "İstatistikler alınamadı", message: "Bağlantınızı kontrol edip tekrar deneyin.")
                    NovaCompactActionButton(title: "Tekrar dene", symbol: "arrow.clockwise") { store.refresh() }
                }
                ForEach(IsgWorkspaceDomain.allCases, id: \.self) { item in
                    Button { navigate(destination(for: item)) } label: {
                        NovaCard(padding: 12) {
                            HStack(spacing: 10) {
                                NovaIcon(symbol: item.symbol, size: 18)
                                NovaText(text: item.title, style: .bodyStrong)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                            }.contentShape(Rectangle())
                        }
                    }.buttonStyle(NovaRowPressStyle()).disabled(selectedCompany == nil)
                }
            }.padding(16).padding(.bottom, novaTabBarInset)
                .novaAsyncContent(isLoading: store.phase == .loading)
        }
    }

    private func destination(for domain: IsgWorkspaceDomain) -> NovaDestination {
        switch domain {
        case .personnel: return .companies
        case .training: return .training
        case .risk: return .riskAssessments
        case .nonconformity: return .findings
        case .checklist: return .checklists
        case .emergencyPlan: return .emergencyPlans
        case .drill: return .drills
        case .appointment: return .appointments
        case .ppe: return .ppeHandovers
        case .equipment: return .periodicChecks
        case .katip: return .katipContracts
        case .annualPlan: return .annualWorkPlans
        case .board: return .boardMeetings
        case .workPermit: return .workPermits
        case .visit: return .visits
        case .files: return .documents
        }
    }

    private var moduleGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.workspace.modules.title", table: .localizable,
                fallback: "Firma operasyonları"), style: .sectionTitle)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(IsgWorkspaceDomain.allCases, id: \.self) { item in
                    Button { dashboardDomain = item } label: {
                        NovaCard(padding: 12) {
                            HStack(spacing: 8) {
                                NovaIcon(symbol: item.symbol, size: 18)
                                NovaText(text: item.title, style: .bodyStrong)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                    }.buttonStyle(NovaRowPressStyle()).disabled(selectedCompany == nil)
                }
                Button { navigate(.analyses) } label: {
                    NovaCard(padding: 12) {
                        HStack(spacing: 8) {
                            NovaIcon(symbol: NovaDestination.analyses.symbol, size: 18)
                            NovaText(text: NovaDestination.analyses.title, style: .bodyStrong)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                }.buttonStyle(NovaRowPressStyle()).disabled(selectedCompany == nil)
            }
        }
    }

    @ViewBuilder private var companies: some View {
        if showingSearch, companyWorkspace != nil {
            search
        } else if let company = companyWorkspace, let selectedDomain = companyWorkspaceDomain {
            domain(selectedDomain, onBack: { companyWorkspaceDomain = nil })
                .id("\(company.id):company:\(selectedDomain.rawValue)")
        } else if let company = companyWorkspace, companyWorkspaceAnalyses {
            analyses(onBack: { companyWorkspaceAnalyses = false })
                .id("\(company.id):company:analyses")
        } else if let company = companyWorkspace {
            companyOverview(company)
        } else {
            NovaCompaniesScreen(
                companies: store.companies.map { company in
                        NovaCompanyItem(id: company.id.uuidString, name: company.name,
                        detail: companySummary(company), progressCompleted: companyProfileProgress(company), progressTotal: 8)
                },
                isLoading: store.phase == .loading && store.companies.isEmpty,
                isOwnedList: !isExpert,
                onSelect: { id in
                    guard let companyID = UUID(uuidString: id) else { return }
                    companyWorkspaceID = companyID
                    companyWorkspaceDomain = nil
                    companyWorkspaceAnalyses = false
                    companyPersonnel = nil
                    if store.selectedCompanyID != companyID { store.selectCompany(companyID) }
                },
                onBack: { navigate(.home) },
                onRetry: { store.refresh() },
                onCreate: canManageCompanies ? { editor = .create } : nil)
        }
    }

    private func companyOverview(_ company: IsgWorkspaceCompany) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NovaPageHeading(title: "Firma Detayı", onBack: {
                    companyWorkspaceID = nil
                    companyWorkspaceDomain = nil
                    companyWorkspaceAnalyses = false
                })
                companyOverviewSummary(company)
                NovaCompanyReadinessCard(items: companyReadinessItems(company))
                companyLogoRow(company)
                if store.phase == .loading || store.selectedCompanyID != company.id {
                    NovaLoadingView(message: "Firma çalışma alanı hazırlanıyor…")
                } else {
                    if companyOverviewLoading && companyDomainSnapshots.isEmpty {
                        NovaLoadingView(message: "Sıradaki işler hazırlanıyor…")
                    } else {
                        nextActionsSection
                        companySearchRow
                        companyCategorySections(company)
                    }
                    if let companyOverviewError {
                        NovaTaskErrorSummary(message: companyOverviewError)
                        NovaCompactActionButton(title: "Firma özetini yeniden yükle", symbol: "arrow.clockwise") {
                            Task { await loadCompanyOverview(company.id) }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
                .novaAsyncContent(isLoading: store.phase == .loading)
        }
    }

    private func companyOverviewSummary(_ company: IsgWorkspaceCompany) -> some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(alignment: .top, spacing: 12) {
                    companyLogoMark
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: company.name, style: .cardTitle)
                        NovaText(text: [IsgWorkspaceDisplayText.value(company.hazardClass),
                            companyPersonnel.map { "\($0.employees.active) personel" }]
                            .compactMap { $0 }.joined(separator: " · "), style: .metaQuiet)
                    }
                    Spacer(minLength: 0)
                    if canManageCompanies {
                        Button { editor = .edit(company) } label: {
                            Image(systemName: "pencil").frame(width: 44, height: 44)
                        }.buttonStyle(NovaRowPressStyle()).accessibilityLabel("Firmayı düzenle")
                    }
                }
                NovaMetricStrip(items: [
                    .init(id: "open-findings", value: String(openCompanyNonconformityCount),
                          label: "açık uygunsuzluk", symbol: "exclamationmark.triangle",
                          status: openCompanyNonconformityCount > 0 ? .danger : .success),
                    .init(id: "actions", value: String(companyNextActions.count),
                          label: "işlem gerekli", symbol: "checklist",
                          status: companyNextActions.isEmpty ? .success : .warning)
                ])
            }
        }
    }

    @ViewBuilder private var companyLogoMark: some View {
        if let companyLogo {
            Image(uiImage: companyLogo).resizable().scaledToFit().padding(5)
                .frame(width: 44, height: 44)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                .accessibilityLabel("Firma logosu")
        } else {
            NovaIcon(symbol: "building.2", size: 22)
                .frame(width: 44, height: 44)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 13))
        }
    }

    private func companyLogoRow(_ company: IsgWorkspaceCompany) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaCard(padding: 11) {
                HStack(spacing: 11) {
                    companyLogoMark
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: companyLogo == nil ? "Firma logosu ekleyin" : "Firma logosu", style: .bodyStrong)
                        NovaText(text: companyLogoSaving ? "Logo yükleniyor…" : "Firma kartında ve oluşturulan raporlarda kullanılır.",
                                 style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    if companyLogoSaving {
                        ProgressView().controlSize(.small).frame(width: 44, height: 44)
                    } else {
                        PhotosPicker(selection: $companyLogoPicker, matching: .images) {
                            HStack(spacing: 5) {
                                Image(systemName: companyLogo == nil ? "plus" : "arrow.triangle.2.circlepath")
                                Text(companyLogo == nil ? "Logo seç" : "Değiştir")
                            }
                            .font(.custom("PlusJakartaSans-SemiBold", size: 10))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 10).frame(minHeight: 44)
                            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(NovaRowPressStyle())
                        .accessibilityIdentifier("company.logo.picker")
                    }
                }.frame(maxWidth: .infinity, minHeight: 54)
            }
            if let companyLogoError {
                NovaText(text: companyLogoError, style: .micro,
                         color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(company.name) firma logosu")
    }

    private var nextActionsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                NovaText(text: "Sıradaki işler", style: .sectionTitle)
                Spacer(minLength: 0)
                if companyOverviewLoading { ProgressView().controlSize(.small) }
            }
            if companyNextActions.isEmpty {
                NovaCard(padding: 14, tint: NovaColorToken.statusSuccessBg.color(in: scheme)) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: "Şu anda kritik iş görünmüyor", style: .bodyStrong)
                            NovaText(text: "Kayıt kategorilerinden ayrıntıları inceleyebilirsiniz.", style: .metaQuiet)
                        }
                    }
                }
            } else {
                ForEach(companyNextActions.prefix(3)) { item in
                    Button { companyWorkspaceDomain = item.domain } label: {
                        NovaCard(padding: 13) {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: item.symbol).font(.system(size: 18, weight: .semibold))
                                    .frame(width: 36, height: 36)
                                    .background(item.status.tokens.background.color(in: scheme),
                                                in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 3) {
                                    NovaText(text: item.title, style: .bodyStrong)
                                    NovaText(text: item.detail, style: .metaQuiet)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                                    .padding(.top, 5)
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
        }
    }

    private var companySearchRow: some View {
        Button { showingSearch = true } label: {
            HStack(spacing: 10) {
                NovaIcon(symbol: "magnifyingglass", size: 18)
                NovaText(text: "Firma kayıtlarında ara", style: .bodyStrong)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
            }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 50)
                .novaControlBackground(cornerRadius: 14).contentShape(Rectangle())
        }.buttonStyle(NovaRowPressStyle())
    }

    private func companyCategorySections(_ company: IsgWorkspaceCompany) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            companyCategory("Firma ve kadro") {
                companyPlainRow(title: "Firma bilgileri", subtitle: company.sector?.isEmpty == false ? company.sector! : "Profil bilgileri",
                    symbol: "building.2", status: company.sector?.isEmpty == false ? ("Güncel", .success) : ("Takip gerekli", .warning),
                    action: canManageCompanies ? { editor = .edit(company) } : nil)
                companyPlainRow(title: "Personel", subtitle: companyPersonnel.map { "\($0.employees.active) kişi" } ?? "Yükleniyor",
                    symbol: IsgWorkspaceDomain.personnel.symbol,
                    status: (companyPersonnel?.employees.active ?? 0) > 0 ? ("Güncel", .success) : ("Başlanmadı", .warning)) {
                        companyWorkspaceDomain = .personnel
                    }
                companyDomainRow(.appointment)
            }
            companyCategory("Risk ve acil durum") {
                companyDomainRow(.risk)
                companyDomainRow(.emergencyPlan)
                companyDomainRow(.drill)
            }
            companyCategory("Kontrol ve kayıtlar") {
                companyDomainRow(.equipment)
                companyDomainRow(.nonconformity)
                companyDomainRow(.checklist)
                companyDomainRow(.files)
                companyPlainRow(title: NovaDestination.analyses.title, subtitle: "Fotoğraflı saha analizleri",
                    symbol: NovaDestination.analyses.symbol, status: nil) { companyWorkspaceAnalyses = true }
            }
            companyCategory("Eğitim ve organizasyon") {
                companyDomainRow(.training)
                companyDomainRow(.board)
                companyDomainRow(.katip)
            }
            companyCategory("Diğer kayıtlar") {
                companyDomainRow(.annualPlan)
                companyDomainRow(.visit)
                companyDomainRow(.ppe)
            }
            companyCategory("Örnek formlar") {
                companyPlainRow(title: IsgWorkspaceDomain.workPermit.title, subtitle: "56 indirilebilir Word örneği",
                    symbol: IsgWorkspaceDomain.workPermit.symbol, status: nil) { companyWorkspaceDomain = .workPermit }
            }
        }
    }

    private func companyCategory<Content: View>(_ title: String,
                                                @ViewBuilder content: @escaping () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: title, style: .sectionTitle)
            NovaCard(padding: 0) {
                VStack(spacing: 0) { content() }
            }
        }
    }

    private func companyDomainRow(_ domain: IsgWorkspaceDomain) -> some View {
        let value = companyModuleStatus(domain)
        return companyPlainRow(title: domain.title, subtitle: companyModuleSubtitle(domain),
            symbol: domain.symbol, status: value) { companyWorkspaceDomain = domain }
    }

    private func companyPlainRow(title: String, subtitle: String, symbol: String,
                                 status: (String, NovaStatus)?, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 11) {
                NovaIcon(symbol: symbol, size: 17).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: title, style: .bodyStrong)
                    NovaText(text: subtitle, style: .metaQuiet)
                }
                Spacer(minLength: 8)
                if let status { NovaStatusPill(label: status.0, status: status.1) }
                if action != nil { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
            }.padding(.horizontal, 13).frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
        }.buttonStyle(NovaRowPressStyle()).disabled(action == nil)
    }

    private func companyModuleSubtitle(_ domain: IsgWorkspaceDomain) -> String {
        guard let snapshot = companyDomainSnapshots[domain.rawValue] else {
            return companyOverviewLoading ? "Yükleniyor…" : "Kayıtları görüntüle"
        }
        return snapshot.rows.isEmpty ? "Henüz kayıt yok" : "\(snapshot.rows.count) kayıt"
    }

    private func companyModuleStatus(_ domain: IsgWorkspaceDomain) -> (String, NovaStatus)? {
        guard let snapshot = companyDomainSnapshots[domain.rawValue] else { return nil }
        guard !snapshot.rows.isEmpty else { return ("Başlanmadı", .warning) }
        let statuses = snapshot.rows.compactMap(\.status)
        let metric = snapshot.metrics.filter { $0.value > 0 }.map(\.id)
        if statuses.contains(where: { ["overdue", "expired", "failed", "critical"].contains($0) }) ||
            metric.contains(where: { $0.contains("overdue") || $0.contains("expired") || $0.contains("failed") }) {
            return ("Dikkat", .danger)
        }
        if statuses.contains(where: { ["due_soon", "upcoming"].contains($0) }) ||
            metric.contains(where: { $0.contains("due_soon") || $0.contains("upcoming") }) {
            return ("Yaklaşıyor", .warning)
        }
        if statuses.contains(where: { ["open", "assigned", "in_progress", "pending_verification", "untracked", "never_inspected", "period_unknown"].contains($0) }) ||
            metric.contains(where: { $0.contains("untracked") || $0.contains("open") }) {
            return ("Takip gerekli", .warning)
        }
        if statuses.contains(where: { ["draft", "planned"].contains($0) }) { return ("Devam ediyor", .info) }
        return ("Güncel", .success)
    }

    private func companyReadinessItems(_ company: IsgWorkspaceCompany) -> [NovaCompanyReadinessItem] {
        let hasCompanyInfo = company.sector?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && company.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let personnelStatus: NovaCompanyReadinessStatus = companyPersonnel.map {
            $0.employees.active > 0 ? .complete : .missing
        } ?? .unknown
        let logoStatus: NovaCompanyReadinessStatus = companyOverviewLoading
            && companyDomainSnapshots[IsgWorkspaceDomain.files.rawValue] == nil ? .unknown
            : (companyLogo == nil ? .missing : .complete)
        let responsible = company.responsibleName?.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            .init(id: "company", title: "Firma Bilgileri",
                detail: hasCompanyInfo ? "Temel firma bilgileri güncel." : "Sektör veya adres bilgisi eksik.",
                status: hasCompanyInfo ? .complete : .missing),
            readinessItem(id: "risk", title: "Risk Analizi", domain: .risk),
            readinessItem(id: "emergency", title: "Acil Durum Planı", domain: .emergencyPlan),
            readinessItem(id: "training", title: "Eğitim", domain: .training),
            .init(id: "personnel", title: "Personel",
                detail: companyPersonnel.map { "\($0.employees.active) aktif personel kayıtlı." } ?? "Personel verisi yükleniyor.",
                status: personnelStatus),
            readinessItem(id: "nonconformity", title: "Uygunsuzluk", domain: .nonconformity),
            readinessItem(id: "equipment", title: "Periyodik Kontrol", domain: .equipment),
            .init(id: "logo", title: "Logo",
                detail: companyLogo == nil ? "Firma logosu eklenmemiş." : "Firma logosu kayıtlı.",
                status: logoStatus),
            .init(id: "responsible", title: "Sorumlu Kişi",
                detail: responsible?.isEmpty == false ? responsible! : "Sorumlu kişi tanımlanmamış.",
                status: responsible?.isEmpty == false ? .complete : .missing),
            readinessItem(id: "visits", title: "Ziyaretler", domain: .visit)
        ]
    }

    private func readinessItem(id: String, title: String,
                               domain: IsgWorkspaceDomain) -> NovaCompanyReadinessItem {
        guard let snapshot = companyDomainSnapshots[domain.rawValue] else {
            return .init(id: id, title: title,
                detail: companyOverviewLoading ? "Durum yükleniyor." : "Durum bilgisi alınamadı.", status: .unknown)
        }
        guard !snapshot.rows.isEmpty else {
            return .init(id: id, title: title, detail: "Henüz kayıt yok.", status: .missing)
        }
        let status: NovaCompanyReadinessStatus
        switch companyModuleStatus(domain)?.1 {
        case .success: status = .complete
        case .warning, .danger, .info: status = .needsReview
        case .neutral, .none: status = .unknown
        }
        let detail = companyModuleStatus(domain).map { "\(snapshot.rows.count) kayıt · \($0.0)" }
            ?? "\(snapshot.rows.count) kayıt bulundu."
        return .init(id: id, title: title, detail: detail, status: status)
    }

    private var monitoredCompanyDomains: [IsgWorkspaceDomain] {
        [.risk, .emergencyPlan, .equipment, .nonconformity, .training, .appointment,
         .drill, .checklist, .board, .katip, .files, .visit]
    }
    private var monitoredCompanyModuleCount: Int { monitoredCompanyDomains.count }
    private var currentCompanyModuleCount: Int {
        monitoredCompanyDomains.filter { companyModuleStatus($0)?.1 == .success }.count
    }
    private var openCompanyNonconformityCount: Int {
        (companyDomainSnapshots[IsgWorkspaceDomain.nonconformity.rawValue]?.rows ?? [])
            .filter { !["closed", "cancelled"].contains($0.status ?? "") }.count
    }
    private var companyNextActions: [CompanyNextAction] {
        var result: [CompanyNextAction] = []
        if openCompanyNonconformityCount > 0 {
            result.append(.init(id: "nonconformity", title: "Açık uygunsuzlukları incele",
                detail: "\(openCompanyNonconformityCount) kayıt takip bekliyor", symbol: "exclamationmark.triangle",
                status: .danger, domain: .nonconformity))
        }
        for (domain, title, detail, symbol) in [
            (IsgWorkspaceDomain.risk, "Risk değerlendirmesi oluştur", "Henüz değerlendirme kaydı yok", "checkmark.shield"),
            (.emergencyPlan, "Acil durum planı oluştur", "Henüz yürürlükte bir plan yok", "light.beacon.max"),
            (.equipment, "Ekipman ve kontrol takibini başlat", "Henüz ekipman kaydı yok", "wrench.and.screwdriver"),
            (.appointment, "Çalışan görevlerini tanımla", "Henüz atama kaydı yok", "person.badge.shield.checkmark"),
            (.training, "İlk eğitim kaydını oluştur", "Henüz gerçekleşen eğitim yok", "graduationcap")
        ] {
            if let snapshot = companyDomainSnapshots[domain.rawValue], snapshot.rows.isEmpty {
                result.append(.init(id: domain.rawValue, title: title, detail: detail,
                    symbol: symbol, status: .warning, domain: domain))
            }
        }
        return result
    }

    @MainActor private func loadCompanyOverview(_ companyID: UUID) async {
        companyOverviewLoading = true; companyOverviewError = nil
        async let personnelValue = try? await store.personnelMetrics(companyID: companyID)
        async let risk = try? await store.domain(.risk, companyID: companyID, limit: 20)
        async let emergency = try? await store.domain(.emergencyPlan, companyID: companyID, limit: 20)
        async let equipment = try? await store.domain(.equipment, companyID: companyID, limit: 20)
        async let nonconformity = try? await store.domain(.nonconformity, companyID: companyID, limit: 20)
        async let training = try? await store.domain(.training, companyID: companyID, limit: 20)
        async let appointment = try? await store.domain(.appointment, companyID: companyID, limit: 20)
        async let drill = try? await store.domain(.drill, companyID: companyID, limit: 20)
        async let checklist = try? await store.domain(.checklist, companyID: companyID, limit: 20)
        async let board = try? await store.domain(.board, companyID: companyID, limit: 20)
        async let katip = try? await store.domain(.katip, companyID: companyID, limit: 20)
        async let files = try? await store.domain(.files, companyID: companyID, limit: 20)
        async let visits = try? await store.domain(.visit, companyID: companyID, limit: 20)
        let values = await (personnelValue, risk, emergency, equipment, nonconformity, training,
                            appointment, drill, checklist, board, katip, files, visits)
        guard companyWorkspaceID == companyID, store.selectedCompanyID == companyID else { return }
        companyPersonnel = values.0
        let snapshots = [values.1, values.2, values.3, values.4, values.5, values.6,
                         values.7, values.8, values.9, values.10, values.11, values.12].compactMap { $0 }
        companyDomainSnapshots = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.domain.rawValue, $0) })
        await loadCompanyLogo(from: values.11, companyID: companyID)
        if companyPersonnel == nil || snapshots.count < monitoredCompanyDomains.count {
            companyOverviewError = "Bazı firma durumları alınamadı. Görünen kayıtları kullanabilir veya özeti yenileyebilirsiniz."
        }
        companyOverviewLoading = false
    }

    @MainActor private func loadCompanyLogo(from files: IsgWorkspaceDomainSnapshot?, companyID: UUID) async {
        guard companyWorkspaceID == companyID, store.selectedCompanyID == companyID else { return }
        guard let row = files?.rows.first(where: { record in
            record.facts.contains { $0.0 == "category" && $0.1 == "company_logo" }
        }) else {
            companyLogo = nil; companyLogoEntryID = nil
            return
        }
        guard row.id != companyLogoEntryID || companyLogo == nil else { return }
        guard let download = try? await store.downloadFile(row, companyID: companyID),
              !Task.isCancelled, companyWorkspaceID == companyID,
              let image = UIImage(data: download.data) else { return }
        companyLogo = image
        companyLogoEntryID = row.id
    }

    @MainActor private func saveCompanyLogo(_ item: PhotosPickerItem) async {
        guard canManageCompanyLogo, let companyID = companyWorkspaceID else {
            companyLogoPicker = nil
            return
        }
        companyLogoSaving = true; companyLogoError = nil
        defer { companyLogoSaving = false; companyLogoPicker = nil }
        do {
            guard let source = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: source),
                  let data = normalizedCompanyLogo(image) else {
                throw IsgWorkspaceAPIFailure.invalidRequest
            }
            let digest = IsgWorkspaceMutationAttempt.digest(data)
            let uploadMutationID = companyLogoUploadAttempt.id(namespace: "company.logo.upload",
                components: [companyID.uuidString.lowercased(), digest])
            let upload = try await store.uploadFile(mutationID: uploadMutationID, title: "Firma logosu",
                filename: "firma-logo.jpg", category: "company_logo", data: data, companyID: companyID)
            let linkMutationID = companyLogoLinkAttempt.id(namespace: "company.logo.link",
                components: [companyID.uuidString.lowercased(), upload.entryID.uuidString.lowercased()])
            _ = try await store.mutateDomain(mutationID: linkMutationID, domain: .files, payload: [
                "action": .string("set_company_logo"), "entry_id": .id(upload.entryID)
            ], companyID: companyID)
            guard companyWorkspaceID == companyID else { return }
            companyLogo = image; companyLogoEntryID = upload.entryID
            celebrate(NovaSuccessMessage.companyLogoAdded)
        } catch {
            companyLogoError = "Logo eklenemedi. JPG veya PNG görseliyle yeniden deneyin."
        }
    }

    private func normalizedCompanyLogo(_ image: UIImage) -> Data? {
        func render(maximum: CGFloat, quality: CGFloat) -> Data? {
            let longest = max(image.size.width, image.size.height)
            guard longest > 0 else { return nil }
            let scale = min(1, maximum / longest)
            let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
            let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
            let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIColor.white.setFill(); UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return rendered.jpegData(compressionQuality: quality)
        }
        for candidate in [(CGFloat(1_600), CGFloat(0.84)), (1_200, 0.72), (900, 0.60)] {
            if let data = render(maximum: candidate.0, quality: candidate.1), data.count <= 5 * 1_024 * 1_024 {
                return data
            }
        }
        return nil
    }

    private var search: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPageHeading(title: RDLocalization.string(
                    "localizable.nova.workspace.search.title", table: .localizable,
                    fallback: "Firma Kayıtlarında Ara"), onBack: { showingSearch = false })
                if selectedCompany == nil {
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.company.pick", table: .localizable,
                            fallback: "Önce firma seçin"),
                        message: RDLocalization.string("localizable.nova.workspace.search.company.required", table: .localizable,
                            fallback: "Arama yalnız seçtiğiniz firmanın yetkili kayıtlarında çalışır."))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                        TextField(RDLocalization.string("localizable.nova.workspace.search.placeholder", table: .localizable,
                            fallback: "Personel, uygunsuzluk, ekipman veya dosya ara"), text: $query)
                            .font(NovaFont.font(.body)).submitLabel(.search).onSubmit { runSearch() }
                        Button(action: runSearch) {
                            if searching { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.right") }
                        }.frame(width: 44, height: 44).disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).utf8.count < 2)
                    }.padding(.horizontal, 12).novaControlBackground(cornerRadius: 16)
                    if let searchError { NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.search.failed", table: .localizable,
                        fallback: "Arama tamamlanamadı"), message: searchError) }
                    if let searchRows, searchRows.isEmpty {
                        NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.search.empty", table: .localizable,
                                fallback: "Eşleşen kayıt yok"),
                            message: RDLocalization.string("localizable.nova.workspace.search.empty.detail", table: .localizable,
                                fallback: "Farklı bir ad, başlık veya kodla yeniden arayın."))
                    } else if let searchRows {
                        ForEach(searchRows, id: \.id) { row in
                            NovaCard(padding: 12) {
                                HStack(spacing: 10) {
                                    NovaIcon(symbol: symbol(row.kind), size: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        NovaText(text: row.title, style: .bodyStrong)
                                        if let subtitle = row.subtitle { NovaText(text: subtitle, style: .metaQuiet) }
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
        }
    }

    @ViewBuilder private func domain(_ value: IsgWorkspaceDomain, startInAddMode: Bool = false,
                                     onBack: (() -> Void)? = nil) -> some View {
        if value == .workPermit {
            NovaWorkPermitLibraryScreen(onBack: onBack ?? { navigate(.home) })
        } else if let company = selectedCompany {
            if value == .personnel {
                personnelScreen(onBack: onBack)
            } else {
                IsgWorkspaceDomainScreen(store: store, domain: value, companyName: company.name,
                    companyHazardClass: company.hazardClass,
                    canOperate: context?.canOperate == true,
                    startInAddMode: startInAddMode,
                    onBack: onBack ?? { navigate(.home) })
                    .id("\(company.id):\(value.rawValue):\(startInAddMode)")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: value.title, onBack: onBack ?? { navigate(.home) })
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.company.pick", table: .localizable,
                            fallback: "Önce firma seçin"),
                        message: RDLocalization.string("localizable.nova.workspace.domain.company.required", table: .localizable,
                            fallback: "Bu modüldeki kayıtlar firma kapsamında tutulur. Ana sayfadan bir firma seçin."))
                }.padding(16)
            }
        }
    }

    @ViewBuilder private func personnelScreen(initialSection: IsgPersonnelSection = .employee,
                                               onBack: (() -> Void)? = nil) -> some View {
        if let company = selectedCompany {
            IsgWorkspacePersonnelScreen(store: store, companyName: company.name,
                canOperate: context?.canOperate == true, canManageDirectory: canManageCompanies,
                initialSection: initialSection, onBack: onBack ?? { navigate(.home) })
                .id("\(company.id):personnel:\(initialSection.rawValue)")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: IsgWorkspaceDomain.personnel.title,
                                    onBack: onBack ?? { navigate(.home) })
                    NovaEmptyState(title: "Önce firma seçin",
                                   message: "Personel ve organizasyon kayıtları firma kapsamında tutulur.")
                }.padding(16)
            }
        }
    }

    private var changes: some View {
        IsgWorkspaceChangeScreen(store: store, companyName: selectedCompany?.name,
                                 onBack: { navigate(.home) })
    }

    @ViewBuilder private func analyses(startInCreateMode: Bool = false,
                                       onBack: (() -> Void)? = nil) -> some View {
        if let company = selectedCompany {
            IsgWorkspaceAnalysisScreen(store: store, companyID: company.id,
                companyName: company.name, canOperate: context?.canOperate == true,
                startInCreateMode: startInCreateMode,
                onBack: onBack ?? { navigate(.findings) })
                .id("\(company.id):analyses:\(startInCreateMode)")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: NovaDestination.analyses.title,
                                    onBack: onBack ?? { navigate(.findings) })
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.company.pick", table: .localizable,
                            fallback: "Önce firma seçin"),
                        message: RDLocalization.string("localizable.nova.workspace.domain.company.required", table: .localizable,
                            fallback: "Bu modüldeki kayıtlar firma kapsamında tutulur. Ana sayfadan bir firma seçin."))
                }.padding(16)
            }
        }
    }

    private func workspaceHeading(title: String) -> some View {
        HStack(spacing: 10) {
            NovaText(text: title, style: .screenTitle)
            Spacer(minLength: 0)
            Button(action: onSwitchWorkspace) {
                HStack(spacing: 5) { Image(systemName: "arrow.triangle.2.circlepath"); NovaText(text: role(context?.membership.role ?? "expert"), style: .meta) }
                    .padding(.horizontal, 10).frame(minHeight: 44).novaControlBackground(cornerRadius: 15)
            }.buttonStyle(NovaRowPressStyle())
        }
    }

    private func statGrid(_ board: IsgWorkspaceDashboard) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.companies", table: .localizable, fallback: "Firmalar"), symbol: "building.2", value: value(board.companies.first))
            if !isExpert {
                NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.experts", table: .localizable, fallback: "Uzmanlar"), symbol: "person.badge.shield.checkmark", value: value(board.experts))
            }
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.open", table: .localizable, fallback: "Açık uygunsuzluk"), symbol: "checklist", value: value(board.nonconformities.first))
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.overdue", table: .localizable, fallback: "Süresi geçen"), symbol: "exclamationmark.triangle", value: value(board.nonconformities.second))
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.training", table: .localizable, fallback: "Tamamlanan eğitim"), symbol: "graduationcap", value: value(board.training.second))
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.deadlines", table: .localizable, fallback: "Yaklaşan kontroller"), symbol: "calendar.badge.clock", value: value((board.deadlines.first ?? 0) + (board.deadlines.second ?? 0)))
        }
    }

    private func personnelGrid(_ value: IsgPersonnelMetrics) -> some View {
        HStack(spacing: 8) {
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.personnel", table: .localizable, fallback: "Personel"), symbol: "person.2", value: String(value.employees.active))
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.workplaces", table: .localizable, fallback: "İşyerleri"), symbol: "building.2", value: String(value.workplaces.active))
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.departments", table: .localizable, fallback: "Departmanlar"), symbol: "square.grid.2x2", value: String(value.departments.active))
        }
    }

    private var companySelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.workspace.company.choose", table: .localizable,
                fallback: "Firma seçimi"), style: .sectionTitle)
            ForEach(store.companies, id: \.id) { company in companyRow(company) }
        }
    }

    private func companyRow(_ company: IsgWorkspaceCompany) -> some View {
        NovaCard(padding: 12) {
            HStack(spacing: 6) {
                Button {
                    store.selectCompany(company.id)
                    navigation.apply(.navigate(.home), from: navigation.epoch)
                } label: {
                    HStack(spacing: 10) {
                    NovaIcon(symbol: "building.2", size: 19)
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: company.name, style: .bodyStrong)
                        NovaText(text: companySummary(company), style: .metaQuiet)
                    }
                    Spacer(minLength: 0)
                    if store.selectedCompanyID == company.id { Image(systemName: "checkmark.circle.fill") }
                    }.contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle())
                if canManageCompanies {
                    Button { editor = .edit(company) } label: {
                        Image(systemName: "pencil").frame(width: 44, height: 44)
                    }
                    .buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(RDLocalization.string("localizable.nova.workspace.company.edit", table: .localizable,
                        fallback: "Firmayı düzenle"))
                }
            }
        }
    }

    private func runSearch() {
        guard let company = store.selectedCompanyID else { return }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.utf8.count >= 2 else { return }
        searching = true; searchError = nil
        Task {
            do { searchRows = try await store.search(companyID: company, query: clean).rows }
            catch { searchRows = nil; searchError = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable, fallback: "Bağlantınızı kontrol edip yeniden deneyin.") }
            searching = false
        }
    }

    private func openAssignments() {
        if selectedCompany != nil {
            showingAssignments = true
        } else {
            navigation.apply(.select(.companies), from: navigation.epoch)
        }
    }

    private func navigate(_ destination: NovaDestination) { navigation.apply(.navigate(destination), from: navigation.epoch) }
    private func value(_ value: Int64?) -> String { value.map(String.init) ?? "—" }
    private func role(_ value: String) -> String {
        switch value {
        case "owner": return RDLocalization.string("localizable.nova.workspace.role.owner", table: .localizable, fallback: "OSGB sahibi")
        case "admin": return RDLocalization.string("localizable.nova.workspace.role.admin", table: .localizable, fallback: "OSGB yöneticisi")
        default: return RDLocalization.string("localizable.nova.workspace.role.expert", table: .localizable, fallback: "İSG uzmanı")
        }
    }
    private func hazard(_ value: String) -> String {
        switch value {
        case "low": return RDLocalization.string("localizable.nova.visual.7", table: .localizable, fallback: "Az Tehlikeli")
        case "high": return RDLocalization.string("localizable.nova.visual.9", table: .localizable, fallback: "Çok Tehlikeli")
        default: return RDLocalization.string("localizable.nova.visual.8", table: .localizable, fallback: "Tehlikeli")
        }
    }
    private func companySummary(_ company: IsgWorkspaceCompany) -> String {
        var parts = [hazard(company.hazardClass)]
        if let sector = company.sector, !sector.isEmpty { parts.append(sector) }
        if let count = company.declaredEmployeeCount { parts.append("\(count) çalışan") }
        return parts.joined(separator: " · ")
    }
    private func companyProfileProgress(_ company: IsgWorkspaceCompany) -> Int {
        func present(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return value
        }
        return [present(company.sector), company.declaredEmployeeCount.map(String.init),
            present(company.email), present(company.address), present(company.responsibleName),
            present(company.responsiblePhone), present(company.responsibleEmail), present(company.hazardClass)].compactMap { $0 }.count
    }
    private func symbol(_ kind: String) -> String {
        switch kind { case "employee": return "person"; case "equipment": return "shippingbox"; case "training": return "graduationcap"; case "file": return "doc"; default: return "checklist" }
    }
}

private struct IsgWorkspaceMemberManagement: View {
    private struct ActivitySelection: Identifiable {
        let id: UUID
        let workspace: UUID
    }
    @State private var activityMember: ActivitySelection?
    @ObservedObject var store: IsgWorkspaceStore
    var onOpenRecord: ((BusinessActivityDetail, Bool) -> Void)? = nil
    @State private var members: [IsgWorkspaceMember] = []
    @State private var invitations: [IsgWorkspaceInvitation] = []
    @State private var email = ""
    @State private var inviteRole = "expert"
    @State private var latestToken: IsgWorkspaceInvitationToken?
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var pendingExpiration: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NovaText(text: RDLocalization.string("localizable.nova.workspace.members.title", table: .localizable,
                    fallback: "Uzman ve yönetici ekibi"), style: .sectionTitle)
                HStack(spacing: 8) {
                    NovaListStat(title: RDLocalization.string("localizable.nova.workspace.members.active", table: .localizable,
                        fallback: "Aktif üye"), symbol: "person.2", value: String(members.filter { $0.status == "active" }.count))
                    NovaListStat(title: RDLocalization.string("localizable.nova.workspace.invitations.pending", table: .localizable,
                        fallback: "Bekleyen davet"), symbol: "envelope", value: String(invitations.filter { $0.status == "pending" }.count))
                }
                invitationForm
                if let latestToken { invitationToken(latestToken) }
                if let error { NovaHelpHint(text: error) }
                if loading {
                    NovaLoadingView(message: RDLocalization.string("localizable.nova.workspace.members.loading", table: .localizable,
                        fallback: "Ekip yükleniyor…"))
                } else {
                    memberList
                    invitationList
                }
            }.padding(18).padding(.bottom, 24).novaPopupContentSize()
                .novaAsyncContent(isLoading: loading)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .sheet(item: $activityMember) { selection in
            ExpertActivityDestination(workspace: selection.workspace, member: selection.id,
                onClose: { activityMember = nil }, onOpenRecord: { detail, companyOnly in
                    activityMember = nil
                    onOpenRecord?(detail, companyOnly)
                })
        }
    }

    private var invitationForm: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                NovaText(text: RDLocalization.string("localizable.nova.workspace.invite.title", table: .localizable,
                    fallback: "Ekibe davet et"), style: .bodyStrong)
                TextField(RDLocalization.string("localizable.nova.workspace.invite.email", table: .localizable,
                    fallback: "E-posta adresi"), text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(NovaFont.font(.body))
                Picker(RDLocalization.string("localizable.nova.workspace.invite.role", table: .localizable,
                    fallback: "Rol"), selection: $inviteRole) {
                    Text(RDLocalization.string("localizable.nova.workspace.role.expert", table: .localizable,
                        fallback: "İSG uzmanı")).tag("expert")
                    Text(RDLocalization.string("localizable.nova.workspace.role.admin", table: .localizable,
                        fallback: "OSGB yöneticisi")).tag("admin")
                }.pickerStyle(.segmented)
                NovaCompactActionButton(title: working
                    ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…")
                    : RDLocalization.string("localizable.nova.workspace.invite.send", table: .localizable, fallback: "Davet oluştur"),
                    symbol: "paperplane", prominent: true, enabled: canInvite && !working) { invite() }
            }
        }
    }

    private func invitationToken(_ value: IsgWorkspaceInvitationToken) -> some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                NovaStatusPill(label: RDLocalization.string("localizable.nova.workspace.invite.ready", table: .localizable,
                    fallback: "Davet hazır"), status: .success)
                NovaText(text: RDLocalization.string("localizable.nova.workspace.invite.share.hint", table: .localizable,
                    fallback: "Bu kod yalnız bu ekranda gösterilir. Davet edilen kişiyle güvenli biçimde paylaşın."), style: .metaQuiet)
                Text(value.token).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ShareLink(item: value.token) {
                    Label(RDLocalization.string("localizable.nova.workspace.invite.share", table: .localizable,
                        fallback: "Davet kodunu paylaş"), systemImage: "square.and.arrow.up")
                        .font(NovaFont.font(.bodyStrong)).frame(minHeight: 44)
                }
            }
        }
    }

    private var memberList: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.workspace.members.list", table: .localizable,
                fallback: "Ekip üyeleri"), style: .sectionTitle)
            ForEach(members, id: \.id) { member in
                NovaCard(padding: 12) {
                    HStack(spacing: 10) {
                        NovaIcon(symbol: member.role == "expert" ? "person.badge.shield.checkmark" : "person.crop.circle.badge.checkmark", size: 19)
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: role(member.role), style: .bodyStrong)
                            NovaText(text: String((member.userID ?? member.id).uuidString.prefix(8)) + " · " + status(member.status), style: .metaQuiet)
                            Text("Kullanım ve işlem geçmişi").font(NovaFont.font(.metaQuiet)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if member.role != "owner" {
                            Menu {
                                if member.status == "active" {
                                    Button { mutate(member, action: "change_role", value: member.role == "expert" ? "admin" : "expert") } label: {
                                        Label(RDLocalization.string("localizable.nova.workspace.member.role.change", table: .localizable,
                                            fallback: "Rolü değiştir"), systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    Button { mutate(member, action: "suspend", reason: defaultReason) } label: {
                                        Label(RDLocalization.string("localizable.nova.workspace.member.suspend", table: .localizable,
                                            fallback: "Erişimi askıya al"), systemImage: "pause.circle")
                                    }
                                    if member.role == "expert" {
                                        Button { mutate(member, action: "set_practicing", value: member.isPracticingExpert ? "false" : "true") } label: {
                                            Label(member.isPracticingExpert
                                                ? RDLocalization.string("localizable.nova.workspace.member.practice.off", table: .localizable, fallback: "Uzman pratiğini kapat")
                                                : RDLocalization.string("localizable.nova.workspace.member.practice.on", table: .localizable, fallback: "Uzman pratiğini aç"),
                                                systemImage: member.isPracticingExpert ? "person.badge.minus" : "person.badge.plus")
                                        }
                                    }
                                    Button(role: .destructive) { mutate(member, action: "end", reason: defaultReason) } label: {
                                        Label(RDLocalization.string("localizable.nova.workspace.member.end", table: .localizable,
                                            fallback: "Üyeliği sonlandır"), systemImage: "person.crop.circle.badge.xmark")
                                    }
                                } else if member.status == "suspended" {
                                    Button { mutate(member, action: "reactivate", reason: defaultReason) } label: {
                                        Label(RDLocalization.string("localizable.nova.workspace.member.reactivate", table: .localizable,
                                            fallback: "Erişimi yeniden aç"), systemImage: "play.circle")
                                    }
                                }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                                .disabled(working)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let user = member.userID, let workspace = store.selection?.workspaceID {
                            activityMember = ActivitySelection(id: user, workspace: workspace)
                        }
                    }
                }
            }
        }
    }

    private var invitationList: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.workspace.invitations.list", table: .localizable,
                fallback: "Davetler"), style: .sectionTitle)
            let pending = invitations.filter { $0.status == "pending" }
            if pending.isEmpty {
                NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.invitations.empty", table: .localizable,
                        fallback: "Bekleyen davet yok"),
                    message: RDLocalization.string("localizable.nova.workspace.invitations.empty.hint", table: .localizable,
                        fallback: "Yeni bir uzman veya yönetici davet edebilirsiniz."))
            } else {
                ForEach(pending, id: \.id) { invitation in
                    NovaCard(padding: 12) {
                        HStack(spacing: 10) {
                            NovaIcon(symbol: "envelope", size: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: invitation.email, style: .bodyStrong)
                                NovaText(text: role(invitation.role), style: .metaQuiet)
                            }
                            Spacer(minLength: 0)
                            Menu {
                                Button { resend(invitation) } label: {
                                    Label(RDLocalization.string("localizable.nova.workspace.invite.resend", table: .localizable,
                                        fallback: "Yeni kod oluştur"), systemImage: "arrow.clockwise")
                                }
                                Button(role: .destructive) { revoke(invitation) } label: {
                                    Label(RDLocalization.string("localizable.nova.workspace.invite.revoke", table: .localizable,
                                        fallback: "Daveti iptal et"), systemImage: "xmark.circle")
                                }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                                .disabled(working)
                        }
                    }
                }
            }
        }
    }

    private var canInvite: Bool {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.contains("@") && clean.contains(".")
    }
    private var expiration: String { ISO8601DateFormatter().string(from: Date().addingTimeInterval(7 * 86_400)) }
    private var defaultReason: String { RDLocalization.string("localizable.nova.workspace.member.reason", table: .localizable, fallback: "Mobil ekip yönetimi") }

    @MainActor private func load() async {
        loading = true; error = nil
        do {
            async let loadedMembers = store.members()
            async let loadedInvitations = store.invitations()
            members = try await loadedMembers
            invitations = try await loadedInvitations
        } catch {
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }

    private func invite() {
        let target = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresAt = pendingExpiration ?? expiration
        pendingExpiration = expiresAt
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "member.invite", components: [target, inviteRole, expiresAt])
        mutationAttempt = attempt
        working = true; error = nil
        Task {
            do {
                latestToken = try await store.invite(mutationID: mutationID, email: target,
                                                     role: inviteRole, expiresAt: expiresAt)
                email = ""; pendingExpiration = nil
                invitations = try await store.invitations()
                celebrate(RDLocalization.string("localizable.nova.workspace.invite.created", table: .localizable,
                    fallback: "Davet oluşturuldu."))
            } catch { failure() }
            working = false
        }
    }

    private func mutate(_ member: IsgWorkspaceMember, action: String,
                        value: String? = nil, reason: String? = nil) {
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "member.\(action)", components: [member.id.uuidString,
            String(member.version), value ?? "", reason ?? ""])
        mutationAttempt = attempt
        working = true; error = nil
        Task {
            do {
                let updated = try await store.mutateMember(mutationID: mutationID, member: member,
                    action: action, value: value, reason: reason)
                if let index = members.firstIndex(where: { $0.id == updated.id }) { members[index] = updated }
                celebrate(RDLocalization.string("localizable.nova.workspace.member.updated", table: .localizable,
                    fallback: "Üye erişimi güncellendi."))
            } catch { failure() }
            working = false
        }
    }

    private func resend(_ invitation: IsgWorkspaceInvitation) {
        let expiresAt = pendingExpiration ?? expiration
        pendingExpiration = expiresAt
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "invitation.resend", components: [invitation.id.uuidString,
            String(invitation.version), expiresAt])
        mutationAttempt = attempt
        working = true; error = nil
        Task {
            do {
                latestToken = try await store.resendInvitation(mutationID: mutationID, invitation: invitation,
                                                               expiresAt: expiresAt)
                pendingExpiration = nil
                invitations = try await store.invitations()
                celebrate(RDLocalization.string("localizable.nova.workspace.invite.renewed", table: .localizable,
                    fallback: "Yeni davet kodu oluşturuldu."))
            } catch { failure() }
            working = false
        }
    }

    private func revoke(_ invitation: IsgWorkspaceInvitation) {
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "invitation.revoke", components: [invitation.id.uuidString,
            String(invitation.version)])
        mutationAttempt = attempt
        working = true; error = nil
        Task {
            do {
                try await store.revokeInvitation(mutationID: mutationID, invitation: invitation)
                invitations.removeAll { $0.id == invitation.id }
                celebrate(RDLocalization.string("localizable.nova.workspace.invite.revoked", table: .localizable,
                    fallback: "Davet iptal edildi."))
            } catch { failure() }
            working = false
        }
    }

    private func failure() {
        error = RDLocalization.string("localizable.nova.workspace.save.failed", table: .localizable,
            fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
    }
    private func role(_ value: String) -> String {
        switch value {
        case "owner": return RDLocalization.string("localizable.nova.workspace.role.owner", table: .localizable, fallback: "OSGB sahibi")
        case "admin": return RDLocalization.string("localizable.nova.workspace.role.admin", table: .localizable, fallback: "OSGB yöneticisi")
        default: return RDLocalization.string("localizable.nova.workspace.role.expert", table: .localizable, fallback: "İSG uzmanı")
        }
    }
    private func status(_ value: String) -> String {
        switch value {
        case "active": return RDLocalization.string("localizable.nova.workspace.member.active", table: .localizable, fallback: "Aktif")
        case "suspended": return RDLocalization.string("localizable.nova.workspace.member.suspended", table: .localizable, fallback: "Askıda")
        default: return RDLocalization.string("localizable.nova.workspace.member.ended", table: .localizable, fallback: "Sona erdi")
        }
    }
}

private struct IsgCompanyEditorRoute: Identifiable {
    let company: IsgWorkspaceCompany?
    let id = UUID()
    let archiveMutationID = UUID()
    static var create: Self { .init(company: nil) }
    static func edit(_ company: IsgWorkspaceCompany) -> Self { .init(company: company) }
}

private struct IsgWorkspaceCompanyEditor: View {
    let company: IsgWorkspaceCompany?
    @ObservedObject var store: IsgWorkspaceStore
    let onClose: () -> Void
    let onSave: (UUID, UUID, IsgWorkspaceCompanyDraft, Set<UUID>, String) async throws -> Void
    let onArchive: ((String) async throws -> Void)?
    @State private var name: String
    @State private var hazard: String
    @State private var sector: String
    @State private var email: String
    @State private var employeeCount: String
    @State private var address: String
    @State private var addResponsible: Bool
    @State private var responsibleName: String
    @State private var responsiblePhone: String
    @State private var responsibleEmail: String
    @State private var expandedSections: Set<String> = ["basic"]
    @State private var experts: [IsgWorkspaceMember] = []
    @State private var selectedExpertIDs: Set<UUID> = []
    @State private var assignmentRole = "support"
    @State private var membersLoading = false
    @State private var reason = ""
    @State private var saving = false
    @State private var error: String?
    @State private var companyAttempt = IsgWorkspaceMutationAttempt()
    @State private var profileAttempt = IsgWorkspaceMutationAttempt()
    @State private var step = 0
    @State private var saved = false
    @Environment(\.novaCelebrate) private var celebrate

    init(company: IsgWorkspaceCompany?, store: IsgWorkspaceStore, onClose: @escaping () -> Void,
         onSave: @escaping (UUID, UUID, IsgWorkspaceCompanyDraft, Set<UUID>, String) async throws -> Void,
         onArchive: ((String) async throws -> Void)?) {
        self.company = company; self.store = store; self.onClose = onClose
        self.onSave = onSave; self.onArchive = onArchive
        _name = State(initialValue: company?.name ?? "")
        _hazard = State(initialValue: company?.hazardClass ?? "medium")
        _sector = State(initialValue: company?.sector ?? "")
        _email = State(initialValue: company?.email ?? "")
        _employeeCount = State(initialValue: company?.declaredEmployeeCount.map(String.init) ?? "")
        _address = State(initialValue: company?.address ?? "")
        let responsible = company?.responsibleName != nil
        _addResponsible = State(initialValue: responsible)
        _responsibleName = State(initialValue: company?.responsibleName ?? "")
        _responsiblePhone = State(initialValue: company?.responsiblePhone ?? "")
        _responsibleEmail = State(initialValue: company?.responsibleEmail ?? "")
    }

    var body: some View {
        Group {
            if saved {
                NovaTaskSuccessView(title: company == nil ? "Firma oluşturuldu" : "Firma güncellendi",
                    message: "Firma bilgileri kaydedildi ve sonraki modül işlemlerinde otomatik kullanılacak.",
                    doneTitle: "Firmalara dön", onDone: onClose)
            } else {
                NovaPageSurface(onEdgeBack: goBack) {
                    VStack(spacing: 0) {
                        NovaTaskHeader(title: company == nil ? "Firma ekle" : "Firmayı düzenle",
                            step: step + 1, total: totalSteps, stepTitle: stepTitle, onClose: goBack)
                            .padding(.horizontal, 18).padding(.top, 10)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                stepContent
                                if let error { NovaTaskErrorSummary(message: error) }
                            }.padding(20).padding(.bottom, 18)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == totalSteps - 1
                                ? (company == nil ? "Firmayı kaydet" : "Değişiklikleri kaydet") : "Devam",
                                primarySymbol: step == totalSteps - 1 ? "checkmark" : "arrow.right",
                                isWorking: saving, canGoBack: true, onBack: goBack, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .task(id: company == nil) {
            guard company == nil else { return }
            membersLoading = true
            do {
                experts = try await store.members(status: "active").filter { $0.isPracticingExpert }
            } catch {
                experts = []
            }
            membersLoading = false
        }
    }

    private var totalSteps: Int { company == nil ? 4 : 3 }
    private var stepTitle: String {
        if step == 0 { return "Temel bilgiler" }
        if step == 1 { return "İletişim ve kapasite" }
        if company == nil && step == 2 { return "Uzman ataması" }
        return "Kontrol ve kaydet"
    }

    @ViewBuilder private var stepContent: some View {
        if step == 0 { basicStep }
        else if step == 1 { contactStep }
        else if company == nil && step == 2 { expertStep }
        else { reviewStep }
    }

    private var basicStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaHelpHint(text: "Firma ve sektör bilgisi bir kez kaydedilir; işyeri ve modül akışlarında yeniden kullanılır.")
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    field("Firma adı *", symbol: "building.2", text: $name)
                    Divider()
                    hazardMenu
                    Divider()
                    field("Sektör *", symbol: "square.grid.2x2", text: $sector)
                }
            }
        }
    }

    private var contactStep: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                field("Firma e-posta", symbol: "envelope", text: $email)
                Divider(); field("Çalışan sayısı", symbol: "person.2", text: $employeeCount)
                Divider(); field("Adres", symbol: "mappin.and.ellipse", text: $address)
                Divider(); Toggle("Sorumlu personel ekle", isOn: $addResponsible)
                if addResponsible {
                    field("Ad soyad *", symbol: "person", text: $responsibleName)
                    field("Telefon *", symbol: "phone", text: $responsiblePhone)
                    field("E-posta *", symbol: "envelope", text: $responsibleEmail)
                    NovaWhyDisclosure {
                        NovaText(text: "Sorumlu kişi firma iletişim bilgisinde gösterilir. Personel kaydı ayrı personel ekranından oluşturulur.", style: .metaQuiet)
                    }
                }
            }
        }
    }

    private var expertStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaHelpHint(text: "Uzman ataması isteğe bağlıdır; firmayı şimdi kaydedip atamayı daha sonra da yapabilirsiniz.")
            if membersLoading { NovaLoadingView(message: "Uzmanlar yükleniyor…") }
            else if experts.isEmpty { NovaEmptyState(title: "Atanabilir uzman yok", message: "Ekip yönetiminden uzman davet ettikten sonra atama yapabilirsiniz.") }
            else {
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Atama rolü", selection: $assignmentRole) {
                            Text("Destek uzmanı").tag("support"); Text("Birincil uzman").tag("primary")
                        }.pickerStyle(.segmented)
                        ForEach(experts, id: \.id) { member in
                            Button { toggleExpert(member.id) } label: {
                                HStack(spacing: 10) {
                                    NovaIcon(symbol: "person.badge.shield.checkmark", size: 17)
                                    NovaText(text: expertLabel(member), style: .body); Spacer(minLength: 0)
                                    Image(systemName: selectedExpertIDs.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(NovaRowPressStyle())
                        }
                    }
                }
            }
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    NovaText(text: "Firma özeti", style: .bodyStrong)
                    NovaText(text: name, style: .cardTitle)
                    NovaText(text: "\(hazardTitle) · \(sector)", style: .metaQuiet)
                    if !address.isEmpty { NovaText(text: address, style: .metaQuiet) }
                    if company == nil { NovaText(text: "\(selectedExpertIDs.count) uzman seçildi", style: .metaQuiet) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if let onArchive {
                NovaWhyDisclosure(label: "Arşivleme") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField(RDLocalization.string("localizable.nova.workspace.archive.reason", table: .localizable,
                            fallback: "Arşivleme gerekçesi"), text: $reason).font(NovaFont.font(.body))
                        NovaButton(label: RDLocalization.string("localizable.nova.workspace.company.archive", table: .localizable,
                            fallback: "Firmayı arşivle"), symbol: "archivebox", variant: .danger,
                            isEnabled: !saving && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { archive(onArchive) }
                    }
                }
            }
        }
    }

    private func goBack() { error = nil; if step > 0 { step -= 1 } else { onClose() } }
    private func advance() {
        error = nil
        if step == 0 && (name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            error = "Firma adı ve sektör zorunludur."; return
        }
        if step == 1 && !canSave { error = "Çalışan sayısı ve sorumlu personel bilgilerini kontrol edin."; return }
        if step < totalSteps - 1 { step += 1 } else { save() }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !sector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              employeeCount.isEmpty || Int(employeeCount) != nil else { return false }
        return !addResponsible || [responsibleName, responsiblePhone, responsibleEmail]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func field(_ title: String, symbol: String, text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            NovaIcon(symbol: symbol, size: 17).frame(width: 22)
            TextField(title, text: text, axis: title == "Adres" ? .vertical : .horizontal)
                .lineLimit(title == "Adres" ? 1...3 : 1...1).font(NovaFont.font(.body))
                .keyboardType(title.contains("e-posta") || title.contains("E-posta") ? .emailAddress :
                              title.contains("Telefon") ? .phonePad : title.contains("sayısı") ? .numberPad : .default)
                .textInputAutocapitalization(title.contains("posta") ? .never : .words)
        }.frame(minHeight: 40)
    }

    private var hazardMenu: some View {
        Menu {
            Button("Az Tehlikeli") { hazard = "low" }
            Button("Tehlikeli") { hazard = "medium" }
            Button("Çok Tehlikeli") { hazard = "high" }
        } label: {
            HStack(spacing: 8) {
                NovaIcon(symbol: "exclamationmark.triangle", size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: "Tehlike sınıfı", style: .metaQuiet)
                    NovaText(text: hazardTitle, style: .body)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .novaControlBackground(cornerRadius: 14)
        }.buttonStyle(NovaRowPressStyle()).frame(maxWidth: .infinity)
            .accessibilityLabel("Tehlike sınıfı, \(hazardTitle)")
    }

    private var hazardTitle: String {
        switch hazard {
        case "low": return "Az Tehlikeli"
        case "high": return "Çok Tehlikeli"
        default: return "Tehlikeli"
        }
    }

    @ViewBuilder private func accordionSection<Content: View>(_ id: String, title: String,
                                                               symbol: String, summary: String,
                                                               @ViewBuilder content: () -> Content) -> some View {
        let isExpanded = expandedSections.contains(id)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedSections.remove(id) } else { expandedSections.insert(id) }
                }
            } label: {
                HStack(spacing: 10) {
                    NovaIcon(symbol: symbol, size: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: title, style: .bodyStrong)
                        if !isExpanded { NovaText(text: summary, style: .metaQuiet).lineLimit(1) }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }.buttonStyle(NovaRowPressStyle())
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) { content() }
                    .padding(.top, 3).padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .background(NovaColorToken.surface.color(in: .light), in: RoundedRectangle(cornerRadius: 20))
    }

    private func toggleExpert(_ id: UUID) {
        if selectedExpertIDs.contains(id) { selectedExpertIDs.remove(id) }
        else { selectedExpertIDs.insert(id) }
    }

    private func expertLabel(_ member: IsgWorkspaceMember) -> String {
        let identity = member.userID ?? member.id
        return "İSG uzmanı · \(identity.uuidString.prefix(8))"
    }

    private func save() {
        guard canSave else { return }
        let draft = IsgWorkspaceCompanyDraft(name: name, hazardClass: hazard, sector: sector, email: email,
            employeeCount: employeeCount.isEmpty ? nil : Int(employeeCount), address: address,
            responsibleName: addResponsible ? responsibleName : "",
            responsiblePhone: addResponsible ? responsiblePhone : "",
            responsibleEmail: addResponsible ? responsibleEmail : "")
        var companyAttempt = companyAttempt
        let companyMutationID = companyAttempt.id(namespace: company == nil ? "company.create" : "company.update",
            components: [name, hazard, company.map { String($0.version) } ?? "0"])
        self.companyAttempt = companyAttempt
        var profileAttempt = profileAttempt
        let profileMutationID = profileAttempt.id(namespace: "company.profile", components: [sector, email,
            employeeCount, address, draft.responsibleName, draft.responsiblePhone, draft.responsibleEmail,
            company?.profileVersion.map(String.init) ?? "0"])
        self.profileAttempt = profileAttempt
        saving = true; error = nil
        Task {
            do {
                try await onSave(companyMutationID, profileMutationID, draft, selectedExpertIDs, assignmentRole)
                celebrate(company == nil ? NovaSuccessMessage.companyCreated : NovaSuccessMessage.companyUpdated)
                saving = false
                saved = true
            } catch {
                self.error = RDLocalization.string("localizable.nova.workspace.save.failed", table: .localizable,
                    fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
                saving = false
            }
        }
    }
    private func archive(_ action: @escaping (String) async throws -> Void) {
        saving = true; error = nil
        Task {
            do {
                try await action(reason)
                celebrate(RDLocalization.string("localizable.nova.workspace.company.archived", table: .localizable,
                    fallback: "Firma arşivlendi."))
            } catch {
                self.error = RDLocalization.string("localizable.nova.workspace.save.failed", table: .localizable,
                    fallback: "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
                saving = false
            }
        }
    }
}

struct NovaPilotRoot: View {
    @ObservedObject private var notebookRelease = NotebookUIRelease.shared
    let identity: NovaSessionIdentity
    var previewOnly = false
    var workspaceLabel: String? = nil
    var onWorkspaceSwitch: (() -> Void)? = nil
    /// Non-nil only for an OSGB expert.  This does not select another panel;
    /// it supplies the same expert root with tenant-scoped reads and writes.
    var workspaceStore: IsgWorkspaceStore? = nil
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller: NovaWorkspaceController
    @State private var navigation: NovaNavigationState
    @State private var showingCreate = false
    @State private var notice: String?
    @State private var listRevision = UUID()
    @State private var overview: [NovaPilotCompanySummary]?
    @State private var overviewFailed = false
    @State private var recentAnalyses: [NovaAnalysisSummary] = []
    @State private var sceneRevalidation = NovaSceneRevalidation()
    /// The account's equipment standing, for the home page's own summary. One
    /// read, and the card says nothing until it answers.
    @State private var equipmentBoard: NovaEquipmentBoard?
    /// The header bell. Computed from the account's own records at read time;
    /// it is never a record of a push that was sent.
    @State private var noticeSource: NovaFollowupPage.Row?
    @State private var trainingNoticeSource: NovaFollowupPage.Row?
    @State private var notices = NovaNoticeFeed.empty
    @State private var noticeRevision = UUID()
    @State private var profileAvatarImage: Image?

    init(identity: NovaSessionIdentity, previewOnly: Bool = false,
         workspaceLabel: String? = nil, onWorkspaceSwitch: (() -> Void)? = nil,
         workspaceStore: IsgWorkspaceStore? = nil) {
        self.identity = identity
        self.previewOnly = previewOnly
        self.workspaceLabel = workspaceLabel
        self.onWorkspaceSwitch = onWorkspaceSwitch
        self.workspaceStore = workspaceStore
        _controller = StateObject(wrappedValue: NovaWorkspaceController(workspaceStore: workspaceStore))
        _navigation = State(initialValue: NovaNavigationState(epoch: UUID().uuidString,
            available: workspaceStore == nil
                ? NovaWorkspaceRole.personnel.destinations
                : NovaWorkspaceRole.osgbExpert.destinations))
    }
    private var overviewKey: String { "\(controller.host.navigation.epoch):\(ready):\(listRevision):\(navigation.selected)" }
    /// The bell reloads when the session, the records or the panel change, and
    /// after every mark.
    private var noticeKey: String { "\(controller.host.navigation.epoch):\(ready):\(listRevision):\(noticeRevision)" }
    private var isWorkspaceExpert: Bool { workspaceStore != nil }
    private var activeCompanies: [NovaPilotCompanySummary]? { ready ? overview?.filter { !$0.is_archived } : nil }
    private var menuAnalysisCount: Int? {
        if let value = workspaceStore?.dashboard?.nonconformities.first { return Int(value) }
        return activeCompanies?.reduce(0) { $0 + ($1.finding_count ?? 0) }
    }
    private var menuProgressCompleted: Int {
        guard let companies = activeCompanies, !companies.isEmpty else { return 0 }
        var completed = 1 // firma bilgileri
        if (menuAnalysisCount ?? 0) > 0 { completed += 1 }
        if (equipmentBoard?.tracked ?? 0) > 0 { completed += 1 }
        if let board = workspaceStore?.dashboard {
            if (board.training.second ?? 0) > 0 { completed += 1 }
            if (board.visits.first ?? 0) > 0 { completed += 1 }
        }
        return min(completed, 8)
    }
    private var menuOverdueCount: Int? {
        if let value = workspaceStore?.dashboard?.nonconformities.second { return Int(value) }
        return equipmentBoard?.count(NovaEquipmentState.overdue)
    }
    private var menuStats: [NovaMenuStat] {
        let upcoming: String
        if let board = workspaceStore?.dashboard {
            let count = (board.deadlines.first ?? 0) + (board.deadlines.second ?? 0)
            upcoming = String(count)
        } else if let equipmentBoard {
            upcoming = String(equipmentBoard.needsAttention)
        } else {
            upcoming = "—"
        }
        let overdue = menuOverdueCount.map { String($0) } ?? "—"
        let analyses = menuAnalysisCount.map { String($0) } ?? "—"
        return [
            .init(id: "upcoming", title: "Yaklaşan İşler", value: upcoming,
                  symbol: "calendar.badge.clock", destination: .periodicChecks),
            .init(id: "overdue", title: "Süresi biten", value: overdue,
                  symbol: "exclamationmark.triangle", destination: .findings),
            .init(id: "analyses", title: "Analiz", value: analyses,
                  symbol: "photo.on.rectangle.angled", destination: .analyses)
        ]
    }
    private var menuNextAction: NovaMenuNextAction? {
        guard let companies = activeCompanies else { return nil }
        if companies.isEmpty {
            return .init(title: "Firma ekle", symbol: "building.2.crop.circle",
                destination: isWorkspaceExpert ? .companies : .newCompany, completed: 0, total: 1)
        }
        if (menuAnalysisCount ?? 0) == 0 {
            return .init(title: "Fotoğraf analiz et", symbol: "camera", destination: .newAnalysis,
                completed: 0, total: 8)
        }
        return .init(title: "Risk analizi ekle", symbol: "shield.lefthalf.filled", destination: .riskAssessments,
            completed: menuProgressCompleted, total: 8)
    }
    private var metrics: [NovaMetricItem] {
        [
            .init(id: "companies", value: activeCompanies.map { String($0.count) } ?? "—", label: "Firmalar", footer: RDLocalization.string("localizable.nova.pilot.main.gate.aktif.pilot.1a73541a", table: .localizable, fallback: "Aktif pilot"), symbol: "building.2", tone: .accent, destination: .companies),
            .init(id: "personnel", value: activeCompanies.map { String($0.reduce(0) { $0 + $1.personnel_count }) } ?? "—", label: "Personel", footer: RDLocalization.string("localizable.nova.pilot.main.gate.aktif.kayit.f0e78da1", table: .localizable, fallback: "Aktif kayıt"), symbol: "person.2", tone: .accent, destination: .companies),
            .init(id: "workplaces", value: activeCompanies.map { String($0.reduce(0) { $0 + $1.workplace_count }) } ?? "—", label: RDLocalization.string("localizable.nova.pilot.main.gate.isyerleri.40b87276", table: .localizable, fallback: "İşyerleri"), footer: RDLocalization.string("localizable.nova.pilot.main.gate.aktif.kayit.c051f94b", table: .localizable, fallback: "Aktif kayıt"), symbol: "building.2", tone: .accent, destination: .companies),
            .init(id: "departments", value: activeCompanies.map { String($0.reduce(0) { $0 + $1.department_count }) } ?? "—", label: "Departman", footer: RDLocalization.string("localizable.nova.pilot.main.gate.aktif.kayit.0f6ad151", table: .localizable, fallback: "Aktif kayıt"), symbol: "square.grid.2x2", tone: .accent, destination: .companies),
            // Equipment whose recorded date has passed or whose last report was
            // negative. A count of records, never a verdict about a company.
            .init(id: "equipment", value: equipmentBoard.map { String($0.needsAttention) } ?? "—",
                  label: RDLocalization.string("localizable.nova.equipment.metric.label", table: .localizable, fallback: "Kontrol"),
                  footer: RDLocalization.string("localizable.nova.equipment.metric.footer", table: .localizable, fallback: "ilgi bekleyen"),
                  symbol: "checkmark.shield", tone: .accent, destination: .periodicChecks)
        ]
    }
    private var name: String { app.profile?.fullName ?? "" }
    private var ready: Bool {
        return !previewOnly && controller.isAvailable && controller.host.identity == identity
    }
    private var writable: Bool {
        ready && (workspaceStore?.selection?.canOperate ?? true)
    }
    private var status: String {
        if previewOnly { return RDLocalization.string("localizable.nova.pilot.main.gate.tasarim.kontrolu.canli.veri.kullanilmiyor.d6b551c8", table: .localizable, fallback: "Tasarım kontrolü · canlı veri kullanılmıyor") }
        if !isWorkspaceExpert && controller.resolving { return RDLocalization.string("localizable.nova.pilot.main.gate.pilot.erisimi.kontrol.ediliyor.6a965311", table: .localizable, fallback: "Pilot erişimi kontrol ediliyor…") }
        if ready, isWorkspaceExpert {
            return workspaceLabel.map { "\($0) · İSG uzmanı" } ?? "OSGB · İSG uzmanı"
        }
        return ready ? RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.yalnizca.pilot.firmalar.eac5bab4", table: .localizable, fallback: "Canlı pilot · yalnızca pilot firmalar") : RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")
    }

    var body: some View {
        NovaExpertShell(notebookAvailable: notebookRelease.enabled, navigation: $navigation, userName: name,
            profileAvatar: profileAvatarImage,
            menuRoleTitle: "İSG Uzmanı",
            menuStats: menuStats, menuNextAction: menuNextAction,
            onInvite: { app.requestProfileDestination(.referral); navigate(.profile) },
            hasUnread: notices.unread > 0, unreadCount: notices.unread,
            notificationItems: notices.rows.map(noticeItem),
            noticeNote: notices.rows.isEmpty ? "" : NovaNoticeWords.dismissNote,
            onReadNotice: { key in Task { await markNotices { try await NovaNoticeService.live().read(identity, key: key) } } },
            onOpenNotice: { key in Task { await openNotice(key) } },
            onDismissNotice: { key in Task { await markNotices { try await NovaNoticeService.live().dismiss(identity, key: key) } } },
            onRestoreNotice: { key in Task { await markNotices { try await NovaNoticeService.live().restore(identity, key: key) } } },
            connectionLabel: status,
            onReadAll: { Task { await markNotices { try await NovaNoticeService.live().readAll(identity) } } },
            onClearNotifications: { Task { await markNotices { try await NovaNoticeService.live().dismissAll(identity) } } },
            onCompanyCreate: isWorkspaceExpert ? nil : { showingCreate = true },
            onDestination: { destination in
                // The company workspace lives below the companies host rather
                // than in NavigationStack's path. Selecting Firmalar from the
                // drawer/tab therefore must clear that feature-local scope.
                if destination == .companies {
                    controller.select(nil)
                }
            },
            onLogout: { app.signOut() }) { destination in
            switch destination {
            case .home:
                VStack(spacing: 0) {
                    NovaDashboardScreen(data: .init(firstName: name.split(separator: " ").first.map(String.init) ?? "",
                        openCount: nil, metrics: metrics, activity: nil,
                        trainingMessage: "Gerçekleşen eğitimler ve katılımcı kayıtları",
                        recentAnalyses: recentAnalyses.map { analysis in
                            NovaRecentAnalysis(id: analysis.id.uuidString.lowercased(),
                                title: NovaAnalysisPresentation.title(analysis.title),
                                companyName: analysis.companyName ?? "Firmasız",
                                createdOn: NovaAnalysisPresentation.dateOnly(analysis.createdOn))
                        },
                        summaryMessage: isWorkspaceExpert
                            ? "Atandığınız firmalardaki toplam güncel kayıtlar."
                            : activeCompanies != nil ? RDLocalization.string("localizable.nova.pilot.main.gate.pilot.firmalarinizin.guncel.kayitlari.01d48da7", table: .localizable, fallback: "Pilot firmalarınızın güncel kayıtları.") : overviewFailed ? RDLocalization.string("localizable.nova.pilot.main.gate.ozet.alinamadi.yenileyerek.tekrar.deneyin.9b6a6077", table: .localizable, fallback: "Özet alınamadı. Yenileyerek tekrar deneyin.") : RDLocalization.string("localizable.nova.pilot.main.gate.ozet.verileri.henuz.bagli.degil.4508136e", table: .localizable, fallback: "Özet verileri henüz bağlı değil.")),
                        onNavigate: navigate,
                        onPhoto: { navigate(.newAnalysis) }, onAssistant: unavailable,
                        trackingIdentity: ready ? identity : nil,
                        trackingCanWrite: controller.canWrite)
                }
            case .statistics:
                if ready {
                    NovaStatisticsScreen(trackingIdentity: identity, trackingCanWrite: controller.canWrite, load: { company, months in
                        try await NovaStatisticsService(identity: identity).load(company: company, months: months)
                    }, onBack: { navigate(.home) }, onNavigate: navigate)
                    .id("\(identity.userID):\(identity.sessionID)")
                } else { statusCard }
            case .companies:
                companies
            case .training, .newTraining:
                Group {
                    NovaTrainingHub(identity: identity, scope: controller.scope, personnel: controller.personnelClient,
                        canWrite: writable, select: controller.select,
                        onBack: { navigate(.home) }, createOnOpen: destination == .newTraining)
                        .id(destination)
                }
            case .findings:
                nonconformities(.board)
            case .analyses:
                nonconformities(.analyses)
            case .newAnalysis:
                nonconformities(.newAnalysis)
            case .newFinding:
                nonconformities(.addFinding)
            case .documentChecklist:
                documents
            case .documents:
                files()
            case .newDocument:
                files(startInAddMode: true)
            case .periodicChecks:
                equipment
            case .riskAssessments:
                risk
            case .checklists:
                checklists
            case .emergencyPlans:
                emergencyPlans
            case .drills:
                drills
            case .ppeHandovers:
                ppe
            case .appointments:
                appointments
            case .katipContracts, .annualWorkPlans, .boardMeetings, .visits, .workPermits, .contractors:
                if ready {
                    NovaPilotProcessGate(identity: identity, kind: processKind(destination), canWrite: writable, onBack: { navigate(.home) })
                        .id(destination)
                } else { statusCard }
            case .newVisit:
                if ready {
                    NovaPilotProcessGate(identity: identity, kind: "site_visit", canWrite: writable,
                        onBack: { navigate(.home) })
                } else { statusCard }
            case .newCompany:
                if isWorkspaceExpert { companies }
                else {
                    companies.onAppear { showingCreate = true }
                }
            case .memory:
                NovaProcessArchive(identity: identity, onBack: { navigate(.home) })
            case .notifications:
                if ready {
                    NovaPilotNoticeGate(identity: identity,
                        onOpen: { target in navigate(target) },
                        onBack: { navigate(.home) })
                } else { statusCard }
            case .reports:
                NovaReportCenter(identity: identity, onBack: { navigate(.home) })
            case .reportArchive:
                NovaProcessArchive(identity: identity, onBack: { navigate(.reports) })
            case .activity:
                ExpertActivityDestination(onClose: { navigate(.home) }, onOpenRecord: openActivityRecord)
            case .notebook, .newNote:
                NotebookDestination(startWithNewNote: destination == .newNote, onClose: { navigate(.home) })
            case .profile:
                NovaPageSurface(onEdgeBack: { navigate(.home) }) {
                    VStack(spacing: 0) {
                        NovaPageHeading(title: "Profil", onBack: { navigate(.home) }).padding(.horizontal, 20)
                        ProfileView()
                    }
                }
            }
        }
        .preferredColorScheme(.light)
        .overlay {
            if controller.resolving && !previewOnly {
                ZStack {
                    NovaColorToken.canvas.color(in: .light).opacity(0.96).ignoresSafeArea()
                    NovaLoadingView(message: "Verileriniz güncelleniyor…")
                }
                .transition(.opacity)
                .zIndex(500)
                .accessibilityAddTraits(.isModal)
            }
        }
        .novaAsyncContent(isLoading: controller.resolving)
        .overlay(alignment: .topLeading) {
            // A container identifier propagates to SwiftUI toolbar/tab descendants.
            // Keep the QA marker separate so each button retains its own identifier.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("nova.pilot.root")
                .allowsHitTesting(false)
        }
        .novaFullScreenCover(isPresented: $showingCreate) {
            NovaPilotCompanyCreateView(identity: identity, service: .live()) { companyID in
                listRevision = UUID()
                controller.select(companyID)
            }
        }
        .novaFullScreenCover(item: $trainingNoticeSource) { source in
            NovaFollowupDestination(identity: identity, row: source, canWrite: writable, onBack: { trainingNoticeSource = nil })
        }
        .novaPopup(item: $noticeSource) { source in
            NovaFollowupDestination(identity: identity, row: source, canWrite: writable, onBack: { noticeSource = nil })
        }
        .alert(RDLocalization.string("localizable.nova.pilot.main.gate.nova.pilot.d20fb7f1", table: .localizable, fallback: "İSGADA pilot"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("Tamam", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .task { if !previewOnly { await controller.observe() } }
        .task(id: app.profile?.avatarURL) { await loadProfileAvatarImage() }
        .task { if !previewOnly { await notebookRelease.refresh() } }
        .onReceive(NetworkMonitor.shared.$isOnline) { online in
            guard !previewOnly else { return }
            if online && scenePhase == .active { ExpertUsagePresence.shared.foreground(workspace: workspaceStore?.selection?.workspaceID) }
            else { Task { await ExpertUsagePresence.shared.background() } }
        }
        .task(id: workspaceStore?.selection?.workspaceID) {
            if !previewOnly, scenePhase == .active {
                ExpertUsagePresence.shared.foreground(workspace: workspaceStore?.selection?.workspaceID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { event in
            if event.object as? UUID == identity.userID { listRevision = UUID() }
        }
        .task(id: overviewKey) {
            guard ready else { return }
            overviewFailed = false
            do { overview = try await loadNovaPilotOverview(identity: identity) }
            catch { if !Task.isCancelled { overviewFailed = true } }
        }
        .task(id: overviewKey) {
            guard ready else { return }
            equipmentBoard = try? await NovaEquipmentCheckService.live().board(identity, query: .init(limit: 1))
        }
        .task(id: "\(overviewKey):recent-analyses") {
            guard ready, !previewOnly else { recentAnalyses = []; return }
            do {
                recentAnalyses = try await NovaAnalysisWorkspace.summaries(
                    identity: identity, method: .fineKinney, limit: 6).rows
            } catch {
                recentAnalyses = []
            }
        }
        .task(id: noticeKey) {
            guard ready, !previewOnly else { return }
            notices = (try? await NovaNoticeService.live().feed(identity)) ?? .empty
        }
        .onChange(of: scenePhase) { phase in
            // Screenshots, permission prompts and Control Center can cause inactive → active.
            if !previewOnly {
                if phase == .active { ExpertUsagePresence.shared.foreground(workspace: workspaceStore?.selection?.workspaceID) }
                else if phase == .background { Task { await ExpertUsagePresence.shared.background() } }
            }
            // They are not a new session and must not destroy a sheet or its draft.
            if sceneRevalidation.update(isBackground: phase == .background, isActive: phase == .active) {
                if !previewOnly {
                    controller.refresh()
                    workspaceStore?.refresh()
                }
            }
        }
        .onChange(of: controller.host.identity) { next in
            if next != identity { showingCreate = false; notice = nil; noticeSource = nil; trainingNoticeSource = nil }
        }
        .modifier(NovaSuccessPresentation(account: identity.userID))
    }

    private func loadProfileAvatarImage() async {
        guard let path = app.profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            profileAvatarImage = nil
            return
        }
        do {
            if let image = try await app.auth.profileAvatarImage(path: path) {
                profileAvatarImage = Image(uiImage: image)
            } else {
                profileAvatarImage = nil
            }
        } catch {
            profileAvatarImage = nil
        }
    }

    private var statusCard: some View {
        NovaCard(padding: 12) {
            HStack(spacing: 8) {
                Image(systemName: ready ? "checkmark.shield" : "lock.shield")
                VStack(alignment: .leading, spacing: 2) {
                    if let workspaceLabel { NovaText(text: workspaceLabel, style: .bodyStrong) }
                    NovaText(text: status, style: .metaQuiet)
                }
                Spacer(minLength: 0)
                if let onWorkspaceSwitch {
                    Button(action: onWorkspaceSwitch) {
                        Image(systemName: "arrow.triangle.2.circlepath").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(RDLocalization.string("localizable.nova.workspace.switch", table: .localizable,
                        fallback: "Çalışma alanını değiştir"))
                }
                if !previewOnly {
                    Button {
                        controller.refresh()
                        workspaceStore?.refresh()
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.pilot.main.gate.pilot.erisimini.tekrar.kontrol.et.bfce533e", table: .localizable, fallback: "Pilot erişimini tekrar kontrol et"))
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 10)
    }

    /// Evrak takibi reads one company at a time and says which one.
    @ViewBuilder private var documents: some View {
        if ready {
            NovaPilotDocumentGate(identity: identity, scope: controller.scope, canWrite: writable,
                select: { controller.select($0) }, currentScope: { controller.scope },
                onBack: { navigate(.home) }, onCompanies: { navigate(.companies) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    /// Periyodik Kontroller reads the whole account and narrows to one company
    /// when the expert picks one.
    @ViewBuilder private var risk: some View {
        if ready {
            NovaPilotRiskGate(identity: identity, canWrite: writable, showBackButton: true,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var checklists: some View {
        if ready {
            NovaPilotChecklistGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var emergencyPlans: some View {
        if ready {
            NovaPilotEmergencyGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var drills: some View {
        if ready {
            NovaPilotDrillGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    private func processKind(_ destination: NovaDestination) -> String {
        switch destination {
        case .katipContracts: return "katip_contract"
        case .annualWorkPlans: return "annual_work_plan"
        case .boardMeetings: return "board"
        case .visits: return "site_visit"
        case .workPermits: return "work_permit"
        default: return "contractor"
        }
    }

    @ViewBuilder private var ppe: some View {
        if ready {
            NovaPilotPPEGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var appointments: some View {
        if ready {
            NovaPilotAppointmentGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var katip: some View {
        if ready {
            NovaPilotKatipGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var equipment: some View {
        if ready {
            NovaPilotEquipmentGate(identity: identity, canWrite: writable,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    /// Diğer Dosyalar reads the whole account and narrows to one company when
    /// the expert picks one.
    @ViewBuilder private func files(startInAddMode: Bool = false) -> some View {
        if ready {
            NovaPilotFileGate(identity: identity, canWrite: writable,
                startInAddMode: startInAddMode, onBack: { navigate(.home) })
                .id(startInAddMode)
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    /// Each menu entry lands on exactly one page; the surface says which.
    @ViewBuilder private func nonconformities(_ surface: NovaFindingsSurface) -> some View {
        if ready {
            NovaPilotFindingsGate(identity: identity, scope: controller.scope, canWrite: controller.canWrite,
                select: controller.select, currentScope: { controller.scope }, surface: surface,
                onNavigate: navigate, onCompanies: { navigate(.companies) }, onHome: { navigate(.home) })
                .id("\(controller.host.navigation.epoch):\(surface)")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NovaText(text: NovaDestination.findings.title, style: .screenTitle)
                    statusCard
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.nonconformity.unavailable", table: .localizable,
                        fallback: "Uygunsuzluk modülü için canlı pilot erişimi gerekiyor."))
                    NovaButton(label: RDLocalization.string("localizable.nova.pilot.main.gate.ana.sayfaya.don.0eb70db3", table: .localizable, fallback: "Ana sayfaya dön"), symbol: "chevron.left", variant: .surface) { navigate(.home) }
                }.padding(20)
            }
        }
    }

    @ViewBuilder private var companies: some View {
        if ready, let scope = controller.scope {
            NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma",
                canWrite: controller.canWrite, canWritePersonnel: controller.canWritePersonnel,
                personnel: controller.personnelClient, directory: controller.directoryClient,
                onBack: { controller.select(nil) },
                loadSummary: { try await loadNovaPilotOverview(identity: identity, companyID: scope.companyID).first },
                loadNonconformities: {
                    try await NovaNonconformityService.live(currentScope: { controller.scope }).list(scope)
                },
                onOpenNonconformities: { navigate(.findings) })
                .id(scope.epoch)
        } else if ready && controller.selectedCompanyID == nil {
            if let workspaceStore {
                // Assigned OSGB companies already live in the workspace store.
                // Reading the personal-owner list here started a second request
                // that could be cancelled while navigating Home -> Companies,
                // leaving the visible list in an idle/loading state.
                NovaCompaniesScreen(
                    companies: workspaceStore.companies.map {
                        NovaCompanyItem(id: $0.id.uuidString.lowercased(), name: $0.name,
                            detail: [IsgWorkspaceDisplayText.value($0.hazardClass), $0.sector]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    },
                    isLoading: workspaceStore.phase == .loading && workspaceStore.companies.isEmpty,
                    error: workspaceStore.phase == .failed
                        ? "Atanmış firmalar yenilenemedi. Bağlantınızı kontrol edip tekrar deneyin."
                        : nil,
                    isOwnedList: false,
                    onSelect: { raw in
                        guard let companyID = UUID(uuidString: raw) else { return }
                        if workspaceStore.selectedCompanyID != companyID {
                            workspaceStore.selectCompany(companyID)
                        }
                        controller.select(companyID)
                    },
                    onBack: { navigate(.home) },
                    onRetry: { workspaceStore.refresh() })
                    .id("workspace-companies:\(workspaceStore.selection?.workspaceID.uuidString ?? "none")")
            } else {
                VStack(spacing: 0) {
                    NovaCompanyDestination(host: Binding(get: { controller.host }, set: { _ in }),
                        loadCompanies: { try await loadNovaPilotCompanies(identity: identity, includeArchived: $0) },
                        includeArchived: true, onSelect: controller.select,
                        onBack: { navigate(.home) }, onCreate: { showingCreate = true })
                        .id(listRevision)
                }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NovaText(text: "Firmalar", style: .screenTitle)
                    statusCard
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.yeni.tasarim.hazir.firma.islemleri.icin.canli.pi.92495baa", table: .localizable, fallback: "Yeni tasarım hazır. Firma işlemleri için canlı pilot servisinin ve hesabınıza ait erişimin açılması gerekiyor. Mevcut firmalarınız otomatik taşınmaz."))
                    NovaButton(label: "Tekrar kontrol et", symbol: "arrow.clockwise", variant: .surface) { controller.select(nil) }
                        .disabled(previewOnly || controller.resolving)
                    NovaButton(label: RDLocalization.string("localizable.nova.pilot.main.gate.ana.sayfaya.don.0eb70db3", table: .localizable, fallback: "Ana sayfaya dön"), symbol: "chevron.left", variant: .surface) { navigate(.home) }
                }.padding(20)
            }
        }
    }

    /// One notice as the shell draws it. The kind and the company are the
    /// detail line; the badge says how late it is in words.
    private func noticeItem(_ entry: NovaNoticeEntry) -> NovaNotice {
        NovaNotice(id: entry.key, title: entry.title,
            detail: [entry.kind.title, entry.companyName].compactMap { $0 }.joined(separator: " · "),
            badge: noticeBadge(entry), symbol: entry.kind.symbol, tone: entry.severity.tone,
            unread: entry.unread, dismissed: entry.dismissed, destination: entry.destination)
    }

    private func openNotice(_ key: String) async {
        guard ready, let entry = notices.rows.first(where: { $0.id == key }),
              let company = entry.companyID, let record = entry.recordID else { return }
        let owner = identity
        if entry.kind == .training {
            do {
                let page = try await NovaFollowupService(identity: owner).load(company: company, query: String(entry.title.prefix(100)))
                guard ready, identity == owner else { return }
                if let source = page.rows.first(where: { $0.record_id == record }) { trainingNoticeSource = source }
                else { navigate(entry.destination) }
            } catch { if identity == owner { notice = "Bildirim kaydı açılamadı. Yeniden deneyin." } }
        } else {
            noticeSource = .init(kind: entry.kind == .drill ? "completed_drill" : entry.kind.rawValue, company_id: company,
                company_name: entry.companyName ?? "", record_id: record, source_id: record, title: entry.title,
                due_on: entry.dueOn, status: entry.severity == .overdue ? "expired" : "soon")
        }
    }

    private func openActivityRecord(_ detail: BusinessActivityDetail, companyOnly: Bool) {
        guard let company = detail.link_company_id else { return }
        guard detail.link_workspace_id == workspaceStore?.selection?.workspaceID else {
            notice = "Bu kayıt başka bir çalışma alanına ait. Önce ilgili çalışma alanına geçin."
            return
        }
        if !companyOnly, let record = detail.entity_id,
           let kind = ["drill": "completed_drill", "certificate": "personnel_certificate",
                       "contract": "katip_contract", "visit": "site_visit", "board": "board",
                       "risk": "risk_assessment", "equipment": "equipment", "emergency": "emergency_plan",
                       "assignment": "appointment", "training_session": "training"][detail.entity_type] {
            noticeSource = .init(kind: kind, company_id: company, company_name: "", record_id: record,
                source_id: record, title: BusinessActivityItem.title(action: detail.action), due_on: nil, status: "active")
        } else {
            controller.select(company)
            navigate(companyOnly ? .companies : ["nonconformity": .findings, "training": .training,
                "file": .documents, "checklist": .checklists, "ppe": .ppeHandovers,
                "permit": .workPermits, "plan": .annualWorkPlans][detail.entity_type] ?? .companies)
        }
    }

    private func noticeBadge(_ entry: NovaNoticeEntry) -> String {
        if entry.severity == .overdue {
            return String(format: RDLocalization.string("localizable.nova.notice.badge.overdue",
                table: .localizable, fallback: "%d gün geçti"), -entry.days)
        }
        if entry.days == 0 {
            return RDLocalization.string("localizable.nova.notice.badge.today", table: .localizable,
                fallback: "bugün")
        }
        return String(format: RDLocalization.string("localizable.nova.notice.badge.soon",
            table: .localizable, fallback: "%d gün"), entry.days)
    }

    /// A mark is never applied locally: the server states the counts, and the
    /// bell asks again.
    private func markNotices(_ work: @escaping () async throws -> Void) async {
        do { try await work() } catch { }
        noticeRevision = UUID()
    }

    private func navigate(_ destination: NovaDestination) {
        guard navigation.canOpen(destination) else { unavailable(); return }
        navigation.apply(.navigate(destination), from: navigation.epoch)
    }
    private func unavailable() { notice = RDLocalization.string("localizable.nova.pilot.main.gate.bu.modul.hazirlaniyor.bu.build.de.henuz.canli.is.cdb9ea95", table: .localizable, fallback: "Bu modül hazırlanıyor. Bu build’de henüz canlı işlem yapmıyor.") }
}
