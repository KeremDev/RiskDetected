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
           let configured = Bundle.main.object(forInfoDictionaryKey: "NOVAPilotOwnerID") as? String,
           UUID(uuidString: configured) == session.user.id,
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
                if store.phase == .ready {
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
        available: [.companies, .findings, .analyses, .statistics, .training, .riskAssessments, .checklists,
                    .emergencyPlans, .drills, .ppeHandovers, .appointments, .katipContracts,
                    .annualWorkPlans, .boardMeetings, .visits, .workPermits, .periodicChecks,
                    .documents, .notifications])
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

    var body: some View {
        NovaExpertShell(navigation: $navigation, userName: app.profile?.fullName ?? "",
            connectionLabel: context.map { "\($0.name) · \(role($0.membership.role))" } ?? "",
            onCompanyCreate: canManageCompanies ? { editor = .create } : nil,
            onLogout: { app.signOut() }) { destination in
            switch destination {
            case .home, .statistics: dashboard
            case .companies: companies
            case .findings: domain(.nonconformity)
            case .analyses: analyses
            case .training: domain(.training)
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
            case .documents: domain(.files)
            case .notifications: changes
            case .profile:
                NovaPageSurface(onEdgeBack: { navigate(.home) }) {
                    VStack(spacing: 0) {
                        NovaPageHeading(title: RDLocalization.string("localizable.nova.navigation.profile", table: .localizable,
                            fallback: "Profil"), onBack: { navigate(.home) }).padding(.horizontal, 20)
                        ProfileView()
                    }
                }
            default: dashboard
            }
        }
        .preferredColorScheme(.light)
        .task(id: store.selectedCompanyID) {
            personnel = try? await store.personnelMetrics()
            query = ""; searchRows = nil; searchError = nil
        }
        .novaFullScreenCover(item: $editor) { route in
            NovaPopup {
                IsgWorkspaceCompanyEditor(company: route.company,
                    onSave: { name, hazard in
                        if let company = route.company {
                            _ = try await store.updateCompany(mutationID: route.mutationID, companyID: company.id,
                                expectedVersion: company.version, name: name, hazardClass: hazard)
                        } else {
                            _ = try await store.createCompany(mutationID: route.mutationID, name: name, hazardClass: hazard)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                workspaceHeading(title: context?.name ?? RDLocalization.string("localizable.nova.workspace.osgb", table: .localizable, fallback: "OSGB"))
                if let company = selectedCompany {
                    NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.workspace.company.active", table: .localizable,
                        fallback: "%@ firması için yetkili kayıtları görüntülüyorsunuz."), company.name))
                }
                if let board = store.dashboard {
                    statGrid(board)
                    if let personnel { personnelGrid(personnel) }
                } else {
                    NovaLoadingView(message: RDLocalization.string("localizable.nova.workspace.summary.loading", table: .localizable,
                        fallback: "Özet yükleniyor…"))
                }
                companySelector
                if selectedCompany != nil {
                    NovaCard(padding: 12) {
                        Button { showingSearch = true } label: {
                            HStack(spacing: 10) {
                                NovaIcon(symbol: "magnifyingglass", size: 19)
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: RDLocalization.string(
                                        "localizable.nova.workspace.search.title", table: .localizable,
                                        fallback: "Firma Kayıtlarında Ara"), style: .bodyStrong)
                                    NovaText(text: RDLocalization.string(
                                        "localizable.nova.workspace.search.company.hint", table: .localizable,
                                        fallback: "Personel, uygunsuzluk, ekipman ve dosyalarda arayın."), style: .metaQuiet)
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
                                    NovaText(text: RDLocalization.string("localizable.nova.workspace.members.title", table: .localizable,
                                        fallback: "Uzman ve yönetici ekibi"), style: .bodyStrong)
                                    NovaText(text: RDLocalization.string("localizable.nova.workspace.members.hint", table: .localizable,
                                        fallback: "Davetleri, rolleri ve erişim durumlarını yönetin."), style: .metaQuiet)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if let company = selectedCompany {
                        NovaCard(padding: 12) {
                            Button { showingAssignments = true } label: {
                                HStack(spacing: 10) {
                                    NovaIcon(symbol: "person.2.badge.gearshape", size: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        NovaText(text: RDLocalization.string(
                                            "localizable.nova.workspace.assignment.title", table: .localizable,
                                            fallback: "Firma uzmanları"), style: .bodyStrong)
                                        NovaText(text: String(format: RDLocalization.string(
                                            "localizable.nova.workspace.assignment.company.hint", table: .localizable,
                                            fallback: "%@ firmasının uzman erişimini yönetin."), company.name), style: .metaQuiet)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
                moduleGrid
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
        }
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

    private var companies: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                workspaceHeading(title: RDLocalization.string("localizable.nova.workspace.companies", table: .localizable,
                    fallback: "Firmalar"))
                if canManageCompanies {
                    NovaCompactActionButton(title: RDLocalization.string("localizable.nova.navigation.firma.ekle.b4073323", table: .localizable,
                        fallback: "Firma Ekle"), symbol: "plus", prominent: true) { editor = .create }
                }
                if store.companies.isEmpty {
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.workspace.company.empty", table: .localizable,
                            fallback: "Henüz firma yok"),
                        message: RDLocalization.string("localizable.nova.workspace.company.empty.detail", table: .localizable,
                            fallback: "İlk firmayı ekleyerek personel ve İSG kayıtlarını bu çalışma alanında takip edebilirsiniz."))
                } else {
                    ForEach(store.companies, id: \.id) { company in companyRow(company) }
                }
            }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
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

    @ViewBuilder private func domain(_ value: IsgWorkspaceDomain, onBack: (() -> Void)? = nil) -> some View {
        if let company = selectedCompany {
            if value == .personnel {
                IsgWorkspacePersonnelScreen(store: store, companyName: company.name,
                    canOperate: context?.canOperate == true, canManageDirectory: canManageCompanies,
                    onBack: onBack ?? { navigate(.home) })
                    .id("\(company.id):personnel")
            } else {
                IsgWorkspaceDomainScreen(store: store, domain: value, companyName: company.name,
                    canOperate: context?.canOperate == true,
                    onBack: onBack ?? { navigate(.home) })
                    .id("\(company.id):\(value.rawValue)")
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

    private var changes: some View {
        IsgWorkspaceChangeScreen(store: store, companyName: selectedCompany?.name,
                                 onBack: { navigate(.home) })
    }

    @ViewBuilder private var analyses: some View {
        if let company = selectedCompany {
            IsgWorkspaceAnalysisScreen(store: store, companyID: company.id,
                companyName: company.name, canOperate: context?.canOperate == true,
                onBack: { navigate(.findings) })
                .id("\(company.id):analyses")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: NovaDestination.analyses.title, onBack: { navigate(.findings) })
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
            NovaListStat(title: RDLocalization.string("localizable.nova.workspace.metric.experts", table: .localizable, fallback: "Uzmanlar"), symbol: "person.badge.shield.checkmark", value: value(board.experts))
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
                        NovaText(text: hazard(company.hazardClass), style: .metaQuiet)
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
        working = true; error = nil
        Task {
            do {
                latestToken = try await store.invite(mutationID: UUID(), email: target,
                                                     role: inviteRole, expiresAt: expiration)
                email = ""
                invitations = try await store.invitations()
                celebrate(RDLocalization.string("localizable.nova.workspace.invite.created", table: .localizable,
                    fallback: "Davet oluşturuldu."))
            } catch { failure() }
            working = false
        }
    }

    private func mutate(_ member: IsgWorkspaceMember, action: String,
                        value: String? = nil, reason: String? = nil) {
        working = true; error = nil
        Task {
            do {
                let updated = try await store.mutateMember(mutationID: UUID(), member: member,
                    action: action, value: value, reason: reason)
                if let index = members.firstIndex(where: { $0.id == updated.id }) { members[index] = updated }
                celebrate(RDLocalization.string("localizable.nova.workspace.member.updated", table: .localizable,
                    fallback: "Üye erişimi güncellendi."))
            } catch { failure() }
            working = false
        }
    }

    private func resend(_ invitation: IsgWorkspaceInvitation) {
        working = true; error = nil
        Task {
            do {
                latestToken = try await store.resendInvitation(mutationID: UUID(), invitation: invitation,
                                                               expiresAt: expiration)
                invitations = try await store.invitations()
                celebrate(RDLocalization.string("localizable.nova.workspace.invite.renewed", table: .localizable,
                    fallback: "Yeni davet kodu oluşturuldu."))
            } catch { failure() }
            working = false
        }
    }

    private func revoke(_ invitation: IsgWorkspaceInvitation) {
        working = true; error = nil
        Task {
            do {
                try await store.revokeInvitation(mutationID: UUID(), invitation: invitation)
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
    let mutationID = UUID()
    let archiveMutationID = UUID()
    var id: UUID { mutationID }
    static var create: Self { .init(company: nil) }
    static func edit(_ company: IsgWorkspaceCompany) -> Self { .init(company: company) }
}

private struct IsgWorkspaceCompanyEditor: View {
    let company: IsgWorkspaceCompany?
    let onSave: (String, String) async throws -> Void
    let onArchive: ((String) async throws -> Void)?
    @State private var name: String
    @State private var hazard: String
    @State private var reason = ""
    @State private var saving = false
    @State private var error: String?
    @Environment(\.novaCelebrate) private var celebrate

    init(company: IsgWorkspaceCompany?, onSave: @escaping (String, String) async throws -> Void,
         onArchive: ((String) async throws -> Void)?) {
        self.company = company; self.onSave = onSave; self.onArchive = onArchive
        _name = State(initialValue: company?.name ?? "")
        _hazard = State(initialValue: company?.hazardClass ?? "medium")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NovaText(text: company == nil
                    ? RDLocalization.string("localizable.nova.navigation.firma.ekle.b4073323", table: .localizable, fallback: "Firma Ekle")
                    : RDLocalization.string("localizable.nova.workspace.company.edit", table: .localizable, fallback: "Firmayı düzenle"), style: .sectionTitle)
                NovaCard(padding: 14) {
                    VStack(spacing: 12) {
                        TextField(RDLocalization.string("localizable.company.picker.sheet.firma.adi.32866b14", table: .localizable,
                            fallback: "Firma adı"), text: $name).font(NovaFont.font(.body))
                        Picker(RDLocalization.string("localizable.nova.visual.6", table: .localizable, fallback: "Tehlike sınıfı"), selection: $hazard) {
                            Text(RDLocalization.string("localizable.nova.visual.7", table: .localizable, fallback: "Az Tehlikeli")).tag("low")
                            Text(RDLocalization.string("localizable.nova.visual.8", table: .localizable, fallback: "Tehlikeli")).tag("medium")
                            Text(RDLocalization.string("localizable.nova.visual.9", table: .localizable, fallback: "Çok Tehlikeli")).tag("high")
                        }
                    }
                }
                if let error { NovaHelpHint(text: error) }
                NovaButton(label: saving
                    ? RDLocalization.string("localizable.nova.workspace.saving", table: .localizable, fallback: "Kaydediliyor…")
                    : RDLocalization.string("localizable.nova.personnel.save", table: .localizable, fallback: "Kaydet"),
                    symbol: saving ? "hourglass" : "checkmark", isEnabled: !saving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save() }
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
        }.scrollDismissesKeyboard(.interactively)
    }

    private func save() {
        saving = true; error = nil
        Task {
            do {
                try await onSave(name, hazard)
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
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = NovaWorkspaceController()
    @State private var navigation = NovaNavigationState(epoch: UUID().uuidString, available: [.riskAssessments, .statistics, .companies, .newCompany, .findings, .newFinding, .analyses, .newAnalysis, .training, .newTraining, .documentChecklist, .documents, .newDocument, .periodicChecks, .emergencyPlans, .drills, .ppeHandovers, .appointments, .katipContracts, .annualWorkPlans, .boardMeetings, .visits, .workPermits, .contractors, .reports, .reportArchive, .checklists, .notifications])
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
    private var overviewKey: String { "\(controller.host.navigation.epoch):\(ready):\(listRevision):\(navigation.selected)" }
    /// The bell reloads when the session, the records or the panel change, and
    /// after every mark.
    private var noticeKey: String { "\(controller.host.navigation.epoch):\(ready):\(listRevision):\(noticeRevision)" }
    private var activeCompanies: [NovaPilotCompanySummary]? { ready ? overview?.filter { !$0.is_archived } : nil }
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
    private var ready: Bool { !previewOnly && controller.isAvailable && controller.host.identity == identity }
    private var status: String {
        if previewOnly { return RDLocalization.string("localizable.nova.pilot.main.gate.tasarim.kontrolu.canli.veri.kullanilmiyor.d6b551c8", table: .localizable, fallback: "Tasarım kontrolü · canlı veri kullanılmıyor") }
        if controller.resolving { return RDLocalization.string("localizable.nova.pilot.main.gate.pilot.erisimi.kontrol.ediliyor.6a965311", table: .localizable, fallback: "Pilot erişimi kontrol ediliyor…") }
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
            onCompanyCreate: { showingCreate = true },
            onDestination: { destination in
                // The company workspace lives below the companies host rather
                // than in NavigationStack's path. Selecting Firmalar from the
                // drawer/tab therefore must clear that feature-local scope.
                if destination == .companies { controller.select(nil) }
            },
            onLogout: { app.signOut() }) { destination in
            switch destination {
            case .home:
                VStack(spacing: 0) {
                    statusCard
                    NovaDashboardScreen(data: .init(firstName: name.split(separator: " ").first.map(String.init) ?? "",
                        openCount: nil, metrics: metrics, activity: nil,
                        trainingMessage: "Gerçekleşen eğitimler ve katılımcı kayıtları",
                        summaryMessage: activeCompanies != nil ? RDLocalization.string("localizable.nova.pilot.main.gate.pilot.firmalarinizin.guncel.kayitlari.01d48da7", table: .localizable, fallback: "Pilot firmalarınızın güncel kayıtları.") : overviewFailed ? RDLocalization.string("localizable.nova.pilot.main.gate.ozet.alinamadi.yenileyerek.tekrar.deneyin.9b6a6077", table: .localizable, fallback: "Özet alınamadı. Yenileyerek tekrar deneyin.") : RDLocalization.string("localizable.nova.pilot.main.gate.ozet.verileri.henuz.bagli.degil.4508136e", table: .localizable, fallback: "Özet verileri henüz bağlı değil.")),
                        onNavigate: navigate,
                        onPhoto: { navigate(.newAnalysis) }, onAssistant: unavailable,
                        trackingIdentity: ready ? identity : nil, trackingCanWrite: controller.canWrite)
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
                NovaTrainingHub(identity: identity, scope: controller.scope, personnel: controller.personnelClient,
                    canWrite: ready, select: controller.select,
                    onBack: { navigate(.home) }, createOnOpen: destination == .newTraining)
                    .id(destination)
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
                    NovaPilotProcessGate(identity: identity, kind: processKind(destination), canWrite: ready, onBack: { navigate(.home) })
                        .id(destination)
                } else { statusCard }
            case .notifications:
                if ready {
                    NovaPilotNoticeGate(identity: identity,
                        onOpen: { target in navigate(target) },
                        onBack: { navigate(.home) })
                } else { statusCard }
            case .reports, .reportArchive:
                NovaProcessArchive(identity: identity, onBack: { navigate(.home) })
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
        .task { if !previewOnly { await controller.observe() } }
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
        .task(id: noticeKey) {
            guard ready, !previewOnly else { return }
            notices = (try? await NovaNoticeService.live().feed(identity)) ?? .empty
        }
        .onChange(of: scenePhase) { phase in
            // Screenshots, permission prompts and Control Center can cause inactive → active.
            // They are not a new session and must not destroy a sheet or its draft.
            if sceneRevalidation.update(isBackground: phase == .background, isActive: phase == .active) {
                if !previewOnly { controller.refresh() }
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
                    Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
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
