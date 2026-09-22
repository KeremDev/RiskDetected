import SwiftUI
import Supabase

/// Actual instruction and missing topics, independent of certificate issuance.
struct NovaEmployeeLearningCard: View {
    let identity: NovaSessionIdentity
    let company: UUID
    let employee: UUID
    let canWrite: Bool
    @State private var result: Learning?
    @State private var failure = false
    @State private var certificates = false
    @State private var revision = 0
    struct Learning: Decodable {
        let schema_version: Int; let owner_id: UUID; let company_id: UUID; let employee_id: UUID
        let groups: [Group]; let expired_scopes: Int; let legacy_company_records: Int
    }
    struct Group: Decodable, Identifiable {
        let id: String; let workplace_name: String?; let group_name: String; let profile: String
        let required_minutes: Int; let received_minutes: Int; let remaining_minutes: Int
        let group4_remaining_minutes: Int; let common_remaining_minutes: Int
        let missing_topics: [Topic]; let excluded_sessions: Int; let context_missing: Bool
        let complete: Bool; let valid_until: String?
        struct Topic: Decodable, Identifiable { let code: String; let title: String; var id: String { code } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Eğitim durumu", systemImage: "graduationcap").font(NovaFont.font(.cardTitle))
                    NovaHelpHint(text: "Gerçekleşen dersler, aynı işyeri ve eğitim kapsamı içinde toplanır. Aralar öğretim süresine eklenmez.")
                    if let result {
                        if result.groups.isEmpty { NovaText(text: "Güncel, konu bazlı temel eğitim kaydı yok.", style: .body) }
                        ForEach(result.groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                NovaText(text: group.profile, style: .label)
                                NovaText(text: [group.workplace_name, group.group_name].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), style: .meta)
                                ProgressView(value: Double(min(group.received_minutes, group.required_minutes)), total: Double(max(1, group.required_minutes))).tint(.primary)
                                NovaText(text: "\(hours(group.received_minutes)) / \(hours(group.required_minutes)) ders saati · \(hours(group.remaining_minutes)) saat eksik", style: .label)
                                NovaText(text: "\(group.received_minutes) dk net öğretim. Bir ders saati 45 dk öğretimdir; ara ayrıca tutulur.", style: .meta)
                                if group.complete {
                                    NovaText(text: "Süre ve konu kapsamı tamam · takip: \(group.valid_until ?? "—")", style: .meta)
                                } else {
                                    if group.group4_remaining_minutes > 0 { NovaText(text: "İşyerine özgü konularda \(group.group4_remaining_minutes) dk eksik", style: .meta) }
                                    if group.common_remaining_minutes > 0 { NovaText(text: "Genel, sağlık ve teknik konularda \(group.common_remaining_minutes) dk eksik", style: .meta) }
                                    if !group.missing_topics.isEmpty {
                                        DisclosureGroup("Eksik konular · \(group.missing_topics.count)") {
                                            VStack(alignment: .leading, spacing: 8) { ForEach(group.missing_topics) { topic in NovaText(text: topic.code + " · " + topic.title, style: .meta) } }.padding(.top, 8)
                                        }.font(NovaFont.font(.meta))
                                    }
                                }
                                if group.excluded_sessions > 0 { NovaText(text: "\(group.excluded_sessions) kaydın ders dağılımı düzeltilmeli; süreye katılmadı.", style: .meta) }
                                if group.context_missing { NovaText(text: "İşyerine özgü içerik veya eğitim yöntemi eksik; ilgili G4 dakikaları sayılmadı.", style: .meta) }
                            }.padding(.vertical, 6)
                        }
                        if result.expired_scopes > 0 { NovaText(text: "Süresi dolan \(result.expired_scopes) kapsam güncel süreye dahil edilmedi.", style: .meta) }
                        if result.legacy_company_records > 0 { NovaText(text: "Firmanın eski kayıtlarında konu dökümü bulunmuyor; bu kayıtlardan süre aktarılmadı.", style: .meta) }
                    } else if failure {
                        NovaText(text: "Eğitim durumu alınamadı.", style: .meta)
                        Button("Yeniden dene") { revision += 1 }
                    } else { ProgressView("Eğitim durumu yükleniyor…") }
                    NovaText(text: "Bu özet sertifika veya sınav sonucu oluşturmaz.", style: .meta)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            NovaButton(label: "Sertifika ve belgeleri", symbol: "doc.text", variant: .surface) { certificates = true }
        }
        .task(id: revision) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { _ in revision += 1 }
        .novaPopup(isPresented: $certificates) {
            NovaPilotProcessGate(identity: identity, kind: "personnel_certificate", initialCompany: company, parent: employee, canWrite: canWrite, onBack: { certificates = false })
        }
    }
    private func hours(_ minutes: Int) -> String { String(format: "%.1f", Double(minutes) / 45).replacingOccurrences(of: ".0", with: "") }
    private func load() async {
        result = nil; failure = false
        do {
            try checkSession()
            let data = try await NovaExpertTransport.shared.execute("isg_pilot_employee_learning_v1", params: ["p_company": PersonnelRPCValue.id(company), "p_employee": .id(employee)], ticket: NovaExpertTransport.shared.capture())
            try checkSession(); try Task.checkCancellation()
            let value = try JSONDecoder().decode(Learning.self, from: data)
            guard value.schema_version == 1, value.owner_id == identity.userID, value.company_id == company, value.employee_id == employee else { throw NovaPPEFailure.denied }
            result = value
        } catch { if !Task.isCancelled { failure = true } }
    }
    private func checkSession() throws {
        guard let session = SupabaseService.shared.client.auth.currentSession, session.user.id == identity.userID,
              NovaPersonnelService.sessionID(session.accessToken) == identity.sessionID else { throw NovaPPEFailure.denied }
    }
}
