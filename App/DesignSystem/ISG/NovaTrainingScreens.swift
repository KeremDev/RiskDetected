import SwiftUI

struct NovaTrainingHub: View {
    let identity: NovaSessionIdentity
    let scope: NovaPersonnelScope?
    let personnel: NovaPersonnelClient
    let canWrite: Bool
    let select: (UUID?) -> Void
    let onBack: () -> Void
    var createOnOpen = false
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                NovaBackButton(action: onBack)
                NovaText(text: "Eğitimler", style: .screenTitle)
                Spacer()
            }.padding(.horizontal, 18).padding(.top, 12)
            NovaTrainingRegister(identity: identity, personnel: personnel, canWrite: canWrite,
                initialCompany: nil, createOnOpen: createOnOpen)
        }
        .novaEdgeBackGesture(action: onBack)
    }
}

struct NovaTrainingCompanyScreen: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let personnel: NovaPersonnelClient
    let canWrite: Bool
    var createOnOpen = false
    var body: some View {
        NovaTrainingRegister(identity: .init(userID: scope.ownerID, sessionID: scope.sessionID),
            personnel: personnel, canWrite: canWrite, initialCompany: scope.companyID, createOnOpen: createOnOpen)
    }
}

struct NovaTrainingRegister: View {
    let identity: NovaSessionIdentity
    let personnel: NovaPersonnelClient
    let canWrite: Bool
    let initialCompany: UUID?
    var createOnOpen = false
    @State private var companies: [NovaPilotCompanySummary] = []
    @State private var sessions: [NovaTrainingSession] = []
    @State private var catalog: [NovaTrainingCatalog] = []
    @State private var writableCompanies = Set<UUID>()
    @State private var company: UUID?
    @State private var query = ""
    @State private var cycleFilter = ""
    @State private var dateFilter = ""
    @State private var loading = false
    @State private var error: String?
    @State private var pending = false
    @State private var revision = UUID()
    @State private var didOpen = false
    @State private var initializedFilter = false
    @State private var employeeTotal: Int?
    @State private var editor: Editor?
    private struct Editor: Identifiable { let id = UUID(); let session: NovaTrainingSession? }
    private var service: NovaTrainingSessionService { .init(identity: identity) }
    private var visible: [NovaTrainingSession] {
        sessions.filter { (company == nil || $0.companies.contains { $0.company_id == company }) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.trainer.localizedCaseInsensitiveContains(query)) &&
            (dateFilter.isEmpty || $0.held_on.hasPrefix(dateFilter)) &&
            (cycleFilter.isEmpty || $0.education?.scopes.contains { $0.cycle == cycleFilter } == true) }
        .sorted { $0.held_on > $1.held_on }
    }
    private var completedScopes: [NovaTrainingSession.Company] {
        sessions.flatMap(\.companies).filter { row in
            row.state == "completed" && (company == nil || row.company_id == company)
        }
    }
    private var trainedPeople: Set<UUID> {
        Set(completedScopes.flatMap { $0.participants.filter(\.attended).map(\.id) })
    }
    private var trainingMinutes: Int { completedScopes.reduce(0) { $0 + $1.duration_minutes } }
    private var personMinutes: Int {
        completedScopes.reduce(0) { $0 + $1.duration_minutes * $1.participants.filter(\.attended).count }
    }
    private func hours(_ minutes: Int) -> String {
        let value = Double(minutes) / 60
        return value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaFilterField(label: "Firma", options: [.init(id: nil, title: "Tüm firmalar")] + companies.map { .init(id: $0.id.uuidString, title: $0.name) },
                        selected: company?.uuidString, identifier: "training.company") { company = $0.flatMap(UUID.init(uuidString:)) }
                    Button { editor = Editor(session: nil) } label: {
                        Label("Eğitim Ekle", systemImage: "plus").font(.system(size: 13))
                            .padding(.horizontal, 16).frame(minHeight: 36).background(Color.green, in: Capsule()).foregroundStyle(.black)
                    }.disabled(!canWrite || loading || pending || error != nil || writableCompanies.isEmpty)
                }
                NovaHelpHint(text: "Gerçekleşen eğitimi ve katılımcılarını kaydedin. Aynı eğitimde birden fazla firmanın personelini seçebilirsiniz.")
                trainingStats
                NovaCard(padding: 12) {
                    HStack { Image(systemName: "magnifyingglass"); TextField("Eğitim veya eğitmen ara…", text: $query) }
                }
                NovaFilterField(label: "Eğitim türü", options: [.init(id: nil, title: "Tüm eğitim türleri")] + NovaEducationScope.cycles.map { .init(id: $0.0, title: $0.1) },
                    selected: cycleFilter.isEmpty ? nil : cycleFilter, identifier: "training.cycle") { cycleFilter = $0 ?? "" }
                TextField("Tarih (YYYY-AA-GG)", text: $dateFilter).font(NovaFont.font(.meta))
                Text("\(visible.count) eğitim").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                if pending {
                    NovaHelpHint(text: "Önceki işlemin sonucu bekleniyor. Aynı kaydı güvenle tamamlayın.")
                    NovaButton(label: "Bekleyen işlemi tamamla", symbol: "arrow.clockwise", isEnabled: canWrite && !loading) {
                        Task { await retry() }
                    }
                }
                if let error { NovaHelpHint(text: error); Button("Yenile") { revision = UUID() } }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !loading && error == nil && visible.isEmpty {
                    NovaEmptyState(title: "Henüz eğitim kaydı yok",
                        message: "Gerçekleşen eğitimi ekleyerek katılımcıları, süreleri ve eksik eğitim konularını personel bazında takip edebilirsiniz.")
                }
                ForEach(visible) { session in
                    Button { editor = Editor(session: session) } label: {
                        NovaCard(padding: 15) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "graduationcap")
                                    Text(session.title).font(NovaFont.font(.cardTitle))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(NovaFont.font(.meta))
                                }
                                HStack {
                                    Label(session.held_on, systemImage: "calendar")
                                    Label("\(session.count)", systemImage: "person.2")
                                    Text(trainingMethodName(session.method))
                                }.font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                                Text(session.companies.map(\.company_name).joined(separator: " · ")).font(NovaFont.font(.meta)).lineLimit(2)
                                if session.isLegacyPlan {
                                    Text("Önceki plan · gerçekleştiği henüz doğrulanmadı").font(NovaFont.font(.meta)).foregroundStyle(.orange)
                                } else if session.companies.allSatisfy({ $0.state == "cancelled" }) {
                                    Text("Önceki iptal kaydı").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(NovaRowPressStyle())
                }
            }.padding(18).novaPopupContentSize()
        }.task(id: revision) { await load() }
            .task(id: company) { await loadEmployeeTotal() }
            .onAppear { if !initializedFilter { company = initialCompany; initializedFilter = true } }
            .refreshable { revision = UUID() }
            .novaFullScreenCover(item: $editor, onDismiss: { revision = UUID() }) { value in
                // A full page, not a popup: the entry supplies its own back
                // control and accordion chrome (the pre-catalogue fallback
                // path still uses its own small card internally).
                NovaEducationEntry(identity: identity, personnel: personnel, companies: companies,
                    initialCompany: company, catalog: catalog, original: value.session,
                    canWrite: canWrite && (value.session?.companies.allSatisfy { writableCompanies.contains($0.company_id) } ?? !writableCompanies.isEmpty),
                    writableCompanies: writableCompanies)
            }
    }
    private var trainingStats: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NovaListStat(title: "Eğitim saati", symbol: "clock", value: hours(trainingMinutes)).frame(width: 104)
                NovaListStat(title: "Eğitim alan", symbol: "person.2", value: trainedPeople.count).frame(width: 104)
                NovaListStat(title: "Adam × saat", symbol: "person.badge.clock", value: hours(personMinutes)).frame(width: 104)
                NovaListStat(title: "Eğitimi eksik", symbol: "person.crop.circle.badge.exclamationmark",
                    value: employeeTotal.map { max(0, $0 - trainedPeople.count) }.map(String.init) ?? "—")
                    .frame(width: 104)
            }.padding(.vertical, 2)
        }.accessibilityIdentifier("training.stats")
    }
    @MainActor private func loadEmployeeTotal() async {
        employeeTotal = nil
        guard let company else { return }
        employeeTotal = try? await service.employees(company: company).count
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let loadedCompanies = try await loadNovaPilotOverview(identity: identity)
            var rows: [NovaTrainingSession] = []; var after: UUID?; var seen = Set<UUID>()
            repeat {
                let page = try await service.list(after: after)
                rows += page.rows; catalog = page.catalog; after = page.next_id
                writableCompanies = Set(page.writable_companies)
                if let after, !seen.insert(after).inserted { throw NovaPersonnelFailure.unavailable }
            } while after != nil
            try Task.checkCancellation()
            companies = loadedCompanies.filter { !$0.is_archived }; sessions = rows
            pending = try service.pending() != nil
            if createOnOpen && !didOpen && !pending && canWrite && !writableCompanies.isEmpty { didOpen = true; editor = Editor(session: nil) }
        } catch { if !Task.isCancelled { self.error = NovaTrainingSessionService.message(error) } }
    }
    private func retry() async {
        loading = true
        do { _ = try await service.retry(); revision = UUID() }
        catch { self.error = NovaTrainingSessionService.message(error); loading = false }
    }
}

func trainingMethodName(_ method: String) -> String {
    method == "online" ? "Online" : method == "mixed" ? "Karma" : "Yüz yüze"
}
