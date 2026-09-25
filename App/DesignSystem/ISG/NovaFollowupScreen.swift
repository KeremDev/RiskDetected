import SwiftUI
import Supabase

struct NovaFollowupPage: Decodable {
    let schema_version: Int; let owner_id: UUID; let company_id: UUID?
    let current: Int; let soon: Int; let expired: Int; let undated: Int
    let has_more: Bool; let rows: [Row]
    struct Row: Decodable, Identifiable {
        let kind: String; let company_id: UUID; let company_name: String
        let record_id: UUID; let source_id: UUID?; let title: String
        let recorded_on: String?; let due_on: String?; let status: String
        var file_category: String? = nil
        var equipment_type: String? = nil
        var equipment_type_label: String? = nil
        var id: String { kind + record_id.uuidString }
        var typeTitle: String { NovaFollowupPage.typeTitle(kind: kind) }
    }
    /// The record type as Evrak Takibi names it; the home cards use the same words.
    static func typeTitle(kind: String) -> String {
        switch kind {
        case "training": return RDLocalization.string("localizable.nova.followup.screen.egitim.e2f9f769", table: .localizable, fallback: "Eğitim")
        case "equipment": return RDLocalization.string("localizable.nova.followup.screen.periyodik.kontrol.b45bd52d", table: .localizable, fallback: "Periyodik kontrol")
        case "risk_assessment": return RDLocalization.string("localizable.nova.followup.screen.risk.analizi.79082240", table: .localizable, fallback: "Risk analizi")
        case "emergency_plan": return RDLocalization.string("localizable.nova.followup.screen.acil.durum.plani.6be8ff28", table: .localizable, fallback: "Acil durum planı")
        case "appointment": return "Atama"
        case "document": return RDLocalization.string("localizable.nova.followup.screen.onceki.evrak.kaydi.698b873e", table: .localizable, fallback: "Önceki evrak kaydı")
        case "file": return "Dosya"
        default: return NovaProcessKind.get(kind).title
        }
    }
    static func statusTitle(_ status: String) -> String { ["current":"Güncel","soon":"Yaklaşıyor","expired":"Süresi doldu","undated":"Süre takibi yok"][status] ?? status }
    static let kindOptions: [(id: String, title: String)] = [
        ("risk_assessment", "Risk analizi"), ("training", "Eğitim"),
        ("equipment", "Periyodik kontrol"), ("emergency_plan", "Acil durum planı"),
        ("file", "Yüklenen dosya"), ("document", "Önceki evrak kaydı"),
        ("personnel_certificate", "Personel belgesi"), ("completed_drill", "Tatbikat"),
        ("appointment", "Atama"), ("katip_contract", "İSG-KATİP sözleşmesi")
    ]
    static func kindTitle(_ kind: String?) -> String {
        kind.flatMap { selected in kindOptions.first { $0.id == selected }?.title } ?? "Tüm evrak türleri"
    }
}
@MainActor struct NovaFollowupService {
    let identity: NovaSessionIdentity
    func load(company: UUID?, status: String? = nil, kind: String? = nil,
              query: String = "", offset: Int = 0) async throws -> NovaFollowupPage {
        try check()
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_followup_v2", params: [
            "p_company": PersonnelRPCValue.id(company),
            "p_status": status.map(PersonnelRPCValue.string) ?? .null,
            "p_kind": kind.map(PersonnelRPCValue.string) ?? .null,
            "p_query": .string(query), "p_offset": .number(Int64(offset))
        ], ticket: NovaExpertTransport.shared.capture())
        try check(); try Task.checkCancellation()
        let result = try JSONDecoder().decode(NovaFollowupPage.self, from: data)
        guard result.schema_version == 2, result.owner_id == identity.userID, result.company_id == company else { throw NovaPPEFailure.denied }
        return result
    }
    private func check() throws {
        guard let session = SupabaseService.shared.client.auth.currentSession, session.user.id == identity.userID, NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID else { throw NovaPPEFailure.denied }
    }
}

struct NovaFollowupScreen: View {
    let identity: NovaSessionIdentity
    var initialCompany: UUID?
    let canWrite: Bool
    let onBack: () -> Void
    var legacy: ((NovaFollowupPage.Row, @escaping () -> Void) -> AnyView)?
    /// Opened from a home card: the list starts on the status the card counted,
    /// so the card and the list show the same records.
    init(identity: NovaSessionIdentity, initialCompany: UUID? = nil, initialStatus: String? = nil, canWrite: Bool,
         onBack: @escaping () -> Void, legacy: ((NovaFollowupPage.Row, @escaping () -> Void) -> AnyView)? = nil) {
        self.identity = identity; self.initialCompany = initialCompany; self.canWrite = canWrite
        self.onBack = onBack; self.legacy = legacy
        _company = State(initialValue: initialCompany)
        _status = State(initialValue: ["current", "soon", "expired", "undated"].contains(initialStatus ?? "") ? initialStatus ?? "" : "")
    }
    @State private var company: UUID?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var page: NovaFollowupPage?
    @State private var rows: [NovaFollowupPage.Row] = []
    @State private var query = ""
    @State private var status = ""
    @State private var kind: String?
    @State private var openFilter: String?
    @State private var busy = false
    @State private var failure = false
    @State private var selected: NovaFollowupPage.Row?
    @State private var trainingSource: NovaFollowupPage.Row?
    @State private var revision = 0
    @Environment(\.dynamicTypeSize) private var typeSize
    private var requestKey: String { "\(company?.uuidString ?? "all"):\(status):\(kind ?? "all"):\(revision)" }
    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: RDLocalization.string("localizable.nova.followup.screen.evrak.takibi.72eac10a", table: .localizable, fallback: "Evrak Takibi"), onBack: onBack)
                    NovaListHint(text: RDLocalization.string("localizable.nova.followup.screen.eklenen.evraklari.firma.ve.ture.gore.izleyin.kay.f039c4fa", table: .localizable, fallback: "Eklenen evrakları firma ve türe göre izleyin. Kayıt tarihi ve varsa geçerlilik süresi kaynağından gelir; karta dokunarak belge detayını açın."))
                    if let page { summary(page) }
                    NovaAnalysisSearchField(text: $query,
                        placeholder: RDLocalization.string("localizable.nova.followup.screen.evrak.veya.firma.ara.7a66a46d", table: .localizable, fallback: "Evrak veya firma ara"),
                        identifier: "followup.search")
                        .onSubmit { revision += 1 }
                    filters
                    if busy && rows.isEmpty { ProgressView("Evraklar yükleniyor…").frame(maxWidth: .infinity) }
                    if failure { NovaText(text: RDLocalization.string("localizable.nova.followup.screen.evrak.takibi.alinamadi.8599ee59", table: .localizable, fallback: "Evrak takibi alınamadı."), style: .meta); Button(RDLocalization.string("localizable.nova.followup.screen.yeniden.dene.c5c2272a", table: .localizable, fallback: "Yeniden dene")) { revision += 1 } }
                    NovaListSectionHeading(title: RDLocalization.string("localizable.nova.followup.list.title", table: .localizable, fallback: "Evraklar"),
                        count: RDLocalization.format("localizable.nova.followup.list.count", table: .localizable, fallback: "%@ kayıt",
                            arguments: [page?.has_more == true ? "\(rows.count)+" : String(rows.count)]))
                    if !busy && !failure && rows.isEmpty {
                        NovaEmptyState(title: RDLocalization.string("localizable.nova.followup.screen.bu.filtrede.evrak.yok.fe176eb3", table: .localizable, fallback: "Bu filtrede evrak yok"),
                            message: RDLocalization.string("localizable.nova.followup.screen.firma.evrak.turu.veya.durum.filtresini.degistiri.9ee2bc44", table: .localizable, fallback: "Firma, evrak türü veya durum filtresini değiştirin."))
                    }
                    ForEach(rows) { row in
                        Button { if row.kind == "training" { trainingSource = row } else { selected = row } } label: {
                            NovaCard(padding: 16) {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .top) { Image(systemName: "doc.text"); NovaText(text: row.title, style: .cardTitle); Spacer(minLength: 4); Image(systemName: "chevron.right") }
                                    NovaText(text: row.company_name + " · " +
                                        (row.file_category.map(NovaFileWords.category) ?? row.typeTitle), style: .meta)
                                    if let recorded = row.recorded_on {
                                        NovaText(text: RDLocalization.string("localizable.nova.followup.screen.kayit.17ddb357", table: .localizable, fallback: "Kayıt: ") + NovaStatisticsSnapshot.dayLabel(recorded), style: .metaQuiet)
                                    }
                                    NovaText(text: row.due_on.map { "Geçerlilik: " + NovaStatisticsSnapshot.dayLabel($0) + " · " + NovaFollowupPage.statusTitle(row.status) }
                                        ?? "Geçerlilik tarihi yok", style: .meta)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(NovaRowPressStyle())
                    }
                    if page?.has_more == true { Button(RDLocalization.string("localizable.nova.followup.screen.daha.fazla.c93627b1", table: .localizable, fallback: "Daha fazla")) { Task { await load(more: true) } }.disabled(busy) }
                }.padding(16)
            }
        }.task { company = initialCompany; companies = (try? await NovaAnalysisWorkspace.companyOptions(identity: identity)) ?? [] }
        .onAppear { NovaForYouOutbox.recordUse("followup") }
        .task(id: requestKey) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { _ in revision += 1 }
        .novaPopup(item: $selected) { row in destination(row) }
        .novaFullScreenCover(item: $trainingSource) { row in
            NovaFollowupDestination(identity: identity, row: row, canWrite: canWrite, onBack: { trainingSource = nil })
        }
    }
    private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                if initialCompany == nil {
                    NovaFileChooserButton(label: "Firma", value: companies.first { $0.id == company }?.name ?? "Tüm firmalar",
                        isOpen: openFilter == "company", identifier: "followup.company") {
                        openFilter = openFilter == "company" ? nil : "company"
                    }
                }
                NovaFileChooserButton(label: "Durum", value: status.isEmpty ? "Tüm durumlar" : NovaFollowupPage.statusTitle(status),
                    isOpen: openFilter == "status", identifier: "followup.status") {
                    openFilter = openFilter == "status" ? nil : "status"
                }
            }
            if openFilter == "company" {
                NovaFileChooserPanel(options: [.init(id: nil, title: RDLocalization.string("localizable.nova.followup.screen.tum.firmalar.7a489774", table: .localizable, fallback: "Tüm firmalar"))] + companies.map { .init(id: $0.id.uuidString, title: $0.name) },
                    selected: company?.uuidString, identifier: "followup.company.options") { value in
                    company = value.flatMap(UUID.init(uuidString:)); openFilter = nil
                }
            }
            if openFilter == "status" {
                NovaFileChooserPanel(options: [.init(id: nil, title: RDLocalization.string("localizable.nova.followup.screen.tum.durumlar.1867ff2d", table: .localizable, fallback: "Tüm durumlar"))] + ["current", "soon", "expired", "undated"].map {
                    .init(id: $0, title: NovaFollowupPage.statusTitle($0))
                }, selected: status.isEmpty ? nil : status, identifier: "followup.status.options") { value in
                    status = value ?? ""; openFilter = nil
                }
            }
            NovaFileChooserButton(label: RDLocalization.string("localizable.nova.followup.screen.evrak.turu.a1b560c1", table: .localizable, fallback: "Evrak türü"), value: NovaFollowupPage.kindTitle(kind),
                isOpen: openFilter == "kind", identifier: "followup.kind") {
                openFilter = openFilter == "kind" ? nil : "kind"
            }
            if openFilter == "kind" {
                NovaFileChooserPanel(options: [.init(id: nil, title: RDLocalization.string("localizable.nova.followup.screen.tum.evrak.turleri.45995fed", table: .localizable, fallback: "Tüm evrak türleri"))] + NovaFollowupPage.kindOptions.map { .init(id: $0.id, title: $0.title) },
                    selected: kind, identifier: "followup.kind.options") { value in
                    kind = value; openFilter = nil
                }
            }
        }
    }
    private func summary(_ page: NovaFollowupPage) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                 count: typeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
            NovaListStat(title: RDLocalization.string("localizable.nova.followup.screen.guncel.56e5ec8b", table: .localizable, fallback: "Güncel"), symbol: "checkmark.circle", value: page.current, status: .success)
            NovaListStat(title: RDLocalization.string("localizable.nova.followup.screen.yaklasiyor.89e7eb9b", table: .localizable, fallback: "Yaklaşıyor"), symbol: "clock", value: page.soon, status: .warning)
            NovaListStat(title: RDLocalization.string("localizable.nova.followup.screen.suresi.doldu.fe9be698", table: .localizable, fallback: "Süresi doldu"), symbol: "exclamationmark.triangle", value: page.expired, status: .danger)
            NovaListStat(title: RDLocalization.string("localizable.nova.followup.screen.tarih.yok.56ba7a76", table: .localizable, fallback: "Tarih yok"), symbol: "calendar", value: page.undated, status: .neutral)
        }
    }
    private func destination(_ row: NovaFollowupPage.Row) -> some View {
        NovaFollowupDestination(identity: identity, row: row, canWrite: canWrite, onBack: { selected = nil }, legacy: legacy)
    }
    private func load(more: Bool = false) async {
        let key = requestKey; let scope = company; busy = true; failure = false
        if !more { rows = []; page = nil }
        defer { if key == requestKey { busy = false } }
        do {
            let result = try await NovaFollowupService(identity: identity).load(company: scope, status: status.isEmpty ? nil : status,
                kind: kind, query: query, offset: more ? rows.count : 0)
            guard key == requestKey else { return }
            page = result; rows = more ? rows + result.rows : result.rows
        } catch { if key == requestKey && !Task.isCancelled { failure = true } }
    }
}

struct NovaFollowupSummaryCard: View {
    let identity: NovaSessionIdentity
    var company: UUID?
    var canWrite = false
    @State private var page: NovaFollowupPage?
    @State private var show = false
    @State private var revision = 0
    var body: some View {
        Button { show = true } label: {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(RDLocalization.string("localizable.nova.followup.screen.evrak.sureleri.e6000ce2", table: .localizable, fallback: "Evrak süreleri"), systemImage: "doc.badge.clock").font(NovaFont.font(.cardTitle))
                    if let page { NovaText(text: RDLocalization.format("localizable.nova.followup.screen.1.guncel.2.yaklasiyor.3.suresi.doldu.4.tarihsiz.19e62e7b", table: .localizable, fallback: "%1$@ güncel · %2$@ yaklaşıyor · %3$@ süresi doldu · %4$@ tarihsiz", arguments: [String(describing: page.current), String(describing: page.soon), String(describing: page.expired), String(describing: page.undated)]), style: .meta) }
                    else { NovaText(text: RDLocalization.string("localizable.nova.followup.screen.evrak.ve.belge.surelerini.ac.f9a1029d", table: .localizable, fallback: "Evrak ve belge sürelerini aç"), style: .meta) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(NovaRowPressStyle())
        .task(id: "\(company?.uuidString ?? "all"):\(revision)") { page = try? await NovaFollowupService(identity: identity).load(company: company) }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { _ in revision += 1 }
        .novaPopup(isPresented: $show) { NovaFollowupScreen(identity: identity, initialCompany: company, canWrite: canWrite, onBack: { show = false }) }
    }
}

private struct NovaFollowupEducation: View {
    let identity: NovaSessionIdentity; let session: UUID?; let company: UUID; let canWrite: Bool
    @State private var context: NovaEducationContext?
    @State private var savedCertificate: NovaTrainingSession?
    @State private var companies: [NovaPilotCompanySummary] = []
    @State private var writableCompanies: Set<UUID> = []
    @State private var failed = false
    var body: some View {
        Group {
            if let savedCertificate {
                NovaEducationCertificatesPage(identity: identity, session: savedCertificate,
                    canIssue: canWrite, showSavedCelebration: true)
            } else if let context {
                NovaEducationEditor(identity: identity, companies: companies, initialCompany: company,
                    original: context.row, context: context,
                    canWrite: canWrite && (context.row?.companies.allSatisfy { writableCompanies.contains($0.company_id) } ?? false),
                    writableCompanies: writableCompanies,
                    onSaved: { savedCertificate = $0 })
            }
            else if failed { NovaText(text: RDLocalization.string("localizable.nova.followup.screen.egitim.acilamadi.egitimler.listesinden.yeniden.d.c7e512d9", table: .localizable, fallback: "Eğitim açılamadı. Eğitimler listesinden yeniden deneyin.")) }
            else { ProgressView("Eğitim yükleniyor…") }
        }.task {
            do {
                guard let session else { throw NovaPPEFailure.denied }
                companies = try await loadNovaPilotOverview(identity: identity)
                writableCompanies = Set(try await NovaTrainingSessionService(identity: identity).list(after: nil).writable_companies)
                context = try await NovaEducationService(identity: identity).context(id: session)
            } catch { failed = true }
        }
    }
}

struct NovaFollowupDestination: View {
    let identity: NovaSessionIdentity
    let row: NovaFollowupPage.Row
    let canWrite: Bool
    let onBack: () -> Void
    var legacy: ((NovaFollowupPage.Row, @escaping () -> Void) -> AnyView)?
    var body: some View {
        switch row.kind {
        case "completed_drill", "personnel_certificate", "katip_contract", "approved_notebook", "site_visit", "board", "board_decision", "annual_work_item":
            NovaProcessEditor(identity: identity, kind: row.kind, company: row.company_id, record: row.record_id, canWrite: canWrite, fileClient: .pilot(identity))
        case "risk_assessment": NovaPilotRiskGate(identity: identity, canWrite: canWrite,
            initialCompany: row.company_id, initialRecordID: row.record_id, onBack: { onBack() })
        case "equipment": NovaPilotEquipmentGate(identity: identity, canWrite: canWrite,
            initialCompany: row.company_id, initialRecordID: row.record_id, onBack: { onBack() })
        case "emergency_plan": NovaPilotEmergencyGate(identity: identity, canWrite: canWrite,
            initialCompany: row.company_id, initialRecordID: row.record_id, onBack: { onBack() })
        case "appointment": NovaPilotAppointmentGate(identity: identity, canWrite: canWrite,
            initialCompany: row.company_id, initialRecordID: row.record_id, onBack: { onBack() })
        case "training": NovaFollowupEducation(identity: identity, session: row.source_id, company: row.company_id, canWrite: canWrite)
        case "document": if let legacy { legacy(row, onBack) } else {
            NovaFollowupLegacyDetail(identity: identity, row: row, onBack: onBack)
        }
        case "file": NovaPilotFileGate(identity: identity, canWrite: canWrite,
            initialCompany: row.company_id, initialEntryID: row.record_id, onBack: { onBack() })
        default: NovaPilotFileGate(identity: identity, canWrite: canWrite, initialCompany: row.company_id, onBack: { onBack() })
        }
    }
}

/// The OSGB entry point has no selected personal-company scope. Build a read-only
/// document client for the row's own company; the RPC still verifies access to it.
private struct NovaFollowupLegacyDetail: View {
    let identity: NovaSessionIdentity
    let row: NovaFollowupPage.Row
    let onBack: () -> Void

    private var scope: NovaPersonnelScope {
        .init(ownerID: identity.userID, sessionID: identity.sessionID,
              companyID: row.company_id, epoch: "followup")
    }

    private var client: NovaDocumentTrackingClient {
        let current = scope
        let service = NovaDocumentTrackingService.live(currentScope: { current })
        var value = NovaDocumentTrackingClient(
            portfolio: { request in
                try await service.portfolio(identity, query: request.query, status: request.status,
                    company: request.company, kinds: request.kinds,
                    limit: request.limit, offset: request.offset)
            },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            kinds: { _ in try await service.kinds(current) },
            workplaces: { _ in try await service.workplaces(current) },
            add: { _, _ in throw NovaDocumentFailure.denied },
            update: { _, _ in throw NovaDocumentFailure.denied },
            archive: { _ in throw NovaDocumentFailure.denied },
            recordCopy: { _, _ in throw NovaDocumentFailure.denied },
            removeCopy: { _, _ in throw NovaDocumentFailure.denied })
        value.detail = { _, record in try await service.detail(current, obligation: record) }
        return value
    }

    var body: some View {
        NovaDocumentTrackingScreen(client: client, onBack: onBack, canWrite: false,
            initialCompany: row.company_id, initialRecordID: row.record_id,
            headingOverride: "Önceki Evrak Kaydı")
    }
}
