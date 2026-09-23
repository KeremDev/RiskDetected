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
                    NovaPageHeading(title: member == nil ? "Aktivitem" : RDLocalization.string("localizable.expert.activity.destination.uzman.aktivitesi.ea6d447b", table: .localizable, fallback: "Uzman aktivitesi"), onBack: onClose)
                    if let summary { summaryCards(summary) }
                    Picker(RDLocalization.string("localizable.expert.activity.destination.tarih.araligi.1edcc16d", table: .localizable, fallback: "Tarih aralığı"), selection: $days) {
                        Text(RDLocalization.string("localizable.expert.activity.destination.7.gun.be150a89", table: .localizable, fallback: "7 gün")).tag(7)
                        Text(RDLocalization.string("localizable.expert.activity.destination.30.gun.95631d49", table: .localizable, fallback: "30 gün")).tag(30)
                        Text(RDLocalization.string("localizable.expert.activity.destination.tumu.decbc7e0", table: .localizable, fallback: "Tümü")).tag(0)
                    }.pickerStyle(.segmented)
                    HStack {
                        Menu {
                            Button(RDLocalization.string("localizable.expert.activity.destination.tum.islemler.d70925a3", table: .localizable, fallback: "Tüm işlemler")) { action = "" }
                            ForEach(actions, id: \.self) { key in
                                Button(BusinessActivityItem.title(action: key)) { action = key }
                            }
                        } label: { Label(action.isEmpty ? RDLocalization.string("localizable.expert.activity.destination.islem.turu.53092789", table: .localizable, fallback: "İşlem türü") : RDLocalization.string("localizable.expert.activity.destination.tur.secili.9296ef6b", table: .localizable, fallback: "Tür seçili"), systemImage: "line.3.horizontal.decrease") }
                        Spacer()
                        Menu {
                            Button(RDLocalization.string("localizable.expert.activity.destination.tum.firmalar.b51e974f", table: .localizable, fallback: "Tüm firmalar")) { company = nil }
                            ForEach(companies) { option in
                                Button(option.name) { company = option.id }
                            }
                        } label: { Label(company == nil ? "Firma" : RDLocalization.string("localizable.expert.activity.destination.firma.secili.9403a701", table: .localizable, fallback: "Firma seçili"), systemImage: "building.2") }
                    }.font(NovaFont.font(.metaQuiet))
                    if let error {
                        NovaHelpHint(text: error)
                        Button(RDLocalization.string("localizable.expert.activity.destination.yeniden.dene.c7a69bc5", table: .localizable, fallback: "Yeniden dene")) { Task { await load(reset: true) } }
                    }
                    if items.isEmpty && !loading && error == nil {
                        NovaHelpHint(text: RDLocalization.string("localizable.expert.activity.destination.bu.tarih.araliginda.kayitli.islem.yok.kullanim.s.96fb2680", table: .localizable, fallback: "Bu tarih aralığında kayıtlı işlem yok. Kullanım süreleri özellik etkinleştirildikten sonra birikir."))
                    }
                    ForEach(items) { item in
                        Button {
                            Task {
                                do { detail = try await ExpertActivityService.detail(item.id, workspace: workspace) }
                                catch { self.error = RDLocalization.string("localizable.expert.activity.destination.islem.detayi.alinamadi.erisiminizi.ve.baglantini.5f0b8e7c", table: .localizable, fallback: "İşlem detayı alınamadı. Erişiminizi ve bağlantınızı kontrol edin.") }
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
                        Button(RDLocalization.string("localizable.expert.activity.destination.daha.fazla.goster.ff146086", table: .localizable, fallback: "Daha fazla göster")) { Task { await load(reset: false) } }.disabled(loading)
                    }
                }.padding(18)
            }.refreshable { await load(reset: true) }
        }
        .task(id: "\(days):\(action):\(company?.uuidString ?? "all")") { await load(reset: true) }
        .sheet(item: $detail) { value in
            NavigationStack {
                List {
                    Section(RDLocalization.string("localizable.expert.activity.destination.islem.1f386195", table: .localizable, fallback: "İşlem")) {
                        Text(items.first(where: { $0.id == value.id })?.title ?? RDLocalization.string("localizable.expert.activity.destination.islem.kaydi.64c62aaf", table: .localizable, fallback: "İşlem kaydı"))
                        Text(Self.date(value.created_at))
                    }
                    Section(RDLocalization.string("localizable.expert.activity.destination.degisiklikler.53c5bfbc", table: .localizable, fallback: "Değişiklikler")) {
                        if value.changes.isEmpty { Text(RDLocalization.string("localizable.expert.activity.destination.bu.islem.icin.gosterilebilir.alan.degisikligi.yo.1b68df85", table: .localizable, fallback: "Bu işlem için gösterilebilir alan değişikliği yok.")) }
                        ForEach(value.changes) { change in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(Self.field(change.field)).font(.headline)
                                Text("\(change.before?.text ?? "—") → \(change.after?.text ?? "—")")
                            }
                        }
                    }
                    if let stages = value.stages, !stages.isEmpty {
                        Section(RDLocalization.string("localizable.expert.activity.destination.islem.asamalari.f62ea3b6", table: .localizable, fallback: "İşlem aşamaları")) {
                            ForEach(Array(stages.enumerated()), id: \.offset) { _, stage in
                                VStack(alignment: .leading) {
                                    Text(BusinessActivityItem.title(action: value.entity_type + "." + stage.status))
                                    Text(Self.date(stage.at)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if value.link_company_id != nil, let onOpenRecord {
                        Section(RDLocalization.string("localizable.expert.activity.destination.ilgili.kayit.62eb30e0", table: .localizable, fallback: "İlgili kayıt")) {
                            Button(RDLocalization.string("localizable.expert.activity.destination.firmayi.ac.bc91ead9", table: .localizable, fallback: "Firmayı aç")) { detail = nil; onOpenRecord(value, true) }
                            if value.entity_type != "company", value.entity_id != nil {
                                Button(RDLocalization.string("localizable.expert.activity.destination.ilgili.moduldeki.kaydi.ac.175749e4", table: .localizable, fallback: "İlgili modüldeki kaydı aç")) { detail = nil; onOpenRecord(value, false) }
                            }
                        }
                    }
                    Section { Text(RDLocalization.string("localizable.expert.activity.destination.kisisel.not.icerigi.iletisim.bilgileri.dosyalar..676c8222", table: .localizable, fallback: "Kişisel not içeriği, iletişim bilgileri, dosyalar ve AI içerikleri bu günlüğe dahil edilmez.")).font(.footnote) }
                }.navigationTitle(RDLocalization.string("localizable.expert.activity.destination.islem.detayi.b03dfaf7", table: .localizable, fallback: "İşlem detayı")).navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button(RDLocalization.string("localizable.expert.activity.destination.kapat.499c5043", table: .localizable, fallback: "Kapat")) { detail = nil } } }
            }.presentationDetents([.medium, .large])
        }
    }
    private func summaryCards(_ value: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric(RDLocalization.string("localizable.expert.activity.destination.bugun.51cdef2d", table: .localizable, fallback: "Bugün"), value.today_seconds)
                metric(RDLocalization.string("localizable.expert.activity.destination.son.7.gun.2ff1dfbf", table: .localizable, fallback: "Son 7 gün"), value.week_seconds)
                metric(RDLocalization.string("localizable.expert.activity.destination.son.30.gun.0cb72be8", table: .localizable, fallback: "Son 30 gün"), value.month_seconds)
                metric(member == nil ? RDLocalization.string("localizable.expert.activity.destination.toplam.aktif.sure.c8ad0d12", table: .localizable, fallback: "Toplam aktif süre") : RDLocalization.string("localizable.expert.activity.destination.uyelik.doneminde.55b58508", table: .localizable, fallback: "Üyelik döneminde"), value.total_seconds)
                metric(RDLocalization.string("localizable.expert.activity.destination.son.oturum.209c7967", table: .localizable, fallback: "Son oturum"), value.session_seconds)
                if member != nil { metric(RDLocalization.string("localizable.expert.activity.destination.bu.osgb.de.83c6267f", table: .localizable, fallback: "Bu OSGB'de"), value.workspace_seconds) }
            }
            NovaText(text: RDLocalization.format("localizable.expert.activity.destination.giris.sayisi.1.74c56dd8", table: .localizable, fallback: "Giriş sayısı: %1$@", arguments: [String(describing: value.login_count)]), style: .metaQuiet)
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
        catch { if loadEpoch == epoch { self.error = RDLocalization.string("localizable.expert.activity.destination.aktivite.bilgileri.yuklenemedi.lutfen.yeniden.de.3229f744", table: .localizable, fallback: "Aktivite bilgileri yüklenemedi. Lütfen yeniden deneyin.") } }
    }
    private static func date(_ value: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: value)
        if date == nil { parser.formatOptions = [.withInternetDateTime]; date = parser.date(from: value) }
        return date?.formatted(date: .abbreviated, time: .shortened) ?? "—"
    }
    private static func field(_ key: String) -> String {
        ["status": "Durum", "state": "Durum", "version": RDLocalization.string("localizable.expert.activity.destination.surum.57eb4e59", table: .localizable, fallback: "Sürüm"), "role": "Rol",
         "hazard_class": RDLocalization.string("localizable.expert.activity.destination.tehlike.sinifi.965c0333", table: .localizable, fallback: "Tehlike sınıfı"), "is_primary": RDLocalization.string("localizable.expert.activity.destination.birincil.uzman.f321243d", table: .localizable, fallback: "Birincil uzman"), "starts_on": RDLocalization.string("localizable.expert.activity.destination.baslangic.e5e2eca3", table: .localizable, fallback: "Başlangıç"),
         "ends_on": RDLocalization.string("localizable.expert.activity.destination.bitis.194708a2", table: .localizable, fallback: "Bitiş"), "ends_before": RDLocalization.string("localizable.expert.activity.destination.bitis.194708a2", table: .localizable, fallback: "Bitiş"), "due_on": RDLocalization.string("localizable.expert.activity.destination.son.tarih.49f89a2c", table: .localizable, fallback: "Son tarih"), "completed_at": "Tamamlanma",
         "employee_count": RDLocalization.string("localizable.expert.activity.destination.calisan.sayisi.d0827fae", table: .localizable, fallback: "Çalışan sayısı"), "declared_employee_count": RDLocalization.string("localizable.expert.activity.destination.calisan.sayisi.d0827fae", table: .localizable, fallback: "Çalışan sayısı"),
         "duration_minutes": RDLocalization.string("localizable.expert.activity.destination.sure.dakika.c7208c2a", table: .localizable, fallback: "Süre (dakika)"), "valid_until": RDLocalization.string("localizable.expert.activity.destination.gecerlilik.e6fa565a", table: .localizable, fallback: "Geçerlilik"), "planned_on": RDLocalization.string("localizable.expert.activity.destination.planlanan.tarih.6b1749a7", table: .localizable, fallback: "Planlanan tarih"),
         "performed_on": RDLocalization.string("localizable.expert.activity.destination.gerceklesme.cc2aab9a", table: .localizable, fallback: "Gerçekleşme"), "held_on": "Tarih", "visited_on": RDLocalization.string("localizable.expert.activity.destination.ziyaret.tarihi.d40fd41b", table: .localizable, fallback: "Ziyaret tarihi"), "quantity": "Miktar",
         "is_archived": RDLocalization.string("localizable.expert.activity.destination.arsivlendi.e2dfae2a", table: .localizable, fallback: "Arşivlendi"), "is_deleted": "Silindi", "severity": RDLocalization.string("localizable.expert.activity.destination.onem.41683347", table: .localizable, fallback: "Önem"),
         "protected_details": RDLocalization.string("localizable.expert.activity.destination.korunan.kayit.bilgileri.degistirildi.1a526237", table: .localizable, fallback: "Korunan kayıt bilgileri değiştirildi")][key] ?? "Alan"
    }
}
