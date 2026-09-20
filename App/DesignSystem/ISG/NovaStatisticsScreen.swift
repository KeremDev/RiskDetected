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
                        NovaText(text: "Aktif firmalarınız ve firma seçilmediğinde firmasız fotoğraf analizleri kapsanır. Arşivlenmiş firmalar dahil değildir.", style: .metaQuiet)
                        NovaText(text: "Güncelleme: \(NovaStatisticsSnapshot.dayLabel(data.today)) · İstanbul", style: .micro)
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
                NovaPageHeading(title: "İstatistikler", onBack: onBack)
                NovaText(text: "Çalışmalarınızın güncel görünümü", style: .metaQuiet)
            }
            Spacer(minLength: 0)
            Button { revision += 1 } label: {
                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44)
            }.disabled(loading).accessibilityLabel("İstatistikleri yenile")
        }
    }
    private var filters: some View {
        VStack(spacing: 10) {
            NovaFilterField(label: "Firma", options: [.init(id: nil, title: "Tüm firmalar")] + companyOptions.map { .init(id: $0.id.uuidString, title: $0.name) },
                selected: company?.uuidString, identifier: "nova.statistics.company") { company = $0.flatMap(UUID.init(uuidString:)) }
            NovaFilterField(label: "Dönem", options: [.init(id: "1", title: "Bu ay"), .init(id: "3", title: "3 ay"), .init(id: "6", title: "6 ay"), .init(id: "12", title: "12 ay")],
                selected: String(months), identifier: "nova.statistics.period") { if let value = $0.flatMap(Int.init) { months = value } }
        }
    }
    private var loadingCard: some View {
        NovaLoadingView(message: "İstatistikler hazırlanıyor…").frame(minHeight: 320)
    }
    private var failureCard: some View {
        NovaCard(padding: 20) { VStack(alignment: .leading, spacing: 12) {
            Label("Veriler alınamadı", systemImage: "wifi.exclamationmark")
            NovaText(text: "Bağlantınızı kontrol edip yeniden deneyin. Önceki filtreye ait sayılar gösterilmiyor.", style: .metaQuiet)
            NovaButton(label: "Tekrar dene", symbol: "arrow.clockwise") { revision += 1 }
        } }
    }
    private func overview(_ data: NovaStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Portföyünüz", subtitle: "Bugünkü kayıtlar · dönem filtresinden bağımsız")
            HStack(spacing: 8) {
                NovaListStat(title: "Aktif firma", symbol: "building.2", value: data.company_count)
                NovaListStat(title: "Personel", symbol: "person.2", value: data.personnel)
                NovaListStat(title: "İşyeri", symbol: "building", value: data.workplaces)
            }
        }
    }
    private func periodCards(_ data: NovaStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Seçili dönemde", subtitle: "\(NovaStatisticsSnapshot.dayLabel(data.from_day)) – \(NovaStatisticsSnapshot.dayLabel(data.today))")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Fotoğraf analizi", value: data.analyses, symbol: "viewfinder", destination: .analyses)
                metric("Eğitim", value: data.trainings, symbol: "graduationcap", destination: .training)
                metric("Eğitim alan kişi", value: data.trained_people, symbol: "person.2", destination: .training)
                metric("Eğitim kaydı", value: data.training_enrollments, symbol: "person.crop.rectangle.stack", destination: .training)
            }
            NovaText(text: "Aynı eğitimdeki farklı firmalar eğitim sayısını artırmaz. Bir kişi farklı eğitimlerde birden fazla kişi × eğitim kaydı oluşturabilir.", style: .metaQuiet)
        }
    }
    private func metric(_ title: String, value: Int, symbol: String, destination: NovaDestination) -> some View {
        NovaListStat(title: title, symbol: symbol, value: value) { onNavigate(destination) }
            .accessibilityLabel("\(title): \(value). Tüm kayıtları aç")
    }
    private func activity(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) {
            VStack(alignment: .leading, spacing: 16) {
                sectionTitle("Aylık hareket", subtitle: "Bir aya dokunarak toplamını görün")
                Picker("Grafik", selection: $trainingChart) { Text("Analizler").tag(false); Text("Eğitimler").tag(true) }.pickerStyle(.segmented)
                chart(data)
                if let item = data.series.first(where: { $0.month == selectedMonth }) {
                    NovaText(text: "\(item.label) \(item.month.prefix(4)) · \(trainingChart ? item.trainings : item.analyses) \(trainingChart ? "eğitim" : "analiz")", style: .bodyStrong)
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
                }.buttonStyle(NovaRowPressStyle()).accessibilityLabel("\(item.label) \(item.month.prefix(4)), \(value) \(trainingChart ? "eğitim" : "analiz")")
            }
                }.frame(width: max(proxy.size.width, CGFloat(data.months * 52 - 8)), height: 148)
            }
        }.frame(height: 158).accessibilityIdentifier("nova.statistics.chart")
    }
    private func findings(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Uygunsuzluklar", subtitle: "Bugünkü açık kayıtların durumu")
            if let findings = data.findings {
                HStack(spacing: 8) {
                    NovaListStat(title: "Açık", symbol: "exclamationmark.circle", value: findings.open)
                    NovaListStat(title: "Gecikmiş", symbol: "clock.badge.exclamationmark", value: findings.overdue)
                    NovaListStat(title: "Doğrulamada", symbol: "checkmark.circle.badge.questionmark", value: findings.pending)
                }
                Divider()
                ForEach(["critical", "high", "medium", "low"], id: \.self) { key in
                    distribution(severityLabel(key), count: findings.severity[key] ?? 0, total: findings.open, tone: severityTone(key))
                }
                NovaText(text: "Seçili dönemde \(findings.opened) kayıt açıldı; bugün kapalı olan \(findings.closed) kayıt bu dönemde kapatıldı. İyileştirme önerileri dahil değildir.", style: .metaQuiet)
                link("Tüm uygunsuzlukları aç", destination: .findings)
            } else { unavailable("Uygunsuzluk istatistikleri bu hesapta henüz kullanılamıyor.") }
        } }
    }
    private func documents(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Evrak durumu", subtitle: "Takip edilen evrakların güncel durumu")
            if let docs = data.documents {
                let total = data.documentTotal ?? 0
                distribution("Geçerli", count: docs["valid"] ?? 0, total: total, tone: .accentInk)
                distribution("Süresi yaklaşıyor", count: docs["due_soon"] ?? 0, total: total, tone: .statusWarningInk)
                distribution("Süresi dolmuş", count: docs["expired"] ?? 0, total: total, tone: .statusDangerInk)
                distribution("Eksik", count: docs["missing"] ?? 0, total: total, tone: .statusNeutralInk)
                if total == 0 { NovaText(text: "Henüz takibe alınmış evrak yok.", style: .metaQuiet) }
                link("Evrak takibini aç", destination: .documentChecklist)
            } else { unavailable("Evrak istatistikleri bu hesapta henüz kullanılamıyor.") }
        } }
    }
    private func companies(_ data: NovaStatisticsSnapshot) -> some View {
        NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Firma dağılımı", subtitle: "İstatistiklerini filtrelemek için firma seçin")
            if data.selectedCompanies.isEmpty { NovaText(text: "Henüz aktif firma yok.", style: .metaQuiet) }
            ForEach(data.selectedCompanies) { item in
                Button { company = item.id } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "building.2").foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: item.name, style: .bodyStrong)
                            NovaText(text: "\(item.personnel) personel · \(item.workplaces) işyeri", style: .metaQuiet)
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
