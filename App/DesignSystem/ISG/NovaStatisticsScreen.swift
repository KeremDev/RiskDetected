import SwiftUI

/// All values are server aggregates. Current stock and period activity have
/// separate headings; unavailable sources never become a zero or a score.
struct NovaStatisticsScreen: View {
    var trackingIdentity: NovaSessionIdentity?
    var trackingCanWrite = false
    let load: (UUID?, Int) async throws -> NovaStatisticsSnapshot
    let onBack: () -> Void
    let onNavigate: (NovaDestination) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var company: UUID?
    @State private var months = 6
    @State private var snapshot: NovaStatisticsSnapshot?
    @State private var companyOptions: [NovaStatisticsSnapshot.Company] = []
    @State private var loading = true
    @State private var failed = false
    @State private var revision = 0
    @State private var trainingChart = false
    @State private var selectedMonth: String?
    private var requestKey: String { "\(company?.uuidString ?? "all")-\(months)-\(revision)" }
    private var companyName: String { companyOptions.first { $0.id == company }?.name ?? "Tüm firmalar" }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    filters
                    if let trackingIdentity {
                        NovaVisitPeriodCard(identity: trackingIdentity, company: company, months: months)
                        NovaFollowupSummaryCard(identity: trackingIdentity, company: company, canWrite: trackingCanWrite)
                        NovaModuleTrackingCard(identity: trackingIdentity, company: company, canWrite: trackingCanWrite)
                    }
                    if loading { loadingCard }
                    else if failed { failureCard }
                    else if let data = snapshot {
                        overview(data)
                        periodCards(data)
                        activity(data)
                        findings(data)
                        documents(data)
                        companies(data)
                        NovaText(text: RDLocalization.string("localizable.nova.statistics.screen.aktif.firmalariniz.ve.firma.secilmediginde.firma.31ba356f", table: .localizable, fallback: "Aktif firmalarınız ve firma seçilmediğinde firmasız fotoğraf analizleri kapsanır. Arşivlenmiş firmalar dahil değildir."), style: .metaQuiet)
                        NovaText(text: RDLocalization.format("localizable.nova.statistics.screen.guncelleme.1.istanbul.1ecb8da9", table: .localizable, fallback: "Güncelleme: %1$@ · İstanbul", arguments: [String(describing: NovaStatisticsSnapshot.dayLabel(data.today))]), style: .micro)
                    }
                }.padding(.horizontal, 18).padding(.top, 6).padding(.bottom, novaTabBarInset)
                    .novaAsyncContent(isLoading: loading)
            }
            .refreshable { revision += 1 }
            .task(id: requestKey) { await refresh(key: requestKey) }
        }.accessibilityIdentifier("nova.statistics.screen")
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("isgada.records.changed"))) { event in
            if let trackingIdentity, event.object as? UUID == trackingIdentity.userID { revision += 1 }
        }
    }
    private var heading: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                NovaPageHeading(title: RDLocalization.string("localizable.nova.statistics.screen.istatistikler.bd4c4deb", table: .localizable, fallback: "İstatistikler"), onBack: onBack)
                NovaText(text: RDLocalization.string("localizable.nova.statistics.screen.calismalarinizin.guncel.gorunumu.e9b2c6f0", table: .localizable, fallback: "Çalışmalarınızın güncel görünümü"), style: .metaQuiet)
            }
            Spacer(minLength: 0)
            Button { revision += 1 } label: {
                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
            }.disabled(loading).accessibilityLabel(RDLocalization.string("localizable.nova.statistics.screen.istatistikleri.yenile.8d3aa434", table: .localizable, fallback: "İstatistikleri yenile"))
        }
    }
    private var filters: some View {
        VStack(spacing: 10) {
            NovaFilterField(label: "Firma", options: [.init(id: nil, title: RDLocalization.string("localizable.nova.statistics.screen.tum.firmalar.1ba73c7f", table: .localizable, fallback: "Tüm firmalar"))] + companyOptions.map { .init(id: $0.id.uuidString, title: $0.name) },
                selected: company?.uuidString, identifier: "nova.statistics.company") { company = $0.flatMap(UUID.init(uuidString:)) }
            NovaFilterField(label: RDLocalization.string("localizable.nova.statistics.screen.donem.1dd14012", table: .localizable, fallback: "Dönem"), options: [.init(id: "1", title: RDLocalization.string("localizable.nova.statistics.screen.bu.ay.0480b628", table: .localizable, fallback: "Bu ay")), .init(id: "3", title: RDLocalization.string("localizable.nova.statistics.screen.3.ay.c3dc9307", table: .localizable, fallback: "3 ay")), .init(id: "6", title: RDLocalization.string("localizable.nova.statistics.screen.6.ay.e062dcd1", table: .localizable, fallback: "6 ay")), .init(id: "12", title: RDLocalization.string("localizable.nova.statistics.screen.12.ay.e2da88ff", table: .localizable, fallback: "12 ay"))],
                selected: String(months), identifier: "nova.statistics.period") { if let value = $0.flatMap(Int.init) { months = value } }
        }
    }
    private var loadingCard: some View {
        NovaLoadingView(message: RDLocalization.string("localizable.nova.statistics.screen.istatistikler.hazirlaniyor.b05e072a", table: .localizable, fallback: "İstatistikler hazırlanıyor…")).frame(minHeight: 320)
    }
    private var failureCard: some View {
        NovaCard(padding: 20) { VStack(alignment: .leading, spacing: 12) {
            Label(RDLocalization.string("localizable.nova.statistics.screen.veriler.alinamadi.07e3c75a", table: .localizable, fallback: "Veriler alınamadı"), systemImage: "wifi.exclamationmark")
            NovaText(text: RDLocalization.string("localizable.nova.statistics.screen.baglantinizi.kontrol.edip.yeniden.deneyin.onceki.0b638a73", table: .localizable, fallback: "Bağlantınızı kontrol edip yeniden deneyin. Önceki filtreye ait sayılar gösterilmiyor."), style: .metaQuiet)
            NovaButton(label: RDLocalization.string("localizable.nova.statistics.screen.tekrar.dene.e8b71d67", table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise") { revision += 1 }
        } }
    }
    private func overview(_ data: NovaStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(RDLocalization.string("localizable.nova.statistics.screen.portfoyunuz.1bd30439", table: .localizable, fallback: "Portföyünüz"), subtitle: RDLocalization.string("localizable.nova.statistics.screen.bugunku.kayitlar.donem.filtresinden.bagimsiz.538a4dec", table: .localizable, fallback: "Bugünkü kayıtlar · dönem filtresinden bağımsız"))
            HStack(spacing: 8) {
                NovaListStat(title: RDLocalization.string("localizable.nova.statistics.screen.aktif.firma.237285a5", table: .localizable, fallback: "Aktif firma"), symbol: "building.2", value: data.company_count)
                NovaListStat(title: "Personel", symbol: "person.2", value: data.personnel)
                NovaListStat(title: RDLocalization.string("localizable.nova.statistics.screen.isyeri.f63b21d4", table: .localizable, fallback: "İşyeri"), symbol: "building", value: data.workplaces)
            }
        }
    }
    private func periodCards(_ data: NovaStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(RDLocalization.string("localizable.nova.statistics.screen.secili.donemde.ef05e110", table: .localizable, fallback: "Seçili dönemde"), subtitle: "\(NovaStatisticsSnapshot.dayLabel(data.from_day)) – \(NovaStatisticsSnapshot.dayLabel(data.today))")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Fotoğraf analizi", value: data.analyses, symbol: "viewfinder", destination: .analyses)
                metric("Eğitim", value: data.trainings, symbol: "graduationcap", destination: .training)
                metric("Eğitim alan kişi", value: data.trained_people, symbol: "person.2", destination: .training)
                metric("Eğitim kaydı", value: data.training_enrollments, symbol: "person.crop.rectangle.stack", destination: .training)
            }
            NovaText(text: RDLocalization.string("localizable.nova.statistics.screen.ayni.egitimdeki.farkli.firmalar.egitim.sayisini..4d04f6dd", table: .localizable, fallback: "Aynı eğitimdeki farklı firmalar eğitim sayısını artırmaz. Bir kişi farklı eğitimlerde birden fazla kişi × eğitim kaydı oluşturabilir."), style: .metaQuiet)
        }
    }
    private func metric(_ title: String, value: Int, symbol: String, destination: NovaDestination) -> some View {
        NovaListStat(title: title, symbol: symbol, value: value) { onNavigate(destination) }
            .accessibilityLabel(RDLocalization.format("localizable.nova.statistics.screen.1.2.tum.kayitlari.ac.5a46df0f", table: .localizable, fallback: "%1$@: %2$@. Tüm kayıtları aç", arguments: [String(describing: title), String(describing: value)]))
    }
    private func activity(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle(RDLocalization.string("localizable.nova.statistics.screen.aylik.hareket.0b93d8db", table: .localizable, fallback: "Aylık hareket"), subtitle: RDLocalization.string("localizable.nova.statistics.screen.bir.aya.dokunarak.toplamini.gorun.0dd7e7c2", table: .localizable, fallback: "Bir aya dokunarak toplamını görün"))
                Picker("Grafik", selection: $trainingChart) { Text("Analizler").tag(false); Text(RDLocalization.string("localizable.nova.statistics.screen.egitimler.8e8f8c6e", table: .localizable, fallback: "Eğitimler")).tag(true) }.pickerStyle(.segmented)
                chart(data)
                if let item = data.series.first(where: { $0.month == selectedMonth }) {
                    NovaText(text: RDLocalization.format("localizable.nova.statistics.screen.chart.bar.title", table: .localizable, fallback: "%1$@ %2$@ · %3$@ %4$@", arguments: [String(describing: item.label), String(describing: item.month.prefix(4)), String(describing: trainingChart ? item.trainings : item.analyses), String(describing: trainingChart ? RDLocalization.string("localizable.nova.statistics.screen.chart.unit.training", table: .localizable, fallback: "eğitim") : RDLocalization.string("localizable.nova.statistics.screen.chart.unit.analysis", table: .localizable, fallback: "analiz"))]), style: .bodyStrong)
                } else {
                    NovaText(text: (trainingChart ? data.trainings : data.analyses) == 0 ? "Bu dönemde henüz kayıt yok." : "Aylık toplamlar, tamamlanan kayıtlardan hesaplanır.", style: .metaQuiet)
                }
            }
        }
    }
    private func chart(_ data: NovaStatisticsSnapshot) -> some View {
        let maximum = max(1, data.series.map { trainingChart ? $0.trainings : $0.analyses }.max() ?? 1)
        return GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: data.months > 6) {
                HStack(alignment: .bottom, spacing: 8) {
            ForEach(data.series) { item in
                let value = trainingChart ? item.trainings : item.analyses
                Button { selectedMonth = item.month } label: {
                    VStack(spacing: 8) {
                        Text(value.formatted()).font(.system(size: 10, weight: .semibold)).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme)).lineLimit(1).minimumScaleFactor(0.5)
                        RoundedRectangle(cornerRadius: 5).fill(value == 0 ? NovaColorToken.surfaceMuted.color(in: scheme) : (trainingChart ? NovaColorToken.accentInk : .statusInfoInk).color(in: scheme).opacity(selectedMonth == nil || selectedMonth == item.month ? 1 : 0.35))
                            .frame(height: max(3, 100 * CGFloat(value) / CGFloat(maximum)))
                        Text(item.label).font(.system(size: 11)).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle()).accessibilityLabel(RDLocalization.format("localizable.nova.statistics.screen.chart.bar.accessibility", table: .localizable, fallback: "%1$@ %2$@, %3$@ %4$@", arguments: [String(describing: item.label), String(describing: item.month.prefix(4)), String(describing: value), String(describing: trainingChart ? RDLocalization.string("localizable.nova.statistics.screen.chart.unit.training", table: .localizable, fallback: "eğitim") : RDLocalization.string("localizable.nova.statistics.screen.chart.unit.analysis", table: .localizable, fallback: "analiz"))]))
            }
                }.frame(width: max(proxy.size.width, CGFloat(data.months * 52 - 8)), height: 148)
            }
        }.frame(height: 158).accessibilityIdentifier("nova.statistics.chart")
    }
    private func findings(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Uygunsuzluklar", subtitle: RDLocalization.string("localizable.nova.statistics.screen.bugunku.acik.kayitlarin.durumu.1929804a", table: .localizable, fallback: "Bugünkü açık kayıtların durumu"))
            if let findings = data.findings {
                HStack(spacing: 8) {
                    NovaListStat(title: RDLocalization.string("localizable.nova.statistics.screen.acik.f632ba89", table: .localizable, fallback: "Açık"), symbol: "exclamationmark.circle", value: findings.open)
                    NovaListStat(title: RDLocalization.string("localizable.nova.statistics.screen.gecikmis.1bfe1e8d", table: .localizable, fallback: "Gecikmiş"), symbol: "clock.badge.exclamationmark", value: findings.overdue)
                    NovaListStat(title: RDLocalization.string("localizable.nova.statistics.screen.dogrulamada.22770641", table: .localizable, fallback: "Doğrulamada"), symbol: "checkmark.circle.badge.questionmark", value: findings.pending)
                }
                Divider()
                ForEach(["critical", "high", "medium", "low"], id: \.self) { key in
                    distribution(severityLabel(key), count: findings.severity[key] ?? 0, total: findings.open, tone: severityTone(key))
                }
                NovaText(text: RDLocalization.format("localizable.nova.statistics.screen.secili.donemde.1.kayit.acildi.bugun.kapali.olan..4f66233b", table: .localizable, fallback: "Seçili dönemde %1$@ kayıt açıldı; bugün kapalı olan %2$@ kayıt bu dönemde kapatıldı. İyileştirme önerileri dahil değildir.", arguments: [String(describing: findings.opened), String(describing: findings.closed)]), style: .metaQuiet)
                link("Tüm uygunsuzlukları aç", destination: .findings)
            } else { unavailable("Uygunsuzluk istatistikleri bu hesapta henüz kullanılamıyor.") }
        } }
    }
    private func documents(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 14) {
            sectionTitle(RDLocalization.string("localizable.nova.statistics.screen.evrak.durumu.82536a40", table: .localizable, fallback: "Evrak durumu"), subtitle: RDLocalization.string("localizable.nova.statistics.screen.takip.edilen.evraklarin.guncel.durumu.6edb72d6", table: .localizable, fallback: "Takip edilen evrakların güncel durumu"))
            if let docs = data.documents {
                let total = data.documentTotal ?? 0
                distribution("Geçerli", count: docs["valid"] ?? 0, total: total, tone: .accentInk)
                distribution("Süresi yaklaşıyor", count: docs["due_soon"] ?? 0, total: total, tone: .statusWarningInk)
                distribution("Süresi dolmuş", count: docs["expired"] ?? 0, total: total, tone: .statusDangerInk)
                distribution("Eksik", count: docs["missing"] ?? 0, total: total, tone: .statusNeutralInk)
                if total == 0 { NovaText(text: RDLocalization.string("localizable.nova.statistics.screen.henuz.takibe.alinmis.evrak.yok.5ecb8de6", table: .localizable, fallback: "Henüz takibe alınmış evrak yok."), style: .metaQuiet) }
                link("Evrak takibini aç", destination: .documentChecklist)
            } else { unavailable("Evrak istatistikleri bu hesapta henüz kullanılamıyor.") }
        } }
    }
    private func companies(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 14) {
            sectionTitle(RDLocalization.string("localizable.nova.statistics.screen.firma.dagilimi.fb2c6ac0", table: .localizable, fallback: "Firma dağılımı"), subtitle: RDLocalization.string("localizable.nova.statistics.screen.istatistiklerini.filtrelemek.icin.firma.secin.c71851f5", table: .localizable, fallback: "İstatistiklerini filtrelemek için firma seçin"))
            if data.selectedCompanies.isEmpty { NovaText(text: RDLocalization.string("localizable.nova.statistics.screen.henuz.aktif.firma.yok.7a8c4a3a", table: .localizable, fallback: "Henüz aktif firma yok."), style: .metaQuiet) }
            ForEach(data.selectedCompanies) { item in
                Button { company = item.id } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "building.2").foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: item.name, style: .bodyStrong)
                            NovaText(text: RDLocalization.format("localizable.nova.statistics.screen.1.personel.2.isyeri.12d31fa7", table: .localizable, fallback: "%1$@ personel · %2$@ işyeri", arguments: [String(describing: item.personnel), String(describing: item.workplaces)]), style: .metaQuiet)
                        }
                        Spacer(minLength: 0); Image(systemName: "chevron.right").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                    }.padding(.vertical, 4)
                }.buttonStyle(NovaRowPressStyle())
            }
            link("Firmaları aç", destination: .companies)
        } }
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { NovaText(text: title, style: .sectionTitle); NovaText(text: subtitle, style: .metaQuiet) }
    }
    private func distribution(_ title: String, count: Int, total: Int, tone: NovaColorToken) -> some View {
        VStack(spacing: 6) {
            HStack { NovaText(text: title, style: .meta); Spacer(); NovaText(text: count.formatted(), style: .bodyStrong) }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NovaColorToken.surfaceMuted.color(in: scheme))
                    Capsule().fill(tone.color(in: scheme)).frame(width: proxy.size.width * min(1, CGFloat(count) / CGFloat(max(1,total))))
                }
            }.frame(height: 5).accessibilityHidden(true)
        }.accessibilityElement(children: .combine)
    }
    private func unavailable(_ text: String) -> some View {
        Label { NovaText(text: text, style: .metaQuiet) } icon: { Image(systemName: "info.circle").foregroundStyle(NovaFont.secondaryInk) }.padding(.vertical, 6)
    }
    private func link(_ title: String, destination: NovaDestination) -> some View {
        Button { onNavigate(destination) } label: { HStack { NovaText(text: title, style: .buttonSm, color: NovaColorToken.accentInk.color(in: scheme)); Spacer(); Image(systemName: "arrow.right") }.padding(.vertical, 6) }.buttonStyle(NovaRowPressStyle())
    }
    private func severityLabel(_ key: String) -> String { ["critical":"Kritik", "high":"Yüksek", "medium":"Orta", "low":"Düşük"][key] ?? key }
    private func severityTone(_ key: String) -> NovaColorToken { ["critical": .statusDangerInk, "high": .statusWarningInk, "medium": .statusInfoInk, "low": .accentInk][key] ?? .text }
    @MainActor private func refresh(key: String) async {
        loading = true; failed = false; snapshot = nil; selectedMonth = nil
        do {
            let result = try await load(company, months)
            try Task.checkCancellation()
            guard key == requestKey else { return }
            snapshot = result; companyOptions = result.companies; loading = false
        } catch {
            guard !Task.isCancelled, key == requestKey else { return }
            failed = true; loading = false
        }
    }
}
