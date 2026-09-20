import SwiftUI
import Supabase

struct NovaFollowupPage: Decodable {
    let schema_version: Int; let owner_id: UUID; let company_id: UUID?
    let current: Int; let soon: Int; let expired: Int; let undated: Int
    let has_more: Bool; let rows: [Row]
    struct Row: Decodable, Identifiable {
        let kind: String; let company_id: UUID; let company_name: String
        let record_id: UUID; let source_id: UUID?; let title: String; let due_on: String?; let status: String
        var id: String { kind + record_id.uuidString }
        var typeTitle: String {
            switch kind {
            case "training": return "Eğitim"
            case "equipment": return "Periyodik kontrol"
            case "risk_assessment": return "Risk değerlendirmesi"
            case "emergency_plan": return "Acil durum planı"
            case "appointment": return "Atama"
            case "document": return "Önceki evrak kaydı"
            case "file": return "Dosya"
            default: return NovaProcessKind.get(kind).title
            }
        }
    }
    static func statusTitle(_ status: String) -> String { ["current":"Güncel","soon":"Yaklaşıyor","expired":"Süresi doldu","undated":"Süre takibi yok"][status] ?? status }
}
@MainActor struct NovaFollowupService {
    let identity: NovaSessionIdentity
    func load(company: UUID?, status: String? = nil, query: String = "", offset: Int = 0) async throws -> NovaFollowupPage {
        try check()
        let data = try await SupabaseService.shared.client.rpc("isg_pilot_followup_v1", params: ["p_company": PersonnelRPCValue.id(company), "p_status": status.map(PersonnelRPCValue.string) ?? .null, "p_query": .string(query), "p_offset": .number(Int64(offset))]).execute().data
        try check(); try Task.checkCancellation()
        let result = try JSONDecoder().decode(NovaFollowupPage.self, from: data)
        guard result.schema_version == 1, result.owner_id == identity.userID, result.company_id == company else { throw NovaPPEFailure.denied }
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
    var legacy: ((UUID) -> AnyView)?
    @State private var company: UUID?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var page: NovaFollowupPage?
    @State private var rows: [NovaFollowupPage.Row] = []
    @State private var query = ""
    @State private var status = ""
    @State private var busy = false
    @State private var failure = false
    @State private var selected: NovaFollowupPage.Row?
    @State private var trainingSource: NovaFollowupPage.Row?
    @State private var revision = 0
    private var requestKey: String { "\(company?.uuidString ?? "all"):\(status):\(revision)" }
    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: "Evrak Takibi", onBack: onBack)
                    NovaHelpHint(text: "Süreler ilgili modüldeki kayıttan otomatik gelir. Bir kaydı açarak kaynağındaki bilgileri düzenleyebilirsiniz.")
                    if initialCompany == nil {
                        NovaFilterField(label: "Firma", options: [.init(id: nil, title: "Tüm firmalar")] + companies.map { .init(id: $0.id.uuidString, title: $0.name) },
                            selected: company?.uuidString, identifier: "followup.company") { company = $0.flatMap(UUID.init(uuidString:)) }
                    }
                    if let page { summary(page) }
                    HStack { Image(systemName: "magnifyingglass"); TextField("Evrak veya firma ara", text: $query).onSubmit { revision += 1 }; Button("Ara") { revision += 1 } }
                        .padding(12).background(.white, in: RoundedRectangle(cornerRadius: 14))
                    NovaFilterField(label: "Durum", options: [.init(id: nil, title: "Tüm durumlar")] + ["current", "soon", "expired", "undated"].map { .init(id: $0, title: NovaFollowupPage.statusTitle($0)) },
                        selected: status.isEmpty ? nil : status, identifier: "followup.status") { status = $0 ?? "" }
                    if busy && rows.isEmpty { ProgressView("Evraklar yükleniyor…").frame(maxWidth: .infinity) }
                    if failure { NovaText(text: "Evrak takibi alınamadı.", style: .meta); Button("Yeniden dene") { revision += 1 } }
                    if !busy && !failure && rows.isEmpty {
                        NovaEmptyState(title: "Bu filtrede kayıt yok",
                            message: "Süreli kayıtlar ilgili modüllere eklendiğinde yaklaşan ve geciken işler burada tek listede görünür.")
                    }
                    ForEach(rows) { row in
                        Button { if row.kind == "training" { trainingSource = row } else { selected = row } } label: {
                            NovaCard(padding: 16) {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(alignment: .top) { Image(systemName: "doc.text"); NovaText(text: row.title, style: .cardTitle); Spacer(minLength: 4); Image(systemName: "chevron.right") }
                                    NovaText(text: row.company_name + " · " + row.typeTitle, style: .meta)
                                    NovaText(text: NovaFollowupPage.statusTitle(row.status) + (row.due_on.map { " · " + $0 } ?? ""), style: .meta)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(NovaRowPressStyle())
                    }
                    if page?.has_more == true { Button("Daha fazla") { Task { await load(more: true) } }.disabled(busy) }
                }.padding(16)
            }
        }.task { company = initialCompany; companies = (try? await NovaAnalysisWorkspace.companyOptions(identity: identity)) ?? [] }
        .task(id: requestKey) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { _ in revision += 1 }
        .novaPopup(item: $selected) { row in destination(row) }
        .novaFullScreenCover(item: $trainingSource) { row in
            NovaFollowupDestination(identity: identity, row: row, canWrite: canWrite, onBack: { trainingSource = nil })
        }
    }
    private func summary(_ page: NovaFollowupPage) -> some View {
        HStack(spacing: 8) {
            NovaListStat(title: "Güncel", symbol: "checkmark.circle", value: page.current)
            NovaListStat(title: "Yaklaşıyor", symbol: "clock", value: page.soon)
            NovaListStat(title: "Süresi doldu", symbol: "exclamationmark.triangle", value: page.expired)
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
            let result = try await NovaFollowupService(identity: identity).load(company: scope, status: status.isEmpty ? nil : status, query: query, offset: more ? rows.count : 0)
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
                    Label("Evrak süreleri", systemImage: "doc.badge.clock").font(NovaFont.font(.cardTitle))
                    if let page { NovaText(text: "\(page.current) güncel · \(page.soon) yaklaşıyor · \(page.expired) süresi doldu", style: .meta) }
                    else { NovaText(text: "Evrak ve belge sürelerini aç", style: .meta) }
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
    @State private var companies: [NovaPilotCompanySummary] = []
    @State private var writableCompanies: Set<UUID> = []
    @State private var failed = false
    var body: some View {
        Group {
            if let context { NovaEducationEditor(identity: identity, companies: companies, initialCompany: company, original: context.row, context: context, canWrite: canWrite && (context.row?.companies.allSatisfy { writableCompanies.contains($0.company_id) } ?? false), writableCompanies: writableCompanies) }
            else if failed { NovaText(text: "Eğitim açılamadı. Eğitimler listesinden yeniden deneyin.") }
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
    var legacy: ((UUID) -> AnyView)?
    var body: some View {
        switch row.kind {
        case "completed_drill", "personnel_certificate", "katip_contract", "approved_notebook", "site_visit", "board", "board_decision", "annual_work_item":
            NovaProcessEditor(identity: identity, kind: row.kind, company: row.company_id, record: row.record_id, canWrite: canWrite, fileClient: .pilot(identity))
        case "risk_assessment": NovaPilotRiskGate(identity: identity, canWrite: canWrite, initialCompany: row.company_id, onBack: { onBack() })
        case "equipment": NovaPilotEquipmentGate(identity: identity, canWrite: canWrite, initialCompany: row.company_id, onBack: { onBack() })
        case "emergency_plan": NovaPilotEmergencyGate(identity: identity, canWrite: canWrite, initialCompany: row.company_id, onBack: { onBack() })
        case "appointment": NovaPilotAppointmentGate(identity: identity, canWrite: canWrite, initialCompany: row.company_id, onBack: { onBack() })
        case "training": NovaFollowupEducation(identity: identity, session: row.source_id, company: row.company_id, canWrite: canWrite)
        case "document": if let legacy { legacy(row.company_id) } else { NovaText(text: "Önceki evrak kaydı · " + row.title) }
        default: NovaPilotFileGate(identity: identity, canWrite: canWrite, initialCompany: row.company_id, onBack: { onBack() })
        }
    }
}
