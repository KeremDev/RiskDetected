import SwiftUI

/// All values are server aggregates. Current stock and period activity have
/// separate headings; unavailable sources never become a zero or a score.
struct NovaStatisticsScreen: View {
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
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heading
                    filters
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
            }
            .refreshable { revision += 1 }
            .task(id: requestKey) { await refresh(key: requestKey) }
        }.accessibilityIdentifier("nova.statistics.screen")
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
            Menu {
                Button("Tüm firmalar") { company = nil }
                ForEach(companyOptions) { item in Button(item.name) { company = item.id } }
            } label: {
                HStack {
                    Image(systemName: "building.2")
                    NovaText(text: companyName, style: .bodyStrong)
                    Spacer(); Image(systemName: "chevron.down").font(NovaFont.font(.meta))
                }.padding(14).background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            }.accessibilityIdentifier("nova.statistics.company")
            Picker("Dönem", selection: $months) {
                Text("Bu ay").tag(1); Text("3 ay").tag(3); Text("6 ay").tag(6); Text("12 ay").tag(12)
            }.pickerStyle(.segmented).accessibilityIdentifier("nova.statistics.period")
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
        NovaCard(padding: 20, tint: NovaColorToken.inverse.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    NovaText(text: "PORTFÖYÜNÜZ", style: .overline, color: NovaColorToken.onInverse.color(in: scheme))
                    Spacer(); Image(systemName: "chart.bar.xaxis").foregroundStyle(NovaColorToken.accent.color(in: scheme))
                }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    heroNumber(data.company_count, "Aktif firma")
                    heroNumber(data.personnel, "Personel")
                    heroNumber(data.workplaces, "İşyeri")
                }
                NovaText(text: "Bugünkü kayıtlar · dönem filtresinden bağımsız", style: .meta, color: NovaColorToken.onInverse.color(in: scheme).opacity(0.65))
            }
        }
    }
    private func heroNumber(_ count: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(count.formatted()).font(.custom("PlusJakartaSans-ExtraBold", size: 30)).foregroundStyle(NovaColorToken.onInverse.color(in: scheme)).minimumScaleFactor(0.6).lineLimit(1)
            NovaText(text: label, style: .meta, color: NovaColorToken.onInverse.color(in: scheme).opacity(0.8))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func periodCards(_ data: NovaStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Seçili dönemde", subtitle: "\(NovaStatisticsSnapshot.dayLabel(data.from_day)) – \(NovaStatisticsSnapshot.dayLabel(data.today))")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metric("Fotoğraf analizi", value: data.analyses, symbol: "viewfinder", tone: .statusInfoInk, note: "Tamamlanan", destination: .analyses)
                metric("Eğitim", value: data.trainings, symbol: "graduationcap", tone: .accentInk, note: "Gerçekleşen eğitim", destination: .training)
                metric("Eğitim alan kişi", value: data.trained_people, symbol: "person.2", tone: .accentInk, note: "Tekil personel", destination: .training)
                metric("Eğitim kaydı", value: data.training_enrollments, symbol: "person.crop.rectangle.stack", tone: .statusInfoInk, note: "Kişi × eğitim", destination: .training)
            }
            NovaText(text: "Aynı eğitimdeki farklı firmalar eğitim sayısını artırmaz. Bir kişi farklı eğitimlerde birden fazla kişi × eğitim kaydı oluşturabilir.", style: .metaQuiet)
        }
    }
    private func metric(_ title: String, value: Int, symbol: String, tone: NovaColorToken, note: String, destination: NovaDestination) -> some View {
        Button { onNavigate(destination) } label: {
            NovaCard(padding: 15) { VStack(alignment: .leading, spacing: 9) {
                HStack { Image(systemName: symbol).foregroundStyle(tone.color(in: scheme)); Spacer(); Image(systemName: "arrow.up.right").font(NovaFont.font(.micro)).foregroundStyle(NovaFont.secondaryInk) }
                Text(value.formatted()).font(.custom("PlusJakartaSans-ExtraBold", size: 27)).foregroundStyle(NovaColorToken.text.color(in: scheme))
                NovaText(text: title, style: .bodyStrong)
                NovaText(text: note, style: .micro)
            }.frame(maxWidth: .infinity, alignment: .leading) }
        }.buttonStyle(.plain).accessibilityLabel("\(title): \(value). Tüm kayıtları aç")
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
                }.buttonStyle(.plain).accessibilityLabel("\(item.label) \(item.month.prefix(4)), \(value) \(trainingChart ? "eğitim" : "analiz")")
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
                    statusNumber("Açık", findings.open, .text)
                    statusNumber("Gecikmiş", findings.overdue, .statusDangerInk)
                    statusNumber("Doğrulamada", findings.pending, .statusWarningInk)
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
                }.buttonStyle(.plain)
            }
            link("Firmaları aç", destination: .companies)
        } }
    }
    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) { NovaText(text: title, style: .sectionTitle); NovaText(text: subtitle, style: .metaQuiet) }
    }
    private func statusNumber(_ title: String, _ count: Int, _ tone: NovaColorToken) -> some View {
        VStack(alignment: .leading, spacing: 5) { NovaText(text: count.formatted(), style: .screenTitle, color: tone.color(in: scheme)); NovaText(text: title, style: .micro) }.frame(maxWidth: .infinity, alignment: .leading)
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
        Button { onNavigate(destination) } label: { HStack { NovaText(text: title, style: .buttonSm, color: NovaColorToken.accentInk.color(in: scheme)); Spacer(); Image(systemName: "arrow.right") }.padding(.vertical, 6) }.buttonStyle(.plain)
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
