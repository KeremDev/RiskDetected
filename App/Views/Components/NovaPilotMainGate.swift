import SwiftUI
import PhotosUI

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
            if choosing || store.phase == .choosing || (store.phase == .failed && !store.contexts.isEmpty) {
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
                        .id("expert:\(identity.userID):\(selectedContext?.workspaceID.uuidString ?? "none")")
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
                        }.buttonStyle(.plain)
                            .accessibilityLabel(RDLocalization.string("localizable.nova.workspace.refresh", table: .localizable,
                                fallback: "Çalışma alanlarını yenile"))
                    }
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.workspace.choose.hint", table: .localizable,
                        fallback: "Kişisel kayıtlarınız ile yetkili olduğunuz OSGB alanları birbirinden ayrı tutulur."))
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
                    ForEach(store.contexts, id: \.workspaceID) { context in
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
                                        NovaText(text: context.kind == "osgb" ? role(context.membership.role) :
                                            RDLocalization.string("localizable.nova.workspace.personal", table: .localizable,
                                                fallback: "Kişisel çalışma alanı"), style: .metaQuiet)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                }.frame(maxWidth: .infinity, minHeight: 52)
                            }
                        }.buttonStyle(.plain)
                    }
                }.padding(18)
            }
        }
        .preferredColorScheme(.light)
        .novaFullScreenCover(item: $accessRoute) { route in
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
    @State private var navigation = NovaNavigationState(epoch: UUID().uuidString,
        // Tenant experts get the complete operational surface. Company
        // creation is manager-only and is exposed through the manager
        // callback actions rather than a navigable expert route.
        available: NovaWorkspaceRole.osgbExpert.destinations)
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
    @State private var expertDashboard: IsgWorkspaceDashboard?
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

    var body: some View {
        NovaExpertShell(navigation: $navigation, userName: app.profile?.fullName ?? "",
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
            case .statistics: statistics
            case .companies: companies
            case .reports, .reportArchive: reportCenter
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
        .task(id: companyTaskKey) {
            guard let companyWorkspaceID, store.phase == .ready,
                  store.selectedCompanyID == companyWorkspaceID else { return }
            companyPersonnel = try? await store.personnelMetrics(companyID: companyWorkspaceID)
        }
        .novaFullScreenCover(item: $editor) { route in
            NovaPopup {
                IsgWorkspaceCompanyEditor(company: route.company, store: store,
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
                        editor = nil
                    },
                    onArchive: route.company.map { company in
                        { reason in
                            try await store.archiveCompany(mutationID: route.archiveMutationID, companyID: company.id,
                                expectedVersion: company.version, reason: reason)
                            editor = nil
                        }
                    })
            }
        }
        .novaFullScreenCover(isPresented: $showingMembers) {
            NovaPopup { IsgWorkspaceMemberManagement(store: store) }
        }
        .novaFullScreenCover(isPresented: $showingAssignments) {
            if let company = selectedCompany {
                NovaPopup { IsgWorkspaceAssignmentManagement(store: store, company: company) }
            }
        }
        .modifier(NovaSuccessPresentation(account: identity.userID))
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
            summaryMessage: context.map { isExpert
                ? "Atandığınız firmalardaki toplam güncel kayıtlar."
                : "\($0.name) çalışma alanının güncel kayıtları."
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
                    }.buttonStyle(.plain)
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
                    }.buttonStyle(.plain)
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
                        NovaText(text: "OSGB çalışma alanını bugün tek yerden yönetin.", style: .metaQuiet)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workspaceHeading(title: "Rapor Merkezi")
                NovaHelpHint(text: "OSGB çalışma alanındaki analiz ve operasyon çıktılarını tek yerden açın.")
                NovaCard(padding: 14) {
                    Button { navigate(.analyses) } label: {
                        HStack(spacing: 10) {
                            NovaIcon(symbol: "chart.doc", size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: "Analiz raporları", style: .bodyStrong)
                                NovaText(text: "Risk analizi çıktılarınızı inceleyin ve dışa aktarın.", style: .metaQuiet)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                NovaCard(padding: 14) {
                    Button { navigate(.documents) } label: {
                        HStack(spacing: 10) {
                            NovaIcon(symbol: "doc.text", size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: "Firma dokümanları", style: .bodyStrong)
                                NovaText(text: "Dosya ve geçerlilik kayıtlarını yönetin.", style: .metaQuiet)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
        }
    }

    private var statistics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPageHeading(title: NovaDestination.statistics.title, onBack: { navigate(.home) })
                NovaHelpHint(text: "OSGB çalışma alanındaki firma, uzman ve operasyon göstergeleri.")
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
                    }.buttonStyle(.plain).disabled(selectedCompany == nil)
                }
            }.padding(16).padding(.bottom, novaTabBarInset)
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
                    }.buttonStyle(.plain).disabled(selectedCompany == nil)
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
                }.buttonStyle(.plain).disabled(selectedCompany == nil)
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
                        detail: companySummary(company))
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
            VStack(alignment: .leading, spacing: 12) {
                NovaPageHeading(title: "Firma Detayı", onBack: {
                    companyWorkspaceID = nil
                    companyWorkspaceDomain = nil
                    companyWorkspaceAnalyses = false
                })
                NovaCard(padding: 14) {
                    HStack(spacing: 11) {
                        NovaIcon(symbol: "building.2", size: 22)
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: company.name, style: .cardTitle)
                            NovaText(text: companySummary(company), style: .metaQuiet)
                        }
                        Spacer(minLength: 0)
                        if canManageCompanies {
                            Button { editor = .edit(company) } label: {
                                Image(systemName: "pencil").frame(width: 44, height: 44)
                            }.buttonStyle(.plain).accessibilityLabel("Firmayı düzenle")
                        }
                    }
                }
                if store.phase == .loading || store.selectedCompanyID != company.id {
                    NovaLoadingView(message: "Firma çalışma alanı hazırlanıyor…")
                } else {
                    if let companyPersonnel { personnelGrid(companyPersonnel) }
                    NovaCard(padding: 12) {
                        Button { showingSearch = true } label: {
                            HStack(spacing: 10) {
                                NovaIcon(symbol: "magnifyingglass", size: 19)
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: "Firma kayıtlarında ara", style: .bodyStrong)
                                    NovaText(text: "Personel, uygunsuzluk, ekipman ve dosyalarda arayın.", style: .metaQuiet)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    companyModuleGrid
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
        }
    }

    private var companyModuleGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: "Firma işlemleri", style: .sectionTitle)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(IsgWorkspaceDomain.allCases, id: \.self) { item in
                    Button { companyWorkspaceDomain = item } label: {
                        NovaCard(padding: 12) {
                            HStack(spacing: 8) {
                                NovaIcon(symbol: item.symbol, size: 18)
                                NovaText(text: item.title, style: .bodyStrong)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain)
                }
                Button { companyWorkspaceAnalyses = true } label: {
                    NovaCard(padding: 12) {
                        HStack(spacing: 8) {
                            NovaIcon(symbol: NovaDestination.analyses.symbol, size: 18)
                            NovaText(text: NovaDestination.analyses.title, style: .bodyStrong)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }
                }.buttonStyle(.plain)
            }
        }
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
        if let company = selectedCompany {
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
            }.buttonStyle(.plain)
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
                }.buttonStyle(.plain)
                if canManageCompanies {
                    Button { editor = .edit(company) } label: {
                        Image(systemName: "pencil").frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
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
    private func symbol(_ kind: String) -> String {
        switch kind { case "employee": return "person"; case "equipment": return "shippingbox"; case "training": return "graduationcap"; case "file": return "doc"; default: return "checklist" }
    }
}

private struct IsgWorkspaceMemberManagement: View {
    @ObservedObject var store: IsgWorkspaceStore
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
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
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
    @Environment(\.novaCelebrate) private var celebrate

    init(company: IsgWorkspaceCompany?, store: IsgWorkspaceStore,
         onSave: @escaping (UUID, UUID, IsgWorkspaceCompanyDraft, Set<UUID>, String) async throws -> Void,
         onArchive: ((String) async throws -> Void)?) {
        self.company = company; self.store = store; self.onSave = onSave; self.onArchive = onArchive
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NovaPopupHeading(text: company == nil
                    ? RDLocalization.string("localizable.nova.navigation.firma.ekle.b4073323", table: .localizable, fallback: "Firma Ekle")
                    : RDLocalization.string("localizable.nova.workspace.company.edit", table: .localizable, fallback: "Firmayı düzenle"),
                    symbol: "building.2", subtitle: "Firma bilgileri OSGB çalışma alanındaki tüm modüllerde kullanılır.")
                accordionSection("basic", title: "Temel bilgiler", symbol: "building.2",
                                 summary: name.isEmpty ? "Firma adı, tehlike sınıfı ve sektör" : name) {
                    field("Firma adı *", symbol: "building.2", text: $name)
                    HStack(spacing: 8) {
                        hazardMenu
                        field("Sektör *", symbol: "square.grid.2x2", text: $sector)
                    }
                }
                accordionSection("osgb", title: "OSGB bilgileri", symbol: "checkmark.seal",
                                 summary: "Sicil ve yetki alanları için hazır bölüm") {
                    NovaHelpHint(text: "OSGB sicil numarası, yetki belgesi ve sorumlu uzman alanları bu bölümde tutulacak.")
                    HStack(spacing: 8) {
                        field("OSGB sicil no", symbol: "number", text: .constant(""))
                            .disabled(true).opacity(0.52)
                        NovaStatusPill(label: "Yakında", status: .neutral)
                    }
                }
                accordionSection("contact", title: "İletişim ve kapasite", symbol: "person.2",
                                 summary: "İsteğe bağlı iletişim ve çalışan bilgileri") {
                    field("Firma e-posta", symbol: "envelope", text: $email)
                    field("Çalışan sayısı", symbol: "person.2", text: $employeeCount)
                    field("Adres", symbol: "mappin.and.ellipse", text: $address)
                    Toggle("Sorumlu personel ekle", isOn: $addResponsible)
                    if addResponsible {
                        field("Ad soyad *", symbol: "person", text: $responsibleName)
                        field("Telefon *", symbol: "phone", text: $responsiblePhone)
                        field("E-posta *", symbol: "envelope", text: $responsibleEmail)
                        NovaText(text: "Sorumlu kişi firma iletişim bilgisinde gösterilir. Personel kaydı ayrı personel ekranından oluşturulur.", style: .metaQuiet)
                    }
                }
                if company == nil {
                    accordionSection("experts", title: "Uzman ataması", symbol: "person.2.badge.gearshape",
                                     summary: selectedExpertIDs.isEmpty ? "İsteğe bağlı hızlı atama" : "\(selectedExpertIDs.count) uzman seçildi") {
                        if membersLoading {
                            NovaLoadingView(message: "Uzmanlar yükleniyor…")
                        } else if experts.isEmpty {
                            NovaHelpHint(text: "Önce ekip yönetiminden aktif bir İSG uzmanı davet edin.")
                        } else {
                            Picker("Atama rolü", selection: $assignmentRole) {
                                Text("Destek uzmanı").tag("support")
                                Text("Birincil uzman").tag("primary")
                            }.pickerStyle(.segmented)
                            ForEach(experts, id: \.id) { member in
                                Button { toggleExpert(member.id) } label: {
                                    HStack(spacing: 10) {
                                        NovaIcon(symbol: "person.badge.shield.checkmark", size: 17)
                                        NovaText(text: expertLabel(member), style: .body)
                                        Spacer(minLength: 0)
                                        Image(systemName: selectedExpertIDs.contains(member.id) ? "checkmark.circle.fill" : "circle")
                                    }.frame(minHeight: 42).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let error { NovaHelpHint(text: error) }
                NovaButton(label: saving
                    ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…")
                    : company == nil ? "Firmayı kaydet" : "Değişiklikleri kaydet",
                    symbol: saving ? "hourglass" : "checkmark", isEnabled: canSave && !saving) { save() }
                if let onArchive {
                    NovaCard(padding: 12) {
                        TextField(RDLocalization.string("localizable.nova.workspace.archive.reason", table: .localizable,
                            fallback: "Arşivleme gerekçesi"), text: $reason).font(NovaFont.font(.body))
                    }
                    NovaButton(label: RDLocalization.string("localizable.nova.workspace.company.archive", table: .localizable,
                        fallback: "Firmayı arşivle"), symbol: "archivebox", variant: .danger,
                        isEnabled: !saving && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { archive(onArchive) }
                }
            }.padding(18).novaPopupContentSize()
        }
        .scrollDismissesKeyboard(.interactively)
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
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
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
            }.buttonStyle(.plain)
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
    let identity: NovaSessionIdentity
    var previewOnly = false
    var workspaceLabel: String? = nil
    var onWorkspaceSwitch: (() -> Void)? = nil
    /// Non-nil only for an OSGB expert.  This does not select another panel;
    /// it supplies the same expert root with tenant-scoped reads and writes.
    var workspaceStore: IsgWorkspaceStore? = nil
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = NovaWorkspaceController()
    @State private var navigation: NovaNavigationState
    @State private var showingCreate = false
    @State private var notice: String?
    @State private var listRevision = UUID()
    @State private var overview: [NovaPilotCompanySummary]?
    @State private var overviewFailed = false
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
    @State private var workspaceRevision = UUID()
    @State private var workspaceDashboard: IsgWorkspaceDashboard?
    @State private var workspacePersonnel: IsgPersonnelMetrics?
    @State private var workspaceCompanyID: UUID?

    init(identity: NovaSessionIdentity, previewOnly: Bool = false,
         workspaceLabel: String? = nil, onWorkspaceSwitch: (() -> Void)? = nil,
         workspaceStore: IsgWorkspaceStore? = nil) {
        self.identity = identity
        self.previewOnly = previewOnly
        self.workspaceLabel = workspaceLabel
        self.onWorkspaceSwitch = onWorkspaceSwitch
        self.workspaceStore = workspaceStore
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
    private var activeCompanies: [NovaPilotCompanySummary]? { ready && !isWorkspaceExpert ? overview?.filter { !$0.is_archived } : nil }
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
    private var dashboardMetrics: [NovaMetricItem] {
        guard isWorkspaceExpert else { return metrics }
        let board = workspaceDashboard
        return [
            .init(id: "companies", value: board?.companies.first.map(String.init) ?? "—",
                  label: "Firmalar", footer: "Atanmış", symbol: "building.2", tone: .accent,
                  destination: .companies),
            .init(id: "personnel", value: workspacePersonnel.map { String($0.employees.active) } ?? "—",
                  label: "Personel", footer: "Toplam", symbol: "person.2", tone: .accent,
                  destination: .companies),
            .init(id: "open", value: board?.nonconformities.first.map(String.init) ?? "—",
                  label: "Açık uygunsuzluk", footer: "Tüm firmalar", symbol: "checklist", tone: .accent,
                  destination: .findings),
            .init(id: "overdue", value: board?.nonconformities.second.map(String.init) ?? "—",
                  label: "Süresi geçen", footer: "Tüm firmalar", symbol: "exclamationmark.triangle", tone: .accent,
                  destination: .findings),
            .init(id: "training", value: board?.training.second.map(String.init) ?? "—",
                  label: "Tamamlanan eğitim", footer: "Toplam", symbol: "graduationcap", tone: .accent,
                  destination: .training),
            .init(id: "deadlines", value: board.map { String(($0.deadlines.first ?? 0) + ($0.deadlines.second ?? 0)) } ?? "—",
                  label: "Yaklaşan kontroller", footer: "Tüm firmalar", symbol: "calendar.badge.clock", tone: .accent,
                  destination: .periodicChecks)
        ]
    }
    private var workspaceTaskKey: String {
        let companyIDs = workspaceStore?.companies.map(\.id.uuidString).joined(separator: ",") ?? "none"
        return "\(workspaceStore?.selection?.workspaceID.uuidString ?? "none"):\(String(describing: workspaceStore?.phase)):\(companyIDs):\(workspaceRevision)"
    }

    private var name: String { app.profile?.fullName ?? "" }
    private var ready: Bool {
        if let workspaceStore { return !previewOnly && workspaceStore.phase == .ready }
        return !previewOnly && controller.isAvailable && controller.host.identity == identity
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
        NovaExpertShell(navigation: $navigation, userName: name,
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
                    if isWorkspaceExpert { workspaceCompanyID = nil }
                    else { controller.select(nil) }
                }
            },
            onLogout: { app.signOut() }) { destination in
            switch destination {
            case .home:
                VStack(spacing: 0) {
                    statusCard
                    NovaDashboardScreen(data: .init(firstName: name.split(separator: " ").first.map(String.init) ?? "",
                        openCount: nil, metrics: dashboardMetrics, activity: nil,
                        trainingMessage: "Gerçekleşen eğitimler ve katılımcı kayıtları",
                        summaryMessage: isWorkspaceExpert
                            ? "Atandığınız firmalardaki toplam güncel kayıtlar."
                            : activeCompanies != nil ? RDLocalization.string("localizable.nova.pilot.main.gate.pilot.firmalarinizin.guncel.kayitlari.01d48da7", table: .localizable, fallback: "Pilot firmalarınızın güncel kayıtları.") : overviewFailed ? RDLocalization.string("localizable.nova.pilot.main.gate.ozet.alinamadi.yenileyerek.tekrar.deneyin.9b6a6077", table: .localizable, fallback: "Özet alınamadı. Yenileyerek tekrar deneyin.") : RDLocalization.string("localizable.nova.pilot.main.gate.ozet.verileri.henuz.bagli.degil.4508136e", table: .localizable, fallback: "Özet verileri henüz bağlı değil.")),
                        onNavigate: navigate,
                        onPhoto: { navigate(.newAnalysis) }, onAssistant: unavailable,
                        trackingIdentity: ready && !isWorkspaceExpert ? identity : nil,
                        trackingCanWrite: !isWorkspaceExpert && controller.canWrite)
                }
            case .statistics:
                if let workspaceStore {
                    NovaWorkspaceExpertStatisticsScreen(store: workspaceStore,
                        dashboard: workspaceDashboard, personnel: workspacePersonnel,
                        onBack: { navigate(.home) }, onNavigate: navigate)
                } else if ready {
                    NovaStatisticsScreen(trackingIdentity: identity, trackingCanWrite: controller.canWrite, load: { company, months in
                        try await NovaStatisticsService(identity: identity).load(company: company, months: months)
                    }, onBack: { navigate(.home) }, onNavigate: navigate)
                    .id("\(identity.userID):\(identity.sessionID)")
                } else { statusCard }
            case .companies:
                companies
            case .training, .newTraining:
                if let workspaceStore {
                    workspaceDomain(workspaceStore, .training, startInAddMode: destination == .newTraining)
                } else {
                    NovaTrainingHub(identity: identity, scope: controller.scope, personnel: controller.personnelClient,
                        canWrite: ready, select: controller.select,
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
                if let workspaceStore { workspaceDomain(workspaceStore, .files) } else { documents }
            case .documents:
                if let workspaceStore { workspaceDomain(workspaceStore, .files) } else { files() }
            case .newDocument:
                if let workspaceStore { workspaceDomain(workspaceStore, .files, startInAddMode: true) }
                else { files(startInAddMode: true) }
            case .periodicChecks:
                if let workspaceStore { workspaceDomain(workspaceStore, .equipment) } else { equipment }
            case .riskAssessments:
                if let workspaceStore { workspaceDomain(workspaceStore, .risk) } else { risk }
            case .checklists:
                if let workspaceStore { workspaceDomain(workspaceStore, .checklist) } else { checklists }
            case .emergencyPlans:
                if let workspaceStore { workspaceDomain(workspaceStore, .emergencyPlan) } else { emergencyPlans }
            case .drills:
                if let workspaceStore { workspaceDomain(workspaceStore, .drill) } else { drills }
            case .ppeHandovers:
                if let workspaceStore { workspaceDomain(workspaceStore, .ppe) } else { ppe }
            case .appointments:
                if let workspaceStore { workspaceDomain(workspaceStore, .appointment) } else { appointments }
            case .katipContracts, .annualWorkPlans, .boardMeetings, .visits, .workPermits, .contractors:
                if let workspaceStore, let domain = workspaceDomain(for: destination) {
                    workspaceDomain(workspaceStore, domain)
                } else if ready {
                    NovaPilotProcessGate(identity: identity, kind: processKind(destination), canWrite: ready, onBack: { navigate(.home) })
                        .id(destination)
                } else { statusCard }
            case .newVisit:
                if let workspaceStore {
                    workspaceDomain(workspaceStore, .visit, startInAddMode: true)
                } else if ready {
                    NovaPilotProcessGate(identity: identity, kind: "site_visit", canWrite: ready,
                        onBack: { navigate(.home) })
                } else { statusCard }
            case .newCompany:
                if isWorkspaceExpert { companies }
                else {
                    companies.onAppear { showingCreate = true }
                }
            case .memory:
                if let workspaceStore {
                    IsgWorkspaceChangeScreen(store: workspaceStore,
                        companyName: workspaceSelectedCompany(in: workspaceStore)?.name,
                        onBack: { navigate(.home) })
                } else { NovaProcessArchive(identity: identity, onBack: { navigate(.home) }) }
            case .notifications:
                if let workspaceStore {
                    IsgWorkspaceChangeScreen(store: workspaceStore,
                        companyName: workspaceSelectedCompany(in: workspaceStore)?.name,
                        onBack: { navigate(.home) })
                } else if ready {
                    NovaPilotNoticeGate(identity: identity,
                        onOpen: { target in navigate(target) },
                        onBack: { navigate(.home) })
                } else { statusCard }
            case .reports, .reportArchive:
                if let workspaceStore { workspaceReportCenter(workspaceStore) }
                else { NovaProcessArchive(identity: identity, onBack: { navigate(.home) }) }
            case .profile:
                NovaPageSurface(onEdgeBack: { navigate(.home) }) {
                    VStack(spacing: 0) {
                        NovaPageHeading(title: "Profil", onBack: { navigate(.home) }).padding(.horizontal, 20)
                        ProfileView()
                    }
                }
            default:
                NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.bu.modul.hazirlaniyor.henuz.canli.islem.yapmiyor.b652656a", table: .localizable, fallback: "Bu modül hazırlanıyor; henüz canlı işlem yapmıyor.")).padding(20)
            }
        }
        .preferredColorScheme(.light)
        .overlay {
            if !isWorkspaceExpert && controller.resolving && !previewOnly {
                ZStack {
                    NovaColorToken.canvas.color(in: .light).opacity(0.96).ignoresSafeArea()
                    NovaLoadingView(message: "Verileriniz güncelleniyor…")
                }
                .transition(.opacity)
                .zIndex(500)
                .accessibilityAddTraits(.isModal)
            }
        }
        .overlay(alignment: .topLeading) {
            // A container identifier propagates to SwiftUI toolbar/tab descendants.
            // Keep the QA marker separate so each button retains its own identifier.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("nova.pilot.root")
                .allowsHitTesting(false)
        }
        .novaFullScreenCover(isPresented: $showingCreate) {
            NovaPopup {
            NovaPilotCompanyCreateView(identity: identity, service: .live()) { companyID in
                listRevision = UUID()
                controller.select(companyID)
            }
            }
        }
        .novaFullScreenCover(item: $trainingNoticeSource) { source in
            NovaFollowupDestination(identity: identity, row: source, canWrite: ready, onBack: { trainingNoticeSource = nil })
        }
        .novaPopup(item: $noticeSource) { source in
            NovaFollowupDestination(identity: identity, row: source, canWrite: ready, onBack: { noticeSource = nil })
        }
        .alert(RDLocalization.string("localizable.nova.pilot.main.gate.nova.pilot.d20fb7f1", table: .localizable, fallback: "İSGADA pilot"), isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("Tamam", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .task { if !previewOnly && !isWorkspaceExpert { await controller.observe() } }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { event in
            if event.object as? UUID == identity.userID { listRevision = UUID() }
        }
        .task(id: overviewKey) {
            guard ready, !isWorkspaceExpert else { return }
            overviewFailed = false
            do { overview = try await loadNovaPilotOverview(identity: identity) }
            catch { if !Task.isCancelled { overviewFailed = true } }
        }
        .task(id: overviewKey) {
            guard ready, !isWorkspaceExpert else { return }
            equipmentBoard = try? await NovaEquipmentCheckService.live().board(identity, query: .init(limit: 1))
        }
        .task(id: noticeKey) {
            guard ready, !previewOnly, !isWorkspaceExpert else { return }
            notices = (try? await NovaNoticeService.live().feed(identity)) ?? .empty
        }
        .task(id: workspaceTaskKey) {
            guard let workspaceStore, ready else { return }
            async let dashboardValue = workspaceStore.aggregateExpertDashboard()
            async let personnelValue = workspaceStore.aggregateExpertPersonnelMetrics()
            workspaceDashboard = try? await dashboardValue
            workspacePersonnel = try? await personnelValue
        }
        .onChange(of: scenePhase) { phase in
            // Screenshots, permission prompts and Control Center can cause inactive → active.
            // They are not a new session and must not destroy a sheet or its draft.
            if sceneRevalidation.update(isBackground: phase == .background, isActive: phase == .active) {
                if !previewOnly {
                    if let workspaceStore { workspaceStore.refresh(); workspaceRevision = UUID() }
                    else { controller.refresh() }
                }
            }
        }
        .onChange(of: controller.host.identity) { next in
            if next != identity { showingCreate = false; notice = nil; noticeSource = nil; trainingNoticeSource = nil }
        }
        .modifier(NovaSuccessPresentation(account: identity.userID))
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
                        if let workspaceStore { workspaceStore.refresh(); workspaceRevision = UUID() }
                        else { controller.refresh() }
                    } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel(RDLocalization.string("localizable.nova.pilot.main.gate.pilot.erisimini.tekrar.kontrol.et.bfce533e", table: .localizable, fallback: "Pilot erişimini tekrar kontrol et"))
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 10)
    }

    /// Evrak takibi reads one company at a time and says which one.
    @ViewBuilder private var documents: some View {
        if ready {
            NovaPilotDocumentGate(identity: identity, scope: controller.scope, canWrite: ready,
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
            NovaPilotRiskGate(identity: identity, canWrite: ready, showBackButton: true,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var checklists: some View {
        if ready {
            NovaPilotChecklistGate(identity: identity, canWrite: ready,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var emergencyPlans: some View {
        if ready {
            NovaPilotEmergencyGate(identity: identity, canWrite: ready,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var drills: some View {
        if ready {
            NovaPilotDrillGate(identity: identity, canWrite: ready,
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
            NovaPilotPPEGate(identity: identity, canWrite: ready,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var appointments: some View {
        if ready {
            NovaPilotAppointmentGate(identity: identity, canWrite: ready,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var katip: some View {
        if ready {
            NovaPilotKatipGate(identity: identity, canWrite: ready,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    @ViewBuilder private var equipment: some View {
        if ready {
            NovaPilotEquipmentGate(identity: identity, canWrite: ready,
                onBack: { navigate(.home) })
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    /// Diğer Dosyalar reads the whole account and narrows to one company when
    /// the expert picks one.
    @ViewBuilder private func files(startInAddMode: Bool = false) -> some View {
        if ready {
            NovaPilotFileGate(identity: identity, canWrite: ready,
                startInAddMode: startInAddMode, onBack: { navigate(.home) })
                .id(startInAddMode)
        } else {
            NovaText(text: RDLocalization.string("localizable.nova.pilot.main.gate.canli.pilot.erisimi.henuz.kullanilamiyor.dad36f07", table: .localizable, fallback: "Canlı pilot erişimi henüz kullanılamıyor")).padding(20)
        }
    }

    /// Each menu entry lands on exactly one page; the surface says which.
    @ViewBuilder private func nonconformities(_ surface: NovaFindingsSurface) -> some View {
        if let workspaceStore {
            NovaWorkspaceExpertFindingsGate(store: workspaceStore, surface: surface,
                onNavigate: navigate, onBack: { navigate(.home) })
                .id("workspace:\(surface):\(workspaceRevision)")
        } else if ready {
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
        if let workspaceStore {
            NovaWorkspaceExpertCompaniesGate(store: workspaceStore,
                selectedCompanyID: $workspaceCompanyID,
                onBack: { navigate(.home) })
                .id("workspace-companies:\(workspaceRevision)")
        } else if ready, let scope = controller.scope {
            NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma",
                canWrite: controller.canWrite, personnel: controller.personnelClient, directory: controller.directoryClient,
                onBack: { controller.select(nil) },
                loadSummary: { try await loadNovaPilotOverview(identity: identity, companyID: scope.companyID).first },
                loadNonconformities: {
                    try await NovaNonconformityService.live(currentScope: { controller.scope }).list(scope)
                },
                onOpenNonconformities: { navigate(.findings) })
                .id(scope.epoch)
        } else if ready && controller.selectedCompanyID == nil {
            VStack(spacing: 0) {
                NovaCompanyDestination(host: Binding(get: { controller.host }, set: { _ in }),
                    loadCompanies: { try await loadNovaPilotCompanies(identity: identity, includeArchived: $0) },
                    includeArchived: true, onSelect: controller.select,
                    onBack: { navigate(.home) }, onCreate: { showingCreate = true })
                    .id(listRevision)
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

    @ViewBuilder private func workspaceDomain(_ store: IsgWorkspaceStore,
                                              _ domain: IsgWorkspaceDomain,
                                              startInAddMode: Bool = false) -> some View {
        NovaWorkspaceExpertDomainGate(store: store, domain: domain,
            startInAddMode: startInAddMode, onBack: { navigate(.home) })
            .id("workspace-domain:\(domain.rawValue):\(startInAddMode):\(workspaceRevision)")
    }

    private func workspaceDomain(for destination: NovaDestination) -> IsgWorkspaceDomain? {
        switch destination {
        case .katipContracts: return .katip
        case .annualWorkPlans: return .annualPlan
        case .boardMeetings: return .board
        case .visits: return .visit
        case .workPermits: return .workPermit
        case .contractors: return .personnel
        default: return nil
        }
    }

    private func workspaceSelectedCompany(in store: IsgWorkspaceStore) -> IsgWorkspaceCompany? {
        let id = workspaceCompanyID ?? store.selectedCompanyID
        return store.companies.first { $0.id == id }
    }

    private func workspaceReportCenter(_ store: IsgWorkspaceStore) -> some View {
        NovaWorkspaceExpertReportCenter(onAnalyses: { navigate(.analyses) },
            onDocuments: { navigate(.documents) }, onBack: { navigate(.home) })
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

// MARK: - OSGB expert data adapters for the shared expert root

/// Chooses a tenant company only when a module actually needs company scope.
/// The home page remains an aggregate expert dashboard and never owns a
/// company picker.
private struct NovaWorkspaceExpertDomainGate: View {
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    var startInAddMode = false
    let onBack: () -> Void
    @State private var selectedCompanyID: UUID?

    private var context: IsgWorkspaceContext? {
        guard let id = store.selection?.workspaceID else { return nil }
        return store.contexts.first { $0.workspaceID == id }
    }
    private var selectedCompany: IsgWorkspaceCompany? {
        guard let id = selectedCompanyID else { return nil }
        return store.companies.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let company = selectedCompany, store.phase == .ready,
               store.selectedCompanyID == company.id {
                if domain == .personnel {
                    IsgWorkspacePersonnelScreen(store: store, companyName: company.name,
                        canOperate: context?.canOperate == true, canManageDirectory: false,
                        initialSection: .employee, onBack: { selectedCompanyID = nil })
                        .id("\(company.id):personnel")
                } else {
                    IsgWorkspaceDomainScreen(store: store, domain: domain,
                        companyName: company.name, companyHazardClass: company.hazardClass,
                        canOperate: context?.canOperate == true,
                        startInAddMode: startInAddMode,
                        onBack: { selectedCompanyID = nil })
                        .id("\(company.id):\(domain.rawValue):\(startInAddMode)")
                }
            } else if selectedCompanyID != nil || store.phase == .loading {
                NovaPageSurface {
                    VStack(spacing: 14) {
                        NovaPageHeading(title: domain.title, onBack: { selectedCompanyID = nil })
                        NovaLoadingView(message: "Firma çalışma alanı hazırlanıyor…")
                    }.padding(.horizontal, 18)
                }
            } else {
                NovaCompaniesScreen(companies: store.companies.map {
                    .init(id: $0.id.uuidString, name: $0.name,
                          detail: [$0.hazardClass, $0.sector].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }, isLoading: store.phase == .loading && store.companies.isEmpty,
                    isOwnedList: false,
                    onSelect: { value in
                        guard let id = UUID(uuidString: value) else { return }
                        selectedCompanyID = id
                        if store.selectedCompanyID != id { store.selectCompany(id) }
                    }, onBack: onBack, onRetry: { store.refresh() })
            }
        }
        .onAppear {
            if selectedCompanyID == nil, store.companies.count == 1,
               let only = store.companies.first {
                selectedCompanyID = only.id
                if store.selectedCompanyID != only.id { store.selectCompany(only.id) }
            }
        }
    }
}

/// Findings and analyses keep the normal expert navigation contract. Only the
/// persistence provider changes to the selected OSGB workspace.
private struct NovaWorkspaceExpertFindingsGate: View {
    @ObservedObject var store: IsgWorkspaceStore
    let surface: NovaFindingsSurface
    let onNavigate: (NovaDestination) -> Void
    let onBack: () -> Void
    @State private var addRoute: AddRoute?

    private enum AddRoute: String, Identifiable { case analysis, manual; var id: String { rawValue } }

    var body: some View {
        Group {
            switch surface {
            case .board:
                NovaWorkspaceExpertDomainGate(store: store, domain: .nonconformity, onBack: onBack)
            case .analyses:
                analysisGate(startInCreateMode: false)
            case .newAnalysis:
                analysisGate(startInCreateMode: true)
            case .addFinding:
                addFinding
            }
        }
        .novaFullScreenCover(item: $addRoute) { route in
            switch route {
            case .analysis:
                analysisGate(startInCreateMode: false, onBack: { addRoute = nil })
            case .manual:
                NovaWorkspaceExpertDomainGate(store: store, domain: .nonconformity,
                    startInAddMode: true, onBack: { addRoute = nil })
            }
        }
    }

    private var addFinding: some View {
        NovaPageSurface(onEdgeBack: { onNavigate(.findings) }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: NovaDestination.newFinding.title,
                        onBack: { onNavigate(.findings) })
                    NovaHelpHint(text: "Daha önce yaptığınız bir analizin bulgularından seçebilir ya da kaydı kendiniz girebilirsiniz.")
                    addCard(title: "Analiz bulgularından seç", detail: "Bir analizi açın, bulguları seçin ve firmaya uygunsuzluk olarak aktarın.",
                            symbol: "sparkles.rectangle.stack", action: { addRoute = .analysis })
                    addCard(title: "Manuel uygunsuzluk ekle", detail: "Firma, işyeri, tehlike, önlem, sorumlu ve termin bilgileriyle ayrıntılı kayıt açın.",
                            symbol: "square.and.pencil", action: { addRoute = .manual })
                }.padding(.horizontal, 18).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private func addCard(title: String, detail: String, symbol: String,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaCard(padding: 16) {
                HStack(spacing: 12) {
                    NovaIcon(symbol: symbol, size: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: title, style: .cardTitle)
                        NovaText(text: detail, style: .metaQuiet)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }.frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }

    private func analysisGate(startInCreateMode: Bool,
                              onBack: (() -> Void)? = nil) -> some View {
        NovaWorkspaceExpertAnalysisGate(store: store, startInCreateMode: startInCreateMode,
            onBack: onBack ?? self.onBack)
    }
}

private struct NovaWorkspaceExpertAnalysisGate: View {
    @ObservedObject var store: IsgWorkspaceStore
    let startInCreateMode: Bool
    let onBack: () -> Void
    @State private var selectedCompanyID: UUID?

    private var context: IsgWorkspaceContext? {
        guard let id = store.selection?.workspaceID else { return nil }
        return store.contexts.first { $0.workspaceID == id }
    }
    private var selectedCompany: IsgWorkspaceCompany? {
        guard let id = selectedCompanyID else { return nil }
        return store.companies.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let company = selectedCompany, store.phase == .ready,
               store.selectedCompanyID == company.id {
                IsgWorkspaceAnalysisScreen(store: store, companyID: company.id,
                    companyName: company.name, canOperate: context?.canOperate == true,
                    startInCreateMode: startInCreateMode,
                    onBack: { selectedCompanyID = nil })
                    .id("\(company.id):analysis:\(startInCreateMode)")
            } else if selectedCompanyID != nil || store.phase == .loading {
                NovaPageSurface {
                    VStack(spacing: 14) {
                        NovaPageHeading(title: NovaDestination.analyses.title,
                            onBack: { selectedCompanyID = nil })
                        NovaLoadingView(message: "Firma analizleri hazırlanıyor…")
                    }.padding(.horizontal, 18)
                }
            } else {
                NovaCompaniesScreen(companies: store.companies.map {
                    .init(id: $0.id.uuidString, name: $0.name,
                          detail: [$0.hazardClass, $0.sector].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                }, isLoading: store.phase == .loading && store.companies.isEmpty,
                    isOwnedList: false,
                    onSelect: { value in
                        guard let id = UUID(uuidString: value) else { return }
                        selectedCompanyID = id
                        if store.selectedCompanyID != id { store.selectCompany(id) }
                    }, onBack: onBack, onRetry: { store.refresh() })
            }
        }
        .onAppear {
            if selectedCompanyID == nil, store.companies.count == 1,
               let only = store.companies.first {
                selectedCompanyID = only.id
                if store.selectedCompanyID != only.id { store.selectCompany(only.id) }
            }
        }
    }
}

private struct NovaWorkspaceExpertCompaniesGate: View {
    @ObservedObject var store: IsgWorkspaceStore
    @Binding var selectedCompanyID: UUID?
    let onBack: () -> Void

    var body: some View {
        if let id = selectedCompanyID,
           let company = store.companies.first(where: { $0.id == id }) {
            NovaWorkspaceExpertCompanyDetail(store: store, company: company,
                onBack: { selectedCompanyID = nil })
                .id("workspace-company:\(id)")
        } else {
            NovaCompaniesScreen(companies: store.companies.map {
                .init(id: $0.id.uuidString, name: $0.name,
                      detail: [$0.hazardClass, $0.sector].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            }, isLoading: store.phase == .loading && store.companies.isEmpty,
                isOwnedList: false,
                onSelect: { value in
                    guard let id = UUID(uuidString: value) else { return }
                    selectedCompanyID = id
                    if store.selectedCompanyID != id { store.selectCompany(id) }
                }, onBack: onBack, onRetry: { store.refresh() })
        }
    }
}

private struct NovaWorkspaceExpertCompanyDetail: View {
    @ObservedObject var store: IsgWorkspaceStore
    let company: IsgWorkspaceCompany
    let onBack: () -> Void
    @State private var expanded = Set<NovaCompanySection>()
    @State private var snapshots: [IsgWorkspaceDomain: IsgWorkspaceDomainSnapshot] = [:]
    @State private var selectedDomain: IsgWorkspaceDomain?
    @State private var showingAnalyses = false
    @State private var loading = true

    private var context: IsgWorkspaceContext? {
        guard let id = store.selection?.workspaceID else { return nil }
        return store.contexts.first { $0.workspaceID == id }
    }
    private var progress: NovaCompanyProgress {
        var states: [NovaCompanySection: NovaCompletionState] = [:]
        for section in NovaCompanySection.allCases {
            guard let domain = domain(for: section), let snapshot = snapshots[domain] else {
                states[section] = .unknown; continue
            }
            states[section] = snapshot.rows.isEmpty ? .missing : .complete
        }
        return .init(states: states)
    }

    var body: some View {
        Group {
            if let selectedDomain {
                if selectedDomain == .personnel {
                    IsgWorkspacePersonnelScreen(store: store, companyName: company.name,
                        canOperate: context?.canOperate == true, canManageDirectory: false,
                        initialSection: .employee, onBack: { self.selectedDomain = nil })
                } else {
                    IsgWorkspaceDomainScreen(store: store, domain: selectedDomain,
                        companyName: company.name, companyHazardClass: company.hazardClass,
                        canOperate: context?.canOperate == true,
                        onBack: { self.selectedDomain = nil })
                }
            } else if showingAnalyses {
                IsgWorkspaceAnalysisScreen(store: store, companyID: company.id,
                    companyName: company.name, canOperate: context?.canOperate == true,
                    onBack: { showingAnalyses = false })
            } else {
                overview
            }
        }
        .onAppear {
            if store.selectedCompanyID != company.id { store.selectCompany(company.id) }
        }
        .task(id: "\(company.id):\(store.phase)") { await loadSnapshots() }
    }

    private var overview: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: "Firma Detayı", onBack: onBack)
                    companyCard
                    NovaCompanyScoreCard(progress: progress)
                    Button { showingAnalyses = true } label: {
                        NovaCard(padding: 14) {
                            HStack(spacing: 10) {
                                NovaIcon(symbol: NovaDestination.analyses.symbol, size: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: "Analizler ve uygunsuzluklar", style: .bodyStrong)
                                    NovaText(text: "Analiz sonuçlarını açın veya firma kayıtlarını takip edin.", style: .metaQuiet)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                            }.contentShape(Rectangle())
                        }
                    }.buttonStyle(.plain)
                    if loading { NovaLoadingView(message: "Firma başlıkları güncelleniyor…") }
                    NovaCompanyAccordion(title: "Firma Bilgileri", symbol: "building.2",
                        identifier: "workspace.company.info",
                        expanded: Binding(get: { expanded.contains(.logo) }, set: { setExpanded(.logo, $0) })) {
                        infoRows
                    }
                    ForEach(NovaCompanySection.allCases.filter { $0 != .logo }) { section in
                        NovaCompanyAccordion(title: section.title, symbol: section.symbol,
                            state: progress[section], identifier: "workspace.company.section.\(section.rawValue)",
                            expanded: Binding(get: { expanded.contains(section) }, set: { setExpanded(section, $0) })) {
                            sectionContents(section)
                        }
                    }
                }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private var companyCard: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    NovaIcon(symbol: "building.2", size: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: company.name, style: .cardTitle)
                        NovaText(text: company.address?.nilIfBlank ?? "Adres bilgisi eklenmemiş", style: .metaQuiet)
                    }
                }
                HStack(spacing: 8) {
                    NovaStatusPill(label: hazardLabel(company.hazardClass), status: .warning)
                    if let sector = company.sector?.nilIfBlank {
                        NovaStatusPill(label: sector, status: .info)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var infoRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            info("Tehlike sınıfı", hazardLabel(company.hazardClass))
            info("Sektör", company.sector?.nilIfBlank ?? "Belirtilmemiş")
            info("E-posta", company.email?.nilIfBlank ?? "Belirtilmemiş")
            info("Çalışan sayısı", company.declaredEmployeeCount.map(String.init) ?? "Belirtilmemiş")
            info("Sorumlu", company.responsibleName?.nilIfBlank ?? "Belirtilmemiş")
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NovaText(text: label, style: .metaQuiet).frame(width: 110, alignment: .leading)
            NovaText(text: value, style: .bodyStrong).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 10).frame(minHeight: 42).novaControlBackground(cornerRadius: 12)
    }

    private func sectionContents(_ section: NovaCompanySection) -> some View {
        let domain = domain(for: section)
        let count = domain.flatMap { snapshots[$0]?.rows.count }
        return VStack(alignment: .leading, spacing: 9) {
            if let count {
                NovaText(text: count == 0 ? "Henüz kayıt yok" : "\(count) kayıt",
                         style: count == 0 ? .metaQuiet : .bodyStrong)
            } else {
                NovaText(text: "Kayıt durumu yükleniyor…", style: .metaQuiet)
            }
            if let domain {
                NovaCompactActionButton(title: count == 0 ? "İlk kaydı ekle" : "Kayıtları aç",
                    symbol: count == 0 ? "plus" : "arrow.right", prominent: count == 0,
                    enabled: context?.canOperate == true || count != 0) {
                        selectedDomain = domain
                    }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func setExpanded(_ section: NovaCompanySection, _ value: Bool) {
        if value { expanded.insert(section) } else { expanded.remove(section) }
    }

    private func domain(for section: NovaCompanySection) -> IsgWorkspaceDomain? {
        switch section {
        case .logo: return nil
        case .personnel: return .personnel
        case .representative, .support: return .appointment
        case .risk: return .risk
        case .emergency: return .emergencyPlan
        case .inspections: return .equipment
        case .accidents, .files: return .files
        case .board: return .board
        case .training: return .training
        case .handover: return .ppe
        }
    }

    @MainActor private func loadSnapshots() async {
        guard store.phase == .ready, store.selectedCompanyID == company.id else { return }
        loading = true
        let domains = Set(NovaCompanySection.allCases.compactMap(domain(for:)))
        var values: [IsgWorkspaceDomain: IsgWorkspaceDomainSnapshot] = [:]
        for domain in domains {
            if let snapshot = try? await store.domain(domain, companyID: company.id) {
                values[domain] = snapshot
            }
        }
        if !Task.isCancelled { snapshots = values; loading = false }
    }

    private func hazardLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "low", "az_tehlikeli", "az tehlikeli": return "Az Tehlikeli"
        case "high", "cok_tehlikeli", "çok tehlikeli": return "Çok Tehlikeli"
        default: return "Tehlikeli"
        }
    }
}

private struct NovaWorkspaceExpertStatisticsScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let dashboard: IsgWorkspaceDashboard?
    let personnel: IsgPersonnelMetrics?
    let onBack: () -> Void
    let onNavigate: (NovaDestination) -> Void

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: NovaDestination.statistics.title, onBack: onBack)
                    NovaHelpHint(text: "Atandığınız tüm firmalardaki güncel kayıtların toplamı gösterilir.")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        stat("Firmalar", dashboard?.companies.first, "building.2", .companies)
                        stat("Personel", personnel?.employees.active, "person.2", .companies)
                        stat("Açık uygunsuzluk", dashboard?.nonconformities.first, "checklist", .findings)
                        stat("Süresi geçen", dashboard?.nonconformities.second, "exclamationmark.triangle", .findings)
                        stat("Tamamlanan eğitim", dashboard?.training.second, "graduationcap", .training)
                        stat("Yaklaşan kontroller", (dashboard?.deadlines.first ?? 0) + (dashboard?.deadlines.second ?? 0), "calendar.badge.clock", .periodicChecks)
                    }
                    NovaCompactActionButton(title: "Verileri yenile", symbol: "arrow.clockwise") { store.refresh() }
                }.padding(.horizontal, 18).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private func stat(_ title: String, _ value: Int64?, _ symbol: String,
                      _ destination: NovaDestination) -> some View {
        Button { onNavigate(destination) } label: {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    NovaIcon(symbol: symbol, size: 20)
                    NovaText(text: value.map(String.init) ?? "—", style: .screenTitle)
                    NovaText(text: title, style: .meta)
                }.frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
            }
        }.buttonStyle(.plain)
    }
}

private struct NovaWorkspaceExpertReportCenter: View {
    let onAnalyses: () -> Void
    let onDocuments: () -> Void
    let onBack: () -> Void

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: "Rapor Merkezi", onBack: onBack)
                    NovaHelpHint(text: "Atandığınız firmaların analiz çıktılarını ve belgelerini açın.")
                    row("Analiz raporları", "Risk analizi sonuçlarını inceleyin ve dışa aktarın.", "chart.doc", onAnalyses)
                    row("Firma dokümanları", "Dosya ve geçerlilik kayıtlarını yönetin.", "doc.text", onDocuments)
                }.padding(.horizontal, 18).padding(.bottom, novaTabBarInset)
            }
        }
    }

    private func row(_ title: String, _ detail: String, _ symbol: String,
                     _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaCard(padding: 14) {
                HStack(spacing: 10) {
                    NovaIcon(symbol: symbol, size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: title, style: .bodyStrong)
                        NovaText(text: detail, style: .metaQuiet)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                }.contentShape(Rectangle())
            }
        }.buttonStyle(.plain)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
