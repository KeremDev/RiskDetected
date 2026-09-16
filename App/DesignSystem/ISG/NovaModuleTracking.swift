import SwiftUI
import Supabase

struct NovaModuleTrackingSnapshot: Decodable {
    let today: String
    let rows: [Row]
    struct Row: Decodable {
        let company_id: UUID
        let company_name: String
        let kind: String
        let available: Bool
        let total: Int?
        let pending: Int?
        let overdue: Int?
        let upcoming: Int?
        let review: Int?
        let next_on: String?
    }
    struct Summary: Identifiable {
        let id: String
        let available: Bool
        let total: Int
        let pending: Int
        let overdue: Int
        let upcoming: Int
        let review: Int
        let nextOn: String?
        var title: String {
            switch id {
            case "emergency_plan": return "Acil Durum Planları"
            case "drill": return "Tatbikatlar"
            case "appointment": return "Atamalar"
            case "ppe": return "KKD Zimmetleri"
            case "checklist_run": return "Kontrol Listeleri"
            default: return NovaProcessKind.get(id).title
            }
        }
        var symbol: String {
            switch id {
            case "emergency_plan": return "light.beacon.max"
            case "drill": return "figure.run"
            case "appointment": return "person.badge.shield.checkmark"
            case "ppe": return "shield"
            case "checklist_run": return "checklist"
            case "annual_work_plan", "annual_work_item": return "calendar"
            case "board", "board_decision": return "person.3"
            case "site_visit": return "mappin.and.ellipse"
            case "contractor": return "building.2"
            default: return "doc.text"
            }
        }
        var route: String {
            switch id {
            case "annual_work_item": return "annual_work_plan"
            case "board_decision": return "board"
            default: return id
            }
        }
    }
    var summaries: [Summary] {
        Dictionary(grouping: rows, by: \.kind).map { kind, values in
            Summary(id: kind, available: values.allSatisfy(\.available),
                total: values.reduce(0) { $0 + ($1.total ?? 0) },
                pending: values.reduce(0) { $0 + ($1.pending ?? 0) },
                overdue: values.reduce(0) { $0 + ($1.overdue ?? 0) },
                upcoming: values.reduce(0) { $0 + ($1.upcoming ?? 0) },
                review: values.reduce(0) { $0 + ($1.review ?? 0) },
                nextOn: values.compactMap(\.next_on).min())
        }.sorted {
            if $0.overdue != $1.overdue { return $0.overdue > $1.overdue }
            if $0.pending != $1.pending { return $0.pending > $1.pending }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
}

/// Shared, read-time projection for company, home and statistics. No legal score.
struct NovaModuleTrackingCard: View {
    let identity: NovaSessionIdentity
    var company: UUID?
    var canWrite = false
    var onLoaded: ((NovaModuleTrackingSnapshot?) -> Void)?
    @State private var snapshot: NovaModuleTrackingSnapshot?
    @State private var failed = false
    @State private var revision = 0
    @State private var expanded = false
    @State private var opening: Route?
    @Environment(\.scenePhase) private var scenePhase
    private struct Route: Identifiable { let id: String }
    private var key: String { "\(identity.userID):\(identity.sessionID):\(company?.uuidString ?? "all"):\(revision)" }

    var body: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: "Süreçler ve Takip", style: .cardTitle)
                    Spacer()
                    Button { revision += 1 } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
                    }.accessibilityLabel("Süreç özetini yenile")
                }
                if failed {
                    NovaText(text: "Süreç özeti alınamadı. Yenileyerek tekrar deneyin.", style: .body)
                } else if let snapshot {
                    if snapshot.rows.isEmpty {
                        NovaText(text: "Takip için önce firma ekleyin.", style: .body)
                    } else {
                        // KKD zimmet henüz ayrı bir Formlar modülüne taşınıyor; o
                        // hazır olana kadar burada gösterilmiyor.
                        let summaries = snapshot.summaries.filter { $0.id != "ppe" }
                        ForEach(Array(summaries.prefix(expanded ? summaries.count : 4))) { row in
                            Button { opening = .init(id: row.route) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    NovaIcon(symbol: row.symbol, size: 18).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 2) {
                                        NovaText(text: row.title, style: .bodyStrong)
                                        if row.available {
                                            if let summary = summaryText(row) {
                                                NovaText(text: summary, style: .meta)
                                            }
                                            if let day = row.nextOn {
                                                NovaText(text: "Sonraki tarih: " + NovaStatisticsSnapshot.dayLabel(day), style: .meta)
                                            }
                                        } else {
                                            NovaText(text: "Bu modül şu anda kullanılamıyor", style: .meta)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                    NovaText(text: row.available ? String(row.total) : "—", style: .bodyStrong)
                                    Image(systemName: "chevron.right").font(.system(size: 11))
                                }.frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(!row.available)
                                .accessibilityIdentifier("nova.tracking.\(row.id)")
                        }
                        Button { expanded.toggle() } label: {
                            NovaText(text: expanded ? "Daha az göster" : "Tüm süreçleri göster", style: .buttonSm)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        NovaText(text: "Kayıt sayıları · Yaklaşan: 30 gün · " + NovaStatisticsSnapshot.dayLabel(snapshot.today), style: .micro)
                    }
                } else {
                    ProgressView("Süreçler yükleniyor…").frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: key) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { event in
            guard event.object as? UUID == identity.userID else { return }
            revision += 1
        }
        .onChange(of: scenePhase) { phase in if phase == .active { revision += 1 } }
        .novaFullScreenCover(item: $opening, onDismiss: { revision += 1 }) { route in
            NovaTrackedModuleDestination(identity: identity, kind: route.id, company: company, canWrite: canWrite) { opening = nil }
        }
    }
    /// Nothing to say when the count is zero and no company needs attention:
    /// the row's own title and dash already carry that state.
    private func summaryText(_ row: NovaModuleTrackingSnapshot.Summary) -> String? {
        var parts: [String] = []
        if row.pending > 0 { parts.append("\(row.pending) bekleyen") }
        if row.overdue > 0 { parts.append("\(row.overdue) tarihi geçmiş") }
        if row.upcoming > 0 { parts.append("\(row.upcoming) yaklaşan") }
        if row.review > 0 { parts.append("\(row.review) süre bilgisi eksik") }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return row.total == 0 ? nil : "Kayıtları görüntüle"
    }
    @MainActor private func refresh() async {
        snapshot = nil; failed = false; onLoaded?(nil)
        do {
            guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
            let data = try await SupabaseService.shared.client.rpc("isg_pilot_module_tracking_v1", params: ["p_company": company.map(PersonnelRPCValue.id) ?? .null]).execute().data
            try Task.checkCancellation()
            guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
            snapshot = try JSONDecoder().decode(NovaModuleTrackingSnapshot.self, from: data)
            onLoaded?(snapshot)
        } catch { if !Task.isCancelled { failed = true } }
    }
}

struct NovaTrackedModuleDestination: View {
    let identity: NovaSessionIdentity
    let kind: String
    let company: UUID?
    let canWrite: Bool
    var startInAddMode = false
    let onBack: () -> Void
    var body: some View {
        switch kind {
        case "emergency_plan": NovaPilotEmergencyGate(identity: identity, canWrite: canWrite, initialCompany: company, startInAddMode: startInAddMode, onBack: onBack)
        case "drill": NovaPilotDrillGate(identity: identity, canWrite: canWrite, initialCompany: company, onBack: onBack)
        case "appointment": NovaPilotAppointmentGate(identity: identity, canWrite: canWrite, initialCompany: company, startInAddMode: startInAddMode, onBack: onBack)
        case "checklist_run": NovaPilotChecklistGate(identity: identity, canWrite: canWrite, initialCompany: company, onBack: onBack)
        case "ppe": NovaPilotPPEGate(identity: identity, canWrite: canWrite, initialCompany: company, startInAddMode: startInAddMode, onBack: onBack)
        default: NovaPilotProcessGate(identity: identity, kind: kind, initialCompany: company, canWrite: canWrite, startInAddMode: startInAddMode, onBack: onBack)
        }
    }
}
