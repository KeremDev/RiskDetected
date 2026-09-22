import SwiftUI

/// The same destination serves personal experts, organization experts and scoped manager inspection.
struct ExpertActivityDestination: View {
    var workspace: UUID? = nil
    var member: UUID? = nil
    let onClose: () -> Void
    var onOpenRecord: ((BusinessActivityDetail, Bool) -> Void)? = nil
    @State private var summary: UsageSummary?
    @State private var items: [BusinessActivityItem] = []
    @State private var cursor: Int64?
    @State private var days = 30
    @State private var action = ""
    @State private var company: UUID?
    @State private var loadEpoch = UUID()
    @State private var loading = false
    @State private var error: String?
    @State private var detail: BusinessActivityDetail?
    @State private var actions: [String] = []
    @State private var companies: [ExpertActivityService.Page.Company] = []

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NovaPageHeading(title: member == nil ? "Aktivitem" : "Uzman aktivitesi", onBack: onClose)
                    if let summary { summaryCards(summary) }
                    Picker("Tarih aralığı", selection: $days) {
                        Text("7 gün").tag(7)
                        Text("30 gün").tag(30)
                        Text("Tümü").tag(0)
                    }.pickerStyle(.segmented)
                    HStack {
                        Menu {
                            Button("Tüm işlemler") { action = "" }
                            ForEach(actions, id: \.self) { key in
                                Button(BusinessActivityItem.title(action: key)) { action = key }
                            }
                        } label: { Label(action.isEmpty ? "İşlem türü" : "Tür seçili", systemImage: "line.3.horizontal.decrease") }
                        Spacer()
                        Menu {
                            Button("Tüm firmalar") { company = nil }
                            ForEach(companies) { option in
                                Button(option.name) { company = option.id }
                            }
                        } label: { Label(company == nil ? "Firma" : "Firma seçili", systemImage: "building.2") }
                    }.font(NovaFont.font(.metaQuiet))
                    if let error {
                        NovaHelpHint(text: error)
                        Button("Yeniden dene") { Task { await load(reset: true) } }
                    }
                    if items.isEmpty && !loading && error == nil {
                        NovaHelpHint(text: "Bu tarih aralığında kayıtlı işlem yok. Kullanım süreleri özellik etkinleştirildikten sonra birikir.")
                    }
                    ForEach(items) { item in
                        Button {
                            Task {
                                do { detail = try await ExpertActivityService.detail(item.id, workspace: workspace) }
                                catch { self.error = "İşlem detayı alınamadı. Erişiminizi ve bağlantınızı kontrol edin." }
                            }
                        } label: {
                            NovaCard(padding: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(item.title).font(NovaFont.font(.bodyStrong))
                                        if let name = item.company_name { Text(name).font(NovaFont.font(.metaQuiet)) }
                                        Text(Self.date(item.created_at)).font(NovaFont.font(.metaQuiet)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }.buttonStyle(.plain)
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if cursor != nil {
                        Button("Daha fazla göster") { Task { await load(reset: false) } }.disabled(loading)
                    }
                }.padding(18)
            }.refreshable { await load(reset: true) }
        }
        .task(id: "\(days):\(action):\(company?.uuidString ?? "all")") { await load(reset: true) }
        .sheet(item: $detail) { value in
            NavigationStack {
                List {
                    Section("İşlem") {
                        Text(items.first(where: { $0.id == value.id })?.title ?? "İşlem kaydı")
                        Text(Self.date(value.created_at))
                    }
                    Section("Değişiklikler") {
                        if value.changes.isEmpty { Text("Bu işlem için gösterilebilir alan değişikliği yok.") }
                        ForEach(value.changes) { change in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Self.field(change.field)).font(.headline)
                                Text("\(change.before?.text ?? "—") → \(change.after?.text ?? "—")")
                            }
                        }
                    }
                    if let stages = value.stages, !stages.isEmpty {
                        Section("İşlem aşamaları") {
                            ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                                VStack(alignment: .leading) {
                                    Text(BusinessActivityItem.title(action: value.entity_type + "." + stage.status))
                                    Text(Self.date(stage.at)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if value.link_company_id != nil, let onOpenRecord {
                        Section("İlgili kayıt") {
                            Button("Firmayı aç") { detail = nil; onOpenRecord(value, true) }
                            if value.entity_type != "company", value.entity_id != nil {
                                Button("İlgili modüldeki kaydı aç") { detail = nil; onOpenRecord(value, false) }
                            }
                        }
                    }
                    Section { Text("Kişisel not içeriği, iletişim bilgileri, dosyalar ve AI içerikleri bu günlüğe dahil edilmez.").font(.footnote) }
                }.navigationTitle("İşlem detayı").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Kapat") { detail = nil } } }
            }.presentationDetents([.medium, .large])
        }
    }
    private func summaryCards(_ value: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Bugün", value.today_seconds)
                metric("Son 7 gün", value.week_seconds)
                metric("Son 30 gün", value.month_seconds)
                metric(member == nil ? "Toplam aktif süre" : "Üyelik döneminde", value.total_seconds)
                metric("Son oturum", value.session_seconds)
                if member != nil { metric("Bu OSGB'de", value.workspace_seconds) }
            }
            NovaText(text: "Giriş sayısı: \(value.login_count)", style: .metaQuiet)
            NovaText(text: "Son giriş: \(value.last_login_at.map(Self.date) ?? "Henüz yok")", style: .metaQuiet)
            NovaText(text: "Son aktiflik: \(value.last_active_at.map(Self.date) ?? "Henüz yok")", style: .metaQuiet)
        }
    }
    private func metric(_ title: String, _ seconds: Double) -> some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: UsageSummary.duration(seconds), style: .sectionTitle)
                NovaText(text: title, style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func load(reset: Bool) async {
        guard reset || !loading else { return }
        let epoch = UUID(); loadEpoch = epoch
        loading = true; error = nil
        defer { if loadEpoch == epoch { loading = false } }
        do {
            let from = days == 0 ? nil : ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(days) * 86400))
            let result = try await ExpertActivityService.page(.init(p_workspace: workspace, p_user: member,
                p_after: reset ? nil : cursor, p_from: from, p_action: action.isEmpty ? nil : action, p_company: company))
            guard loadEpoch == epoch else { return }
            summary = result.summary
            actions = result.actions ?? []
            companies = result.companies ?? []
            items = reset ? result.items : items + result.items
            cursor = result.next_cursor
        } catch is CancellationError { }
        catch { if loadEpoch == epoch { self.error = "Aktivite bilgileri yüklenemedi. Lütfen yeniden deneyin." } }
    }
    private static func date(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: value) }
        return date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }
    private static func field(_ key: String) -> String {
        ["status": "Durum", "state": "Durum", "version": "Sürüm", "role": "Rol",
         "hazard_class": "Tehlike sınıfı", "is_primary": "Birincil uzman", "starts_on": "Başlangıç",
         "ends_on": "Bitiş", "ends_before": "Bitiş", "due_on": "Son tarih", "completed_at": "Tamamlanma",
         "employee_count": "Çalışan sayısı", "declared_employee_count": "Çalışan sayısı",
         "duration_minutes": "Süre (dakika)", "valid_until": "Geçerlilik", "planned_on": "Planlanan tarih",
         "performed_on": "Gerçekleşme", "held_on": "Tarih", "visited_on": "Ziyaret tarihi", "quantity": "Miktar",
         "is_archived": "Arşivlendi", "is_deleted": "Silindi", "severity": "Önem",
         "protected_details": "Korunan kayıt bilgileri değiştirildi"][key] ?? "Alan"
    }
}
