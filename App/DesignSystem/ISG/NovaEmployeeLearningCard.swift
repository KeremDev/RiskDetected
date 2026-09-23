import SwiftUI
import Supabase

/// Actual instruction and missing topics, independent of certificate issuance.
struct NovaEmployeeLearningCard: View {
    let identity: NovaSessionIdentity
    let company: UUID
    let employee: UUID
    @State private var result: Learning?
    @State private var failure = false
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
        }
        .task(id: revision) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { _ in revision += 1 }
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

/// Opens only the education records that include this employee. Certificate
/// issuance remains in the education domain; the other personnel documents
/// keep their existing destination.
struct NovaEmployeeCertificatesScreen: View {
    let identity: NovaSessionIdentity
    let company: UUID
    let employee: UUID
    let canWrite: Bool
    let onBack: () -> Void
    private struct Entry: Identifiable {
        let session: NovaTrainingSession
        let scopeID: UUID
        var id: String { "\(session.id)-\(scopeID)" }
    }
    private struct Selection: Identifiable {
        let id = UUID()
        let session: NovaTrainingSession
        let scopeID: UUID
        let documentID: UUID?
        let revision: Int?
    }
    @State private var entries: [Entry] = []
    @State private var selection: Selection?
    @State private var otherDocuments = false
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NovaText(text: "Sertifika ve belgeler", style: .screenTitle)
                    Spacer()
                    Button("Bitti", action: onBack)
                }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error { NovaHelpHint(text: error) }
                if !loading && entries.isEmpty && error == nil {
                    NovaEmptyState(title: "Eğitim sertifikası yok",
                        message: "Bu personelin yer aldığı bir eğitim kaydı henüz bulunamadı.")
                }
                ForEach(entries) { entry in
                    Button { Task { await open(entry) } } label: {
                        NovaCard(padding: 14) {
                            HStack(spacing: 10) {
                                Image(systemName: "graduationcap")
                                VStack(alignment: .leading, spacing: 3) {
                                    NovaText(text: entry.session.title, style: .bodyStrong)
                                    NovaText(text: entry.session.held_on, style: .metaQuiet)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                            }
                        }
                    }.buttonStyle(NovaRowPressStyle())
                }
                NovaCompactActionButton(title: "Diğer belgeler", symbol: "doc.text") { otherDocuments = true }
            }.padding(18).novaPopupContentSize()
        }
        .task { await load() }
        .novaFullScreenCover(item: $selection) { value in
            NovaPopup {
                NovaEducationCertificateScreen(identity: identity, session: value.session,
                    scopeID: value.scopeID, personID: employee, canIssue: canWrite,
                    documentID: value.documentID, documentRevision: value.revision)
            }
        }
        .novaPopup(isPresented: $otherDocuments) {
            NovaPilotProcessGate(identity: identity, kind: "personnel_certificate",
                initialCompany: company, parent: employee, canWrite: canWrite,
                onBack: { otherDocuments = false })
        }
    }
    private func load() async {
        loading = true; error = nil
        do {
            let service = NovaTrainingSessionService(identity: identity)
            var rows: [Entry] = []
            var after: UUID?
            var seen = Set<UUID>()
            repeat {
                let page = try await service.list(company: company, after: after)
                for session in page.rows {
                    for scope in session.education?.scopes ?? [] where
                        scope.company_id == company && scope.participants.contains(where: { $0.id == employee }) {
                        rows.append(.init(session: session, scopeID: scope.id))
                    }
                }
                after = page.next_id
                if let after, !seen.insert(after).inserted { throw NovaPersonnelFailure.unavailable }
            } while after != nil
            entries = rows.sorted { $0.session.held_on > $1.session.held_on }
        } catch { self.error = NovaTrainingSessionService.message(error) }
        loading = false
    }
    private func open(_ entry: Entry) async {
        do {
            let context = try await NovaEducationService(identity: identity).context(id: entry.session.id)
            guard let session = context.row else { throw NovaPersonnelFailure.unavailable }
            let document = context.certificates.first {
                $0.scope_id == entry.scopeID && $0.person_id == employee && $0.source_session_revision == session.version
            }
            selection = .init(session: session, scopeID: entry.scopeID,
                documentID: document?.document_id, revision: document?.revision)
        } catch { self.error = NovaEducationService.message(error) }
    }
}
