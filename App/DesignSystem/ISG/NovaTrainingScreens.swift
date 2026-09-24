import SwiftUI

struct NovaTrainingHub: View {
    let identity: NovaSessionIdentity
    let scope: NovaPersonnelScope?
    let personnel: NovaPersonnelClient
    let canWrite: Bool
    let select: (UUID?) -> Void
    let onBack: () -> Void
    var createOnOpen = false
    /// Opens on the trainings a home card counted, until the filter is removed.
    var initialPreset: NovaListPreset? = nil
    var onPresetCleared: () -> Void = {}
    @State private var createRequest = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaBackButton(action: onBack)
                    NovaText(text: RDLocalization.string("localizable.nova.training.screens.egitimler.b7f2e2e3", table: .localizable, fallback: "Eğitimler"), style: .screenTitle)
                    Spacer(minLength: 0)
                }
                if canWrite {
                    NovaListActionButton(title: RDLocalization.string("localizable.nova.training.screens.egitim.ekle.a755e696", table: .localizable, fallback: "Eğitim Ekle"),
                        symbol: "plus", tone: .primary, identifier: "training.add.header") {
                        createRequest += 1
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 12)
            NovaTrainingRegister(identity: identity, personnel: personnel, canWrite: canWrite,
                initialCompany: nil, createOnOpen: createOnOpen, createRequest: createRequest,
                initialPreset: initialPreset, onPresetCleared: onPresetCleared)
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
    var createRequest = 0
    var initialPreset: NovaListPreset? = nil
    var onPresetCleared: () -> Void = {}
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
    @State private var createPending = false
    @State private var createMessage: String?
    @State private var initializedFilter = false
    @State private var employeeTotal: Int?
    @State private var editor: Editor?
    @State private var certificatePage: CertificatePage?
    @State private var certificatePageAfterEditor: CertificatePage?
    /// A home card's filter: completed sessions held on its days, and in an
    /// organization only the member's own. The totals follow it.
    @State private var preset: NovaListPreset?
    @State private var presetApplied = false
    @Environment(\.dynamicTypeSize) private var typeSize
    private struct Editor: Identifiable { let id = UUID(); let session: NovaTrainingSession? }
    private struct CertificatePage: Identifiable {
        let id = UUID()
        let session: NovaTrainingSession
        let created: Bool
    }
    private var service: NovaTrainingSessionService { .init(identity: identity) }
    private func editable(_ session: NovaTrainingSession) -> Bool {
        canWrite && session.companies.allSatisfy { writableCompanies.contains($0.company_id) }
    }
    private func matchesPreset(_ session: NovaTrainingSession) -> Bool {
        guard let preset else { return true }
        return preset.includes(day: session.held_on) && session.companies.contains { $0.state == "completed" }
            && (preset.mine == nil || session.created_by_user_id == preset.mine)
    }
    private var visible: [NovaTrainingSession] {
        sessions.filter { matchesPreset($0) && (company == nil || $0.companies.contains { $0.company_id == company }) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.trainer.localizedCaseInsensitiveContains(query)) &&
            (dateFilter.isEmpty || $0.held_on.hasPrefix(dateFilter)) &&
            (cycleFilter.isEmpty || $0.education?.scopes.contains { $0.cycle == cycleFilter } == true) }
        .sorted { $0.held_on > $1.held_on }
    }
    private var completedScopes: [NovaTrainingSession.Company] {
        sessions.filter(matchesPreset).flatMap(\.companies).filter { row in
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
                NovaListHint(text: RDLocalization.string("localizable.nova.training.screens.gerceklesen.egitimi.ve.katilimcilarini.kaydedin..d89372f5", table: .localizable, fallback: "Gerçekleşen eğitimi ve katılımcılarını kaydedin. Aynı eğitimde birden fazla firmanın personelini seçebilirsiniz."))
                if let createMessage { NovaHelpHint(text: createMessage) }
                if let preset {
                    NovaListPresetChip(preset: preset) { self.preset = nil; onPresetCleared() }
                }
                trainingStats
                NovaAnalysisSearchField(text: $query,
                    placeholder: RDLocalization.string("localizable.nova.training.screens.egitim.veya.egitmen.ara.e5972c31", table: .localizable, fallback: "Eğitim veya eğitmen ara…"),
                    identifier: "training.search")
                NovaAnalysisSearchField(text: $dateFilter,
                    placeholder: RDLocalization.string("localizable.nova.training.screens.tarih.yyyy.aa.gg.d01f7dc7", table: .localizable, fallback: "Tarih (YYYY-AA-GG)"),
                    identifier: "training.date", symbol: "calendar")
                HStack(spacing: 8) {
                    NovaFilterField(label: "Firma", options: [.init(id: nil, title: RDLocalization.string("localizable.nova.training.screens.tum.firmalar.5b83def5", table: .localizable, fallback: "Tüm firmalar"))] + companies.map { .init(id: $0.id.uuidString, title: $0.name) },
                        selected: company?.uuidString, identifier: "training.company") { company = $0.flatMap(UUID.init(uuidString:)) }
                        .frame(maxWidth: .infinity)
                    NovaFilterField(label: RDLocalization.string("localizable.nova.training.screens.egitim.turu.1d83c7fd", table: .localizable, fallback: "Eğitim türü"), options: [.init(id: nil, title: RDLocalization.string("localizable.nova.training.screens.tum.egitim.turleri.eed447b6", table: .localizable, fallback: "Tüm eğitim türleri"))] + NovaEducationScope.cycles.map { .init(id: $0.0, title: $0.1) },
                        selected: cycleFilter.isEmpty ? nil : cycleFilter, identifier: "training.cycle") { cycleFilter = $0 ?? "" }
                        .frame(maxWidth: .infinity)
                }
                NovaListSectionHeading(title: RDLocalization.string("localizable.nova.training.screens.egitimler.b7f2e2e3", table: .localizable, fallback: "Eğitimler"),
                    count: RDLocalization.format("localizable.nova.training.screens.1.egitim.07b9d9c8", table: .localizable, fallback: "%1$@ eğitim", arguments: [String(describing: visible.count)]))
                if pending {
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.training.screens.onceki.islemin.sonucu.bekleniyor.ayni.kaydi.guve.840d8402", table: .localizable, fallback: "Önceki işlemin sonucu bekleniyor. Aynı kaydı güvenle tamamlayın."))
                    NovaButton(label: RDLocalization.string("localizable.nova.training.screens.bekleyen.islemi.tamamla.8e8fc724", table: .localizable, fallback: "Bekleyen işlemi tamamla"), symbol: "arrow.clockwise", isEnabled: canWrite && !loading) {
                        Task { await retry() }
                    }
                }
                if let error { NovaHelpHint(text: error); Button("Yenile") { revision = UUID() } }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if !loading && error == nil && visible.isEmpty {
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.training.screens.henuz.egitim.kaydi.yok.0cf4c592", table: .localizable, fallback: "Henüz eğitim kaydı yok"),
                        message: RDLocalization.string("localizable.nova.training.screens.gerceklesen.egitimi.ekleyerek.katilimcilari.sure.26d67c9e", table: .localizable, fallback: "Gerçekleşen eğitimi ekleyerek katılımcıları, süreleri ve eksik eğitim konularını personel bazında takip edebilirsiniz."))
                }
                ForEach(visible) { session in
                    Button { editor = Editor(session: session) } label: {
                        NovaCard(padding: 15) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "graduationcap")
                                    Text(session.title).font(NovaFont.font(.cardTitle))
                                    Spacer()
                                    Label(editable(session) ? "Düzenle" : "Aç", systemImage: editable(session) ? "pencil" : "chevron.right")
                                        .font(NovaFont.font(.meta))
                                        .foregroundStyle(NovaFont.secondaryInk)
                                }
                                HStack {
                                    Label(session.held_on, systemImage: "calendar")
                                    Label("\(session.count)", systemImage: "person.2")
                                    Text(trainingMethodName(session.method))
                                }.font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                                Text(session.companies.map(\.company_name).joined(separator: " · ")).font(NovaFont.font(.meta)).lineLimit(2)
                                if session.isLegacyPlan {
                                    Text(RDLocalization.string("localizable.nova.training.screens.onceki.plan.gerceklestigi.henuz.dogrulanmadi.41c251b8", table: .localizable, fallback: "Önceki plan · gerçekleştiği henüz doğrulanmadı")).font(NovaFont.font(.meta)).foregroundStyle(.orange)
                                } else if session.companies.allSatisfy({ $0.state == "cancelled" }) {
                                    Text(RDLocalization.string("localizable.nova.training.screens.onceki.iptal.kaydi.c652154a", table: .localizable, fallback: "Önceki iptal kaydı")).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.buttonStyle(NovaRowPressStyle())
                }
            }.padding(18).novaPopupContentSize()
        }.task(id: revision) {
            if !presetApplied { presetApplied = true; preset = initialPreset }
            await load()
        }
            .task(id: company) { await loadEmployeeTotal() }
            .onAppear { if !initializedFilter { company = initialCompany; initializedFilter = true } }
            .onChange(of: createRequest) { _ in
                requestCreate()
            }
            .refreshable { revision = UUID() }
            .novaFullScreenCover(item: $editor, onDismiss: {
                revision = UUID()
                if let next = certificatePageAfterEditor {
                    certificatePageAfterEditor = nil
                    certificatePage = next
                }
            }) { value in
                // A full page, not a popup: every role receives the same
                // five-step editor and its own back/accordion chrome.
                NovaEducationEntry(identity: identity, companies: companies,
                    initialCompany: company, original: value.session,
                    canWrite: value.session.map(editable) ?? (canWrite && !writableCompanies.isEmpty),
                    writableCompanies: writableCompanies,
                    onSaved: { session in
                        certificatePageAfterEditor = .init(session: session, created: value.session == nil)
                        editor = nil
                    }, onDeleted: { editor = nil })
            }
            .novaFullScreenCover(item: $certificatePage, onDismiss: { revision = UUID() }) { page in
                NovaEducationCertificatesPage(identity: identity, session: page.session,
                    canIssue: canWrite, showSavedCelebration: true, created: page.created)
            }
    }
    private var trainingStats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
            NovaListStat(title: RDLocalization.string("localizable.nova.training.screens.egitim.saati.e609ca65", table: .localizable, fallback: "Eğitim saati"), symbol: "clock", value: hours(trainingMinutes))
            NovaListStat(title: RDLocalization.string("localizable.nova.training.screens.egitim.alan.9b6e442b", table: .localizable, fallback: "Eğitim alan"), symbol: "person.2", value: "\(trainedPeople.count)", status: .success)
            NovaListStat(title: RDLocalization.string("localizable.nova.training.screens.adam.saat.5bf33e14", table: .localizable, fallback: "Adam × saat"), symbol: "person.badge.clock", value: hours(personMinutes))
            NovaListStat(title: RDLocalization.string("localizable.nova.training.screens.egitimi.eksik.b6d8ae8f", table: .localizable, fallback: "Eğitimi eksik"), symbol: "person.crop.circle.badge.exclamationmark", value: employeeTotal.map { String(max(0, $0 - trainedPeople.count)) } ?? "—", status: .warning)
        }.accessibilityIdentifier("training.stats")
    }
    @MainActor private func loadEmployeeTotal() async {
        employeeTotal = nil
        guard let company else { return }
        employeeTotal = try? await service.employees(company: company).count
    }
    private func load() async {
        loading = true; error = nil
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
        } catch { if !Task.isCancelled { self.error = NovaTrainingSessionService.message(error) } }
        guard !Task.isCancelled else { return }
        loading = false
        if createOnOpen && !didOpen {
            didOpen = true
            createPending = true
        }
        presentRequestedCreate()
    }

    private func requestCreate() {
        createPending = true
        if loading {
            createMessage = "Eğitim bilgileri hazırlanıyor…"
        } else if error != nil || writableCompanies.isEmpty {
            // A newly granted company may not be in this screen's cached page.
            createMessage = "Eğitim bilgileri güncelleniyor…"
            revision = UUID()
        } else {
            presentRequestedCreate()
        }
    }

    private func presentRequestedCreate() {
        guard createPending, !loading else { return }
        if let error {
            createMessage = "Eğitim ekranı açılamadı: \(error) Yenile ile tekrar deneyin."
            return
        }
        guard canWrite else {
            createMessage = "Bu hesapta eğitim kaydı oluşturma yetkisi yok."
            createPending = false
            return
        }
        guard !pending else {
            createMessage = "Önce bekleyen eğitim işlemini tamamlayın."
            createPending = false
            return
        }
        guard !writableCompanies.isEmpty else {
            createMessage = "Eğitim ekleyebileceğiniz firma bulunamadı. Firma erişiminizi kontrol edin."
            createPending = false
            return
        }
        createPending = false
        createMessage = nil
        editor = Editor(session: nil)
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
