import SwiftUI

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
            NovaPilotRoot(identity: .init(userID: session.user.id, sessionID: sessionID))
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

struct NovaPilotRoot: View {
    let identity: NovaSessionIdentity
    var previewOnly = false
    @EnvironmentObject private var app: AppState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var controller = NovaWorkspaceController()
    @State private var navigation = NovaNavigationState(epoch: UUID().uuidString, available: [.companies, .newCompany, .findings, .newFinding])
    @State private var showingCreate = false
    @State private var notice: String?
    @State private var listRevision = UUID()
    @State private var overview: [NovaPilotCompanySummary]?
    @State private var overviewFailed = false
    @State private var sceneRevalidation = NovaSceneRevalidation()
    private var overviewKey: String { "\(controller.host.navigation.epoch):\(ready):\(listRevision):\(navigation.selected)" }
    private var activeCompanies: [NovaPilotCompanySummary]? { ready ? overview?.filter { !$0.is_archived } : nil }
    private var metrics: [NovaMetricItem] {
        [
            .init(id: "companies", value: activeCompanies.map { String($0.count) } ?? "—", label: "Firmalar", footer: "Aktif pilot", symbol: "building.2", tone: .accent, destination: .companies),
            .init(id: "personnel", value: activeCompanies.map { String($0.reduce(0) { $0 + $1.personnel_count }) } ?? "—", label: "Personel", footer: "Aktif kayıt", symbol: "person.2", tone: .accent, destination: .companies),
            .init(id: "workplaces", value: activeCompanies.map { String($0.reduce(0) { $0 + $1.workplace_count }) } ?? "—", label: "İşyerleri", footer: "Aktif kayıt", symbol: "building.2", tone: .accent, destination: .companies),
            .init(id: "departments", value: activeCompanies.map { String($0.reduce(0) { $0 + $1.department_count }) } ?? "—", label: "Departman", footer: "Aktif kayıt", symbol: "square.grid.2x2", tone: .accent, destination: .companies)
        ]
    }

    private var name: String { app.profile?.fullName ?? "" }
    private var ready: Bool { !previewOnly && controller.isAvailable && controller.host.identity == identity }
    private var status: String {
        if previewOnly { return "Tasarım kontrolü · canlı veri kullanılmıyor" }
        if controller.resolving { return "Pilot erişimi kontrol ediliyor…" }
        return ready ? "Canlı pilot · yalnızca pilot firmalar" : "Canlı pilot erişimi henüz kullanılamıyor"
    }

    var body: some View {
        NovaExpertShell(navigation: $navigation, userName: name, connectionLabel: status,
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
                        trainingMessage: "Eğitim modülü henüz kullanıma açık değil.",
                        summaryMessage: activeCompanies != nil ? "Pilot firmalarınızın güncel kayıtları." : overviewFailed ? "Özet alınamadı. Yenileyerek tekrar deneyin." : "Özet verileri henüz bağlı değil."),
                        onNavigate: navigate, onPhoto: unavailable, onAssistant: unavailable)
                }
            case .companies:
                companies
            case .findings:
                nonconformities(startOnNew: false)
            case .newFinding:
                nonconformities(startOnNew: true)
            case .profile:
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        NovaText(text: "Hesabım", style: .screenTitle)
                        NovaCard(padding: 20) {
                            NovaText(text: name, style: .cardTitle)
                            NovaText(text: "NOVA · özel pilot build", style: .metaQuiet)
                            NovaText(text: status, style: .metaQuiet)
                        }
                        NovaText(text: "Profil düzenleme ve abonelik işlemleri bu pilot arayüzüne henüz bağlanmadı.")
                        NovaButton(label: "Çıkış yap", symbol: "rectangle.portrait.and.arrow.right", variant: .surface) { app.signOut() }
                    }.padding(20)
                }
            default:
                NovaText(text: "Bu modül hazırlanıyor; henüz canlı işlem yapmıyor.").padding(20)
            }
        }
        .preferredColorScheme(.light)
        .overlay(alignment: .topLeading) {
            // A container identifier propagates to SwiftUI toolbar/tab descendants.
            // Keep the QA marker separate so each button retains its own identifier.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityIdentifier("nova.pilot.root")
                .allowsHitTesting(false)
        }
        .fullScreenCover(isPresented: $showingCreate) {
            NovaPopup {
            NovaPilotCompanyCreateView(identity: identity, service: .live()) { companyID in
                listRevision = UUID()
                controller.select(companyID)
            }
            }
        }
        .alert("NOVA pilot", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("Tamam", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
        .task { if !previewOnly { await controller.observe() } }
        .task(id: overviewKey) {
            overview = nil; overviewFailed = false
            guard ready else { return }
            do { overview = try await loadNovaPilotOverview(identity: identity) }
            catch { if !Task.isCancelled { overviewFailed = true } }
        }
        .onChange(of: scenePhase) { phase in
            // Screenshots, permission prompts and Control Center can cause inactive → active.
            // They are not a new session and must not destroy a sheet or its draft.
            if sceneRevalidation.update(isBackground: phase == .background, isActive: phase == .active) {
                if !previewOnly { controller.refresh() }
            }
        }
        .onChange(of: controller.host.identity) { next in
            if next != identity { showingCreate = false; notice = nil }
        }
        .modifier(NovaSuccessPresentation())
    }

    private var statusCard: some View {
        NovaCard(padding: 12) {
            HStack(spacing: 8) {
                Image(systemName: ready ? "checkmark.shield" : "lock.shield")
                NovaText(text: status, style: .metaQuiet)
                Spacer(minLength: 0)
                if !previewOnly {
                    Button { controller.refresh() } label: { Image(systemName: "arrow.clockwise").frame(width: 44, height: 44) }
                        .accessibilityLabel("Pilot erişimini tekrar kontrol et")
                }
            }
        }.padding(.horizontal, 20).padding(.bottom, 10)
    }

    /// Nonconformities live under a selected company: without one there is no
    /// workplace to attach a record to, so the screen asks for the company first.
    @ViewBuilder private func nonconformities(startOnNew: Bool) -> some View {
        if ready, let scope = controller.scope {
            NovaNonconformityDestination(scope: scope, client: nonconformityClient(scope),
                onBack: { navigate(.home) }, canWrite: controller.canWrite,
                onStartPhotoAnalysis: nil, startOnNew: startOnNew)
                .id(scope.epoch)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NovaText(text: NovaDestination.findings.title, style: .screenTitle)
                    statusCard
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.nonconformity.needs.company", table: .localizable,
                        fallback: "Uygunsuzluk kaydı bir firmaya bağlıdır. Önce Firmalar'dan bir firma seçin."))
                    NovaButton(label: NovaDestination.companies.title, symbol: "building.2", variant: .surface) { navigate(.companies) }
                        .accessibilityIdentifier("nonconformity.pick.company")
                }.padding(20)
            }
        }
    }

    private func nonconformityClient(_ scope: NovaPersonnelScope) -> NovaNonconformityClient {
        let service = NovaNonconformityService.live(currentScope: { controller.scope })
        return .init(list: { try await service.list(scope, state: $0) },
                     workplaces: { try await service.workplaces(scope) },
                     open: { try await service.open(scope, intent: $0) })
    }

    @ViewBuilder private var companies: some View {
        if ready, let scope = controller.scope {
            NovaCompanyWorkspace(scope: scope, companyName: controller.capability?.company_name ?? "Firma",
                canWrite: controller.canWrite, personnel: controller.personnelClient, directory: controller.directoryClient,
                onBack: { controller.select(nil) },
                loadSummary: { try await loadNovaPilotOverview(identity: identity, companyID: scope.companyID).first })
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
                    NovaText(text: "Yeni tasarım hazır. Firma işlemleri için canlı pilot servisinin ve hesabınıza ait erişimin açılması gerekiyor. Mevcut firmalarınız otomatik taşınmaz.")
                    NovaButton(label: "Tekrar kontrol et", symbol: "arrow.clockwise", variant: .surface) { controller.select(nil) }
                        .disabled(previewOnly || controller.resolving)
                    NovaButton(label: "Ana sayfaya dön", symbol: "chevron.left", variant: .surface) { navigate(.home) }
                }.padding(20)
            }
        }
    }

    private func navigate(_ destination: NovaDestination) {
        guard navigation.canOpen(destination) else { unavailable(); return }
        navigation.apply(.navigate(destination), from: navigation.epoch)
    }
    private func unavailable() { notice = "Bu modül hazırlanıyor. Bu build’de henüz canlı işlem yapmıyor." }
}
