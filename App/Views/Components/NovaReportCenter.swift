import SwiftUI
import UIKit

enum NovaGeneratedReportKind: String, CaseIterable, Identifiable, Codable {
    case company, training, pending, completed, visits, allProcesses
    var id: String { rawValue }
    var title: String {
        switch self {
        case .company: return RDLocalization.string("reports.nova.report.center.firma.raporu.cc00e3ad", table: .reports, fallback: "Firma raporu")
        case .training: return RDLocalization.string("reports.nova.report.center.egitim.raporu.47633e79", table: .reports, fallback: "Eğitim raporu")
        case .pending: return RDLocalization.string("reports.nova.report.center.bekleyen.isler.251e5952", table: .reports, fallback: "Bekleyen işler")
        case .completed: return RDLocalization.string("reports.nova.report.center.tamamlanan.isler.7785d550", table: .reports, fallback: "Tamamlanan işler")
        case .visits: return RDLocalization.string("reports.nova.report.center.ziyaret.raporu.be3e82d7", table: .reports, fallback: "Ziyaret raporu")
        case .allProcesses: return RDLocalization.string("reports.nova.report.center.tum.surecler.01b0f1a4", table: .reports, fallback: "Tüm süreçler")
        }
    }
    var detail: String {
        switch self {
        case .company: return RDLocalization.string("reports.nova.report.center.firmanin.butun.surec.sayilarini.tek.tabloda.gost.3f3bfa02", table: .reports, fallback: "Firmanın bütün süreç sayılarını tek tabloda gösterir.")
        case .training: return RDLocalization.string("reports.nova.report.center.gerceklesen.egitim.sure.ve.katilimci.kayitlarini.d06c0a45", table: .reports, fallback: "Gerçekleşen eğitim, süre ve katılımcı kayıtlarını listeler.")
        case .pending: return RDLocalization.string("reports.nova.report.center.bekleyen.yaklasan.ve.geciken.isleri.bir.araya.ge.4ee58834", table: .reports, fallback: "Bekleyen, yaklaşan ve geciken işleri bir araya getirir.")
        case .completed: return RDLocalization.string("reports.nova.report.center.toplam.kayitlardan.bekleyenler.cikarilarak.tamam.d0b8ee45", table: .reports, fallback: "Toplam kayıtlardan bekleyenler çıkarılarak tamamlanan işleri gösterir.")
        case .visits: return RDLocalization.string("reports.nova.report.center.ziyaret.tarihi.sure.isyeri.ve.gorusme.kayitlarin.fd7c7d42", table: .reports, fallback: "Ziyaret tarihi, süre, işyeri ve görüşme kayıtlarını listeler.")
        case .allProcesses: return RDLocalization.string("reports.nova.report.center.acil.durumdan.kontrol.listelerine.kadar.tum.taki.4c16e338", table: .reports, fallback: "Acil durumdan kontrol listelerine kadar tüm takip özetini verir.")
        }
    }
    var symbol: String {
        switch self {
        case .company: return "building.2"
        case .training: return "graduationcap"
        case .pending: return "clock.badge.exclamationmark"
        case .completed: return "checkmark.circle"
        case .visits: return "figure.walk"
        case .allProcesses: return "square.grid.2x2"
        }
    }
}

struct NovaGeneratedReport: Codable, Identifiable {
    let id: UUID
    let title: String
    let kind: NovaGeneratedReportKind
    let companyName: String?
    let period: String
    let format: String
    let createdAt: Date
    let filename: String
}

enum NovaGeneratedReportArchive {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ISGADA/GeneratedReports", isDirectory: true)
    }
    private static var indexURL: URL { directory.appendingPathComponent("index.json") }

    static func load() -> [NovaGeneratedReport] {
        guard let data = try? Data(contentsOf: indexURL),
              let values = try? JSONDecoder().decode([NovaGeneratedReport].self, from: data) else { return [] }
        return values.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func store(_ source: URL, title: String, kind: NovaGeneratedReportKind,
                      companyName: String?, period: String, format: String) throws -> NovaGeneratedReport {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let filename = id.uuidString.lowercased() + "." + source.pathExtension.lowercased()
        let destination = directory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.copyItem(at: source, to: destination)
        let value = NovaGeneratedReport(id: id, title: title, kind: kind, companyName: companyName,
            period: period, format: format, createdAt: Date(), filename: filename)
        var values = load()
        values.insert(value, at: 0)
        try JSONEncoder().encode(values).write(to: indexURL, options: [.atomic, .completeFileProtection])
        return value
    }

    static func url(for report: NovaGeneratedReport) -> URL { directory.appendingPathComponent(report.filename) }
}

private struct NovaReportLine {
    let columns: [String]
}

private struct NovaReportCreateRoute: Identifiable {
    let id = UUID()
    let kind: NovaGeneratedReportKind
    /// A report-type card is already an explicit answer to the first question.
    let skipsTypeSelection: Bool
}

private struct NovaReportContentOption: Identifiable {
    let id: String
    let title: String
    let symbol: String
}

struct NovaReportCenter: View {
    let identity: NovaSessionIdentity
    let onBack: () -> Void
    @State private var createRoute: NovaReportCreateRoute?
    @State private var archive = false
    @State private var recent: [NovaGeneratedReport] = []
    @State private var file: URL?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaListHeading(title: RDLocalization.string("reports.nova.report.center.rapor.merkezi.af121a01", table: .reports, fallback: "Rapor Merkezi"), onBack: onBack) {
                        NovaButton(label: RDLocalization.string("reports.nova.report.center.arsiv.c5b0065b", table: .reports, fallback: "Arşiv"), symbol: "archivebox", variant: .surface, compact: true) {
                            archive = true
                        }.accessibilityIdentifier("report.center.archive")
                    }
                    NovaListHint(text: RDLocalization.string("reports.nova.report.center.firma.egitim.bekleyen.isler.tamamlanan.isler.ve..6d6b0372", table: .reports, fallback: "Firma, eğitim, bekleyen işler, tamamlanan işler ve ziyaretler için kapsamlı rapor oluşturun; PDF veya Excel çıktısını indirin."))
                    NovaListActionButton(title: RDLocalization.string("reports.nova.report.center.yeni.rapor.olustur.9bffaeea", table: .reports, fallback: "Yeni rapor oluştur"), symbol: "doc.badge.plus", tone: .primary,
                        identifier: "report.center.create") {
                        createRoute = .init(kind: .company, skipsTypeSelection: false)
                    }
                    NovaListSectionHeading(title: RDLocalization.string("reports.nova.report.center.rapor.turleri.ca33c777", table: .reports, fallback: "Rapor türleri"),
                        count: RDLocalization.format("reports.nova.report.center.kind.count", table: .reports, fallback: "%d tür",
                            arguments: [NovaGeneratedReportKind.allCases.count]))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(NovaGeneratedReportKind.allCases) { kind in
                            Button { createRoute = .init(kind: kind, skipsTypeSelection: true) } label: {
                                NovaCard(padding: 13) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Image(systemName: kind.symbol).font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                                        NovaText(text: kind.title, style: .bodyStrong)
                                        NovaText(text: kind.detail, style: .metaQuiet).lineLimit(3)
                                    }.frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
                                }
                            }.buttonStyle(NovaRowPressStyle())
                                .accessibilityIdentifier("report.center.kind.\(kind.rawValue)")
                        }
                    }
                    if !recent.isEmpty {
                        NovaListSectionHeading(title: RDLocalization.string("reports.nova.report.center.son.olusturulanlar.3ee091ac", table: .reports, fallback: "Son oluşturulanlar"),
                            count: RDLocalization.format("reports.nova.report.center.recent.count", table: .reports, fallback: "%d rapor",
                                arguments: [recent.count]))
                        ForEach(recent.prefix(3)) { report in
                            Button { file = NovaGeneratedReportArchive.url(for: report) } label: {
                                NovaCard(padding: 13) {
                                    HStack(spacing: 10) {
                                        Image(systemName: report.format == "PDF" ? "doc.text" : "tablecells")
                                        VStack(alignment: .leading, spacing: 2) {
                                            NovaText(text: report.title, style: .bodyStrong)
                                            NovaText(text: [report.companyName, report.period, report.format]
                                                .compactMap { $0 }.joined(separator: " · "), style: .metaQuiet)
                                        }
                                        Spacer(); Image(systemName: "arrow.down.circle")
                                    }
                                }
                            }.buttonStyle(NovaRowPressStyle())
                        }
                    }
                }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, novaTabBarInset)
            }
        }
        .onAppear { recent = NovaGeneratedReportArchive.load() }
        .novaFullScreenCover(item: $createRoute, onDismiss: { recent = NovaGeneratedReportArchive.load() }) { route in
            NovaReportCreateFlow(identity: identity, initialKind: route.kind,
                                 skipsTypeSelection: route.skipsTypeSelection) { createRoute = nil }
        }
        .novaFullScreenCover(isPresented: $archive, onDismiss: { recent = NovaGeneratedReportArchive.load() }) {
            NovaProcessArchive(identity: identity, onBack: { archive = false })
        }
        .sheet(item: $file) { NovaFileShareSheet(url: $0) }
    }
}

private struct NovaReportCreateFlow: View {
    let identity: NovaSessionIdentity
    let initialKind: NovaGeneratedReportKind
    let skipsTypeSelection: Bool
    let onClose: () -> Void
    @State private var step: Int
    @State private var kind: NovaGeneratedReportKind
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var company: UUID?
    @State private var period = "90"
    @State private var format = "PDF"
    @State private var selectedContent: Set<String>
    @State private var customFields: [String] = []
    @State private var customValues: [String: String] = [:]
    @State private var customFieldDraft = ""
    @State private var loading = true
    @State private var working = false
    @State private var failure: String?
    @State private var generated: NovaGeneratedReport?
    @State private var file: URL?

    init(identity: NovaSessionIdentity, initialKind: NovaGeneratedReportKind,
         skipsTypeSelection: Bool = false,
         onClose: @escaping () -> Void) {
        self.identity = identity
        self.initialKind = initialKind
        self.skipsTypeSelection = skipsTypeSelection
        self.onClose = onClose
        _step = State(initialValue: skipsTypeSelection ? 1 : 0)
        _kind = State(initialValue: initialKind)
        _selectedContent = State(initialValue: Set(Self.contentOptions(for: initialKind).map(\.id)))
    }

    private var companyName: String? { companies.first { $0.id == company }?.name }
    private var periodTitle: String {
        switch period { case "30": return RDLocalization.string("reports.nova.report.center.son.30.gun.280ea33a", table: .reports, fallback: "Son 30 gün"); case "90": return RDLocalization.string("reports.nova.report.center.son.90.gun.e2c9a4f8", table: .reports, fallback: "Son 90 gün"); case "365": return RDLocalization.string("reports.nova.report.center.son.1.yil.33dc9924", table: .reports, fallback: "Son 1 yıl"); default: return RDLocalization.string("reports.nova.report.center.tum.zamanlar.d42e0115", table: .reports, fallback: "Tüm zamanlar") }
    }
    private var minimumStep: Int { skipsTypeSelection ? 1 : 0 }
    private var visibleStep: Int { skipsTypeSelection ? step : step + 1 }
    private var visibleTotal: Int { skipsTypeSelection ? 4 : 5 }
    private var stepTitle: String {
        [RDLocalization.string("reports.nova.report.center.rapor.turu.4d2a8466", table: .reports, fallback: "Rapor türü"), RDLocalization.string("reports.nova.report.center.kapsam.ve.donem.ba95ad7e", table: .reports, fallback: "Kapsam ve dönem"), RDLocalization.string("reports.nova.report.center.rapor.icerigi.2978ebd4", table: .reports, fallback: "Rapor içeriği"), RDLocalization.string("reports.nova.report.center.cikti.bicimi.6a2e1b7a", table: .reports, fallback: "Çıktı biçimi"), RDLocalization.string("reports.nova.report.center.kontrol.ve.olustur.42f6cea8", table: .reports, fallback: "Kontrol ve oluştur")][step]
    }
    private var contentOptions: [NovaReportContentOption] { Self.contentOptions(for: kind) }
    private var selectedContentTitles: [String] {
        contentOptions.filter { selectedContent.contains($0.id) }.map(\.title) + customFields
    }

    var body: some View {
        if let generated {
            NovaTaskSuccessView(title: RDLocalization.string("reports.nova.report.center.rapor.hazir.0ad6f4f3", table: .reports, fallback: "Rapor hazır"),
                message: RDLocalization.format("reports.nova.report.center.1.olusturuldu.ve.rapor.arsivi.ozel.raporlar.bolu.230c60c9", table: .reports, fallback: "%1$@ oluşturuldu ve Rapor Arşivi > Özel Raporlar bölümüne kaydedildi.", arguments: [String(describing: generated.title)]),
                nextTitle: RDLocalization.string("reports.nova.report.center.raporu.indir.a77b8e41", table: .reports, fallback: "Raporu indir"), onNext: { file = NovaGeneratedReportArchive.url(for: generated) },
                doneTitle: RDLocalization.string("reports.nova.report.center.rapor.merkezine.don.efdd2ccd", table: .reports, fallback: "Rapor Merkezine dön"), onDone: onClose)
                .sheet(item: $file) { NovaFileShareSheet(url: $0) }
        } else {
            NovaPageSurface(onEdgeBack: goBack) {
                VStack(spacing: 0) {
                    NovaTaskHeader(title: RDLocalization.string("reports.nova.report.center.rapor.olustur.7fe5db6d", table: .reports, fallback: "Rapor oluştur"), step: visibleStep, total: visibleTotal,
                        stepTitle: stepTitle, onClose: goBack)
                        .padding(.horizontal, 18).padding(.top, 10)
                    if loading {
                        NovaLoadingView(message: RDLocalization.string("reports.nova.report.center.rapor.secenekleri.hazirlaniyor.0287cf72", table: .reports, fallback: "Rapor seçenekleri hazırlanıyor…"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                flowStep
                                if let failure { NovaTaskErrorSummary(message: failure) }
                            }.padding(20).padding(.bottom, 18)
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == 4 ? RDLocalization.string("reports.nova.report.center.raporu.olustur.ad23d521", table: .reports, fallback: "Raporu oluştur") : RDLocalization.string("reports.nova.report.center.devam.4cf8f0bb", table: .reports, fallback: "Devam"),
                                primarySymbol: step == 4 ? "doc.badge.plus" : "arrow.right", isWorking: working,
                                canGoBack: true, onBack: goBack, onPrimary: advance)
                        }
                    }
                }
            }.task { await loadCompanies() }
        }
    }

    @ViewBuilder private var flowStep: some View {
        switch step {
        case 0:
            NovaText(text: RDLocalization.string("reports.nova.report.center.neyi.raporlamak.istiyorsunuz.26210e44", table: .reports, fallback: "Neyi raporlamak istiyorsunuz?"), style: .sectionTitle)
            ForEach(NovaGeneratedReportKind.allCases) { item in
                Button { selectKind(item) } label: {
                    NovaCard(padding: 13, tint: kind == item ? Color.green.opacity(0.10) : nil) {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: item.title, style: .bodyStrong)
                                NovaText(text: item.detail, style: .metaQuiet)
                            }
                            Spacer(); Image(systemName: kind == item ? "checkmark.circle.fill" : "circle")
                        }
                    }
                }.buttonStyle(NovaRowPressStyle())
            }
        case 1:
            NovaText(text: RDLocalization.string("reports.nova.report.center.firma.ve.donem.ef19139e", table: .reports, fallback: "Firma ve dönem"), style: .sectionTitle)
            NovaFilterField(label: "Firma", options: [.init(id: nil, title: RDLocalization.string("reports.nova.report.center.tum.firmalar.7e5cae36", table: .reports, fallback: "Tüm firmalar"))] + companies.map {
                .init(id: $0.id.uuidString, title: $0.name)
            }, selected: company?.uuidString, identifier: "report.create.company") {
                company = $0.flatMap(UUID.init(uuidString:))
            }
            Picker(RDLocalization.string("reports.nova.report.center.donem.69a6690a", table: .reports, fallback: "Dönem"), selection: $period) {
                Text(RDLocalization.string("reports.nova.report.center.son.30.gun.0c3e510d", table: .reports, fallback: "Son 30 gün")).tag("30"); Text(RDLocalization.string("reports.nova.report.center.son.90.gun.df60a216", table: .reports, fallback: "Son 90 gün")).tag("90")
                Text(RDLocalization.string("reports.nova.report.center.son.1.yil.48beda4d", table: .reports, fallback: "Son 1 yıl")).tag("365"); Text(RDLocalization.string("reports.nova.report.center.tum.zamanlar.3949f1d7", table: .reports, fallback: "Tüm zamanlar")).tag("all")
            }.pickerStyle(.segmented)
        case 2:
            reportContentStep
        case 3:
            NovaText(text: RDLocalization.string("reports.nova.report.center.cikti.bicimi.0794bd57", table: .reports, fallback: "Çıktı biçimi"), style: .sectionTitle)
            Picker(RDLocalization.string("reports.nova.report.center.cikti.b39c791d", table: .reports, fallback: "Çıktı"), selection: $format) { Text("PDF").tag("PDF"); Text("Excel").tag("Excel") }
                .pickerStyle(.segmented)
            NovaWhyDisclosure {
                NovaText(text: RDLocalization.string("reports.nova.report.center.pdf.paylasim.ve.imza.surecleri.icin.excel.ise.fi.211d8487", table: .reports, fallback: "PDF paylaşım ve imza süreçleri için; Excel ise filtreleme ve kurum içi çalışma için uygundur."), style: .metaQuiet)
            }
        default:
            NovaText(text: RDLocalization.string("reports.nova.report.center.rapor.ozeti.64d076b4", table: .reports, fallback: "Rapor özeti"), style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    summary("Kapsam", kind.title); summary("Firma", companyName ?? RDLocalization.string("reports.nova.report.center.tum.firmalar.c039d79f", table: .reports, fallback: "Tüm firmalar"))
                    summary(RDLocalization.string("reports.nova.report.center.donem.e51fec96", table: .reports, fallback: "Dönem"), periodTitle)
                    summary(RDLocalization.string("reports.nova.report.center.icerik.67331564", table: .reports, fallback: "İçerik"), RDLocalization.format("reports.nova.report.center.1.baslik.0a96228b", table: .reports, fallback: "%1$@ başlık", arguments: [String(describing: selectedContentTitles.count)]))
                    summary(RDLocalization.string("reports.nova.report.center.cikti.0b13d512", table: .reports, fallback: "Çıktı"), format)
                }
            }
        }
    }

    private var reportContentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: RDLocalization.string("reports.nova.report.center.raporda.neler.yer.alsin.5f78a7cc", table: .reports, fallback: "Raporda neler yer alsın?"), style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("reports.nova.report.center.onerilen.basliklarin.tamami.secili.gelir.istemed.c35a22b5", table: .reports, fallback: "Önerilen başlıkların tamamı seçili gelir. İstemediğiniz başlıkları çıkarabilir veya rapora özel bir alan ekleyebilirsiniz."))
            HStack(spacing: 8) {
                NovaCompactActionButton(title: RDLocalization.string("reports.nova.report.center.tumunu.sec.edbfe603", table: .reports, fallback: "Tümünü seç"), symbol: "checkmark.circle") {
                    selectedContent = Set(contentOptions.map(\.id))
                }
                NovaCompactActionButton(title: RDLocalization.string("reports.nova.report.center.secimi.temizle.3871a9a3", table: .reports, fallback: "Seçimi temizle"), symbol: "xmark.circle") {
                    selectedContent.removeAll()
                }
            }
            ForEach(contentOptions) { option in
                Button {
                    if selectedContent.contains(option.id) { selectedContent.remove(option.id) }
                    else { selectedContent.insert(option.id) }
                } label: {
                    NovaCard(padding: 13, tint: selectedContent.contains(option.id) ? Color.green.opacity(0.10) : nil) {
                        HStack(spacing: 11) {
                            Image(systemName: option.symbol).frame(width: 24)
                            NovaText(text: option.title, style: .bodyStrong)
                            Spacer(minLength: 0)
                            Image(systemName: selectedContent.contains(option.id) ? "checkmark.circle.fill" : "circle")
                        }.contentShape(Rectangle())
                    }
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityIdentifier("report.create.content.\(option.id)")
            }
            NovaCard(padding: 13) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: RDLocalization.string("reports.nova.report.center.ozel.alan.ekle.64bfb309", table: .reports, fallback: "Özel alan ekle"), style: .bodyStrong)
                    HStack(spacing: 8) {
                        TextField(RDLocalization.string("reports.nova.report.center.orn.yonetici.notu.6b56c867", table: .reports, fallback: "Örn. Yönetici notu"), text: $customFieldDraft)
                            .font(NovaFont.font(.body)).textInputAutocapitalization(.sentences)
                        Button(action: addCustomField) {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                        }.buttonStyle(NovaRowPressStyle())
                            .accessibilityLabel(RDLocalization.string("reports.nova.report.center.ozel.alani.ekle.96178def", table: .reports, fallback: "Özel alanı ekle"))
                            .accessibilityIdentifier("report.create.custom.add")
                    }
                    ForEach(customFields, id: \.self) { title in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                NovaText(text: title, style: .label)
                                Spacer(minLength: 0)
                                Button(role: .destructive) { removeCustomField(title) } label: {
                                    Image(systemName: "xmark.circle").frame(width: 44, height: 44)
                                }.buttonStyle(NovaRowPressStyle()).accessibilityLabel(RDLocalization.format("reports.nova.report.center.1.alanini.kaldir.b5d91269", table: .reports, fallback: "%1$@ alanını kaldır", arguments: [String(describing: title)]))
                            }
                            TextField(RDLocalization.string("reports.nova.report.center.bu.raporda.gorunecek.deger.istege.bagli.fa3e0500", table: .reports, fallback: "Bu raporda görünecek değer (isteğe bağlı)"),
                                      text: Binding(get: { customValues[title] ?? "" },
                                                    set: { customValues[title] = $0 }))
                                .font(NovaFont.font(.body)).padding(11).novaControlBackground(cornerRadius: 12)
                        }
                    }
                }
            }
        }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        HStack { NovaText(text: label, style: .metaQuiet); Spacer(); NovaText(text: value, style: .bodyStrong) }
    }
    private func goBack() { failure = nil; if step > minimumStep { step -= 1 } else { onClose() } }
    private func advance() {
        failure = nil
        if step == 2 && selectedContent.isEmpty && customFields.isEmpty {
            failure = RDLocalization.string("reports.nova.report.center.rapora.en.az.bir.baslik.ekleyin.880be084", table: .reports, fallback: "Rapora en az bir başlık ekleyin.")
        } else if step < 4 { step += 1 }
        else { Task { await generate() } }
    }

    private func selectKind(_ item: NovaGeneratedReportKind) {
        kind = item
        selectedContent = Set(Self.contentOptions(for: item).map(\.id))
        customFields = []
        customValues = [:]
        customFieldDraft = ""
    }

    private func addCustomField() {
        let title = customFieldDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.utf8.count <= 80,
              !customFields.contains(where: { $0.localizedCaseInsensitiveCompare(title) == .orderedSame }) else { return }
        customFields.append(title)
        customValues[title] = ""
        customFieldDraft = ""
    }

    private func removeCustomField(_ title: String) {
        customFields.removeAll { $0 == title }
        customValues.removeValue(forKey: title)
    }
    private func loadCompanies() async {
        do { companies = try await NovaAnalysisWorkspace.companyOptions(identity: identity) }
        catch { failure = RDLocalization.string("reports.nova.report.center.firmalar.yuklenemedi.tum.firmalar.kapsaminda.dev.b1c5b111", table: .reports, fallback: "Firmalar yüklenemedi; tüm firmalar kapsamında devam edebilirsiniz.") }
        loading = false
    }

    @MainActor private func generate() async {
        working = true; failure = nil
        defer { working = false }
        do {
            let result = try await reportLines()
            let title = "\(kind.title) · \(companyName ?? "Tüm firmalar")"
            let temporary = try Self.write(title: title, subtitle: periodTitle, headers: result.headers,
                lines: result.lines, format: format)
            generated = try NovaGeneratedReportArchive.store(temporary, title: title, kind: kind,
                companyName: companyName, period: periodTitle, format: format)
        } catch {
            failure = RDLocalization.string("reports.nova.report.center.rapor.olusturulamadi.baglantinizi.kontrol.edip.y.df48526c", table: .reports, fallback: "Rapor oluşturulamadı. Bağlantınızı kontrol edip yeniden deneyin.")
        }
    }

    private func reportLines() async throws -> (headers: [String], lines: [NovaReportLine]) {
        if kind == .training {
            var sessions: [NovaTrainingSession] = []; var after: UUID?; var seen = Set<UUID>()
            let service = NovaTrainingSessionService(identity: identity)
            repeat {
                let page = try await service.list(after: after); sessions += page.rows; after = page.next_id
                if let after, !seen.insert(after).inserted { break }
            } while after != nil
            let rows = sessions.filter { session in
                (company == nil || session.companies.contains { $0.company_id == company }) && withinPeriod(session.held_on)
            }
            let options = contentOptions.filter { selectedContent.contains($0.id) }
            let headers = options.map(\.title) + customFields
            return (headers, rows.map { session in
                let values = ["training": session.title, "date": session.held_on,
                              "trainer": session.trainer,
                              "company": session.companies.map(\.company_name).joined(separator: ", "),
                              "participants": "\(session.count)"]
                return .init(columns: options.map { values[$0.id] ?? "" } + customFields.map { customValues[$0] ?? "" })
            })
        }
        if kind == .visits {
            var page = try JSONDecoder().decode(NovaProcessPage.self,
                from: await NovaProcessService(identity: identity).read(kind: "site_visit", company: company))
            var rows = page.rows
            while page.has_more && rows.count < 500 {
                page = try JSONDecoder().decode(NovaProcessPage.self,
                    from: await NovaProcessService(identity: identity).read(kind: "site_visit", company: company, offset: rows.count))
                rows += page.rows
            }
            rows = rows.filter { withinPeriod($0.date) }
            let options = contentOptions.filter { selectedContent.contains($0.id) }
            let headers = options.map(\.title) + customFields
            return (headers, rows.map { row in
                let values = ["company": row.company_name, "workplace": row.workplace_name ?? "",
                              "date": String(row.date.prefix(10)), "duration": row.values["duration_minutes"]?.text ?? "",
                              "contact": row.values["responsible_contact"]?.text ?? "",
                              "note": row.values["expert_note"]?.text ?? ""]
                return .init(columns: options.map { values[$0.id] ?? "" } + customFields.map { customValues[$0] ?? "" })
            })
        }
        let snapshot = try await NovaModuleTrackingLoader.load(identity: identity, company: company)
        let rows = snapshot.rows.filter { row in
            guard selectedContent.contains(row.kind) else { return false }
            switch kind {
            case .pending: return (row.pending ?? 0) > 0 || (row.overdue ?? 0) > 0
            case .completed: return max(0, (row.total ?? 0) - (row.pending ?? 0)) > 0
            default: return true
            }
        }
        return (["Firma", RDLocalization.string("reports.nova.report.center.surec.f17c3801", table: .reports, fallback: "Süreç"), "Toplam", "Tamamlanan", "Bekleyen", "Geciken", RDLocalization.string("reports.nova.report.center.yaklasan.2253f9c7", table: .reports, fallback: "Yaklaşan")] + customFields, rows.map { row in
            .init(columns: [row.company_name, NovaModuleTrackingSnapshot.Summary(id: row.kind,
                available: row.available, total: row.total ?? 0, pending: row.pending ?? 0,
                overdue: row.overdue ?? 0, upcoming: row.upcoming ?? 0, review: row.review ?? 0,
                nextOn: row.next_on).title, "\(row.total ?? 0)",
                String(max(0, (row.total ?? 0) - (row.pending ?? 0))), "\(row.pending ?? 0)",
                "\(row.overdue ?? 0)", "\(row.upcoming ?? 0)"] + customFields.map { customValues[$0] ?? "" })
        })
    }

    private static func contentOptions(for kind: NovaGeneratedReportKind) -> [NovaReportContentOption] {
        switch kind {
        case .training:
            return [
                .init(id: "training", title: RDLocalization.string("reports.nova.report.center.egitim.128cc7fa", table: .reports, fallback: "Eğitim"), symbol: "graduationcap"),
                .init(id: "date", title: "Tarih", symbol: "calendar"),
                .init(id: "trainer", title: RDLocalization.string("reports.nova.report.center.egitici.d42e0f3f", table: .reports, fallback: "Eğitici"), symbol: "person.crop.rectangle"),
                .init(id: "company", title: "Firma", symbol: "building.2"),
                .init(id: "participants", title: RDLocalization.string("reports.nova.report.center.katilimci.e7b876c9", table: .reports, fallback: "Katılımcı"), symbol: "person.3")
            ]
        case .visits:
            return [
                .init(id: "company", title: "Firma", symbol: "building.2"),
                .init(id: "workplace", title: RDLocalization.string("reports.nova.report.center.isyeri.7af4fd48", table: .reports, fallback: "İşyeri"), symbol: "building"),
                .init(id: "date", title: "Tarih", symbol: "calendar"),
                .init(id: "duration", title: RDLocalization.string("reports.nova.report.center.sure.c1b71093", table: .reports, fallback: "Süre"), symbol: "clock"),
                .init(id: "contact", title: RDLocalization.string("reports.nova.report.center.gorusulen.kisi.7b54ab80", table: .reports, fallback: "Görüşülen kişi"), symbol: "person"),
                .init(id: "note", title: "Not", symbol: "text.alignleft")
            ]
        default:
            return [
                .init(id: "risk_assessment", title: RDLocalization.string("reports.nova.report.center.risk.degerlendirmeleri.15bb5974", table: .reports, fallback: "Risk değerlendirmeleri"), symbol: "checkmark.shield"),
                .init(id: "emergency_plan", title: RDLocalization.string("reports.nova.report.center.acil.durum.planlari.d90b67a4", table: .reports, fallback: "Acil durum planları"), symbol: "light.beacon.max"),
                .init(id: "drill", title: "Tatbikatlar", symbol: "figure.run"),
                .init(id: "appointment", title: RDLocalization.string("reports.nova.report.center.atama.ve.temsilciler.20437883", table: .reports, fallback: "Atama ve temsilciler"), symbol: "person.badge.shield.checkmark"),
                .init(id: "checklist_run", title: RDLocalization.string("reports.nova.report.center.kontrol.listeleri.f19ad1a3", table: .reports, fallback: "Kontrol listeleri"), symbol: "checklist"),
                .init(id: "equipment", title: RDLocalization.string("reports.nova.report.center.periyodik.kontroller.ff270a58", table: .reports, fallback: "Periyodik kontroller"), symbol: "checkmark.shield"),
                .init(id: "nonconformity", title: "Uygunsuzluklar", symbol: "exclamationmark.triangle"),
                .init(id: "training", title: RDLocalization.string("reports.nova.report.center.egitimler.0e20cd3d", table: .reports, fallback: "Eğitimler"), symbol: "graduationcap"),
                .init(id: "site_visit", title: "Ziyaretler", symbol: "figure.walk"),
                .init(id: "annual_work_plan", title: RDLocalization.string("reports.nova.report.center.yillik.calisma.planlari.2e90a4ec", table: .reports, fallback: "Yıllık çalışma planları"), symbol: "calendar"),
                .init(id: "board", title: RDLocalization.string("reports.nova.report.center.kurul.ve.toplantilar.384e377e", table: .reports, fallback: "Kurul ve toplantılar"), symbol: "person.3"),
                .init(id: "katip_contract", title: RDLocalization.string("reports.nova.report.center.isg.katip.sozlesmeleri.279f78c6", table: .reports, fallback: "İSG-KATİP sözleşmeleri"), symbol: "doc.text")
            ]
        }
    }

    private func withinPeriod(_ value: String) -> Bool {
        guard period != "all" else { return true }
        let prefix = String(value.prefix(10))
        guard let date = Self.dayFormatter.date(from: prefix), let days = Int(period),
              let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return true }
        return date >= threshold
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func write(title: String, subtitle: String, headers: [String], lines: [NovaReportLine], format: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if format == "Excel" {
            let url = base.appendingPathComponent("rapor.csv")
            let escape: (String) -> String = { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
            let content = ([headers] + lines.map(\.columns)).map { $0.map(escape).joined(separator: ";") }.joined(separator: "\n")
            try ("\u{FEFF}" + content).data(using: .utf8)!.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        }
        let url = base.appendingPathComponent("rapor.pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        try renderer.writePDF(to: url) { context in
            var y: CGFloat = 46
            func pageHeader() {
                context.beginPage(); y = 46
                (title as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 20)])
                y += 29
                (subtitle as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray])
                y += 26
            }
            pageHeader()
            let all = [NovaReportLine(columns: headers)] + lines
            for (index, line) in all.enumerated() {
                let text = line.columns.joined(separator: "  •  ")
                let rect = CGRect(x: 40, y: y, width: 515, height: 52)
                (text as NSString).draw(in: rect, withAttributes: [.font: index == 0 ? UIFont.boldSystemFont(ofSize: 10) : UIFont.systemFont(ofSize: 9)])
                y += 42
                if y > 785 { pageHeader() }
            }
            if lines.isEmpty {
                (RDLocalization.string("reports.nova.report.center.secilen.kapsamda.kayit.bulunamadi.7e9fac58", table: .reports, fallback: "Seçilen kapsamda kayıt bulunamadı.") as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            }
        }
        return url
    }
}
