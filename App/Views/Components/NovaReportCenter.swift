import SwiftUI
import UIKit

enum NovaGeneratedReportKind: String, CaseIterable, Identifiable, Codable {
    case company, training, pending, completed, visits, allProcesses
    var id: String { rawValue }
    var title: String {
        switch self {
        case .company: return "Firma raporu"
        case .training: return "Eğitim raporu"
        case .pending: return "Bekleyen işler"
        case .completed: return "Tamamlanan işler"
        case .visits: return "Ziyaret raporu"
        case .allProcesses: return "Tüm süreçler"
        }
    }
    var detail: String {
        switch self {
        case .company: return "Firmanın bütün süreç sayılarını tek tabloda gösterir."
        case .training: return "Gerçekleşen eğitim, süre ve katılımcı kayıtlarını listeler."
        case .pending: return "Bekleyen, yaklaşan ve geciken işleri bir araya getirir."
        case .completed: return "Toplam kayıtlardan bekleyenler çıkarılarak tamamlanan işleri gösterir."
        case .visits: return "Ziyaret tarihi, süre, işyeri ve görüşme kayıtlarını listeler."
        case .allProcesses: return "Acil durumdan kontrol listelerine kadar tüm takip özetini verir."
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
                    NovaListHeading(title: "Rapor Merkezi", onBack: onBack) {
                        NovaButton(label: "Arşiv", symbol: "archivebox", variant: .surface, compact: true) {
                            archive = true
                        }.accessibilityIdentifier("report.center.archive")
                    }
                    NovaHelpHint(text: "Firma, eğitim, bekleyen işler, tamamlanan işler ve ziyaretler için kapsamlı rapor oluşturun; PDF veya Excel çıktısını indirin.")
                    NovaButton(label: "Yeni rapor oluştur", symbol: "doc.badge.plus", variant: .primary) {
                        createRoute = .init(kind: .company, skipsTypeSelection: false)
                    }.accessibilityIdentifier("report.center.create")
                    NovaText(text: "Rapor türleri", style: .sectionTitle)
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
                        NovaText(text: "Son oluşturulanlar", style: .sectionTitle)
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
        switch period { case "30": return "Son 30 gün"; case "90": return "Son 90 gün"; case "365": return "Son 1 yıl"; default: return "Tüm zamanlar" }
    }
    private var minimumStep: Int { skipsTypeSelection ? 1 : 0 }
    private var visibleStep: Int { skipsTypeSelection ? step : step + 1 }
    private var visibleTotal: Int { skipsTypeSelection ? 4 : 5 }
    private var stepTitle: String {
        ["Rapor türü", "Kapsam ve dönem", "Rapor içeriği", "Çıktı biçimi", "Kontrol ve oluştur"][step]
    }
    private var contentOptions: [NovaReportContentOption] { Self.contentOptions(for: kind) }
    private var selectedContentTitles: [String] {
        contentOptions.filter { selectedContent.contains($0.id) }.map(\.title) + customFields
    }

    var body: some View {
        if let generated {
            NovaTaskSuccessView(title: "Rapor hazır",
                message: "\(generated.title) oluşturuldu ve Rapor Arşivi > Özel Raporlar bölümüne kaydedildi.",
                nextTitle: "Raporu indir", onNext: { file = NovaGeneratedReportArchive.url(for: generated) },
                doneTitle: "Rapor Merkezine dön", onDone: onClose)
                .sheet(item: $file) { NovaFileShareSheet(url: $0) }
        } else {
            NovaPageSurface(onEdgeBack: goBack) {
                VStack(spacing: 0) {
                    NovaTaskHeader(title: "Rapor oluştur", step: visibleStep, total: visibleTotal,
                        stepTitle: stepTitle, onClose: goBack)
                        .padding(.horizontal, 18).padding(.top, 10)
                    if loading {
                        NovaLoadingView(message: "Rapor seçenekleri hazırlanıyor…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                flowStep
                                if let failure { NovaTaskErrorSummary(message: failure) }
                            }.padding(20).padding(.bottom, 18)
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == 4 ? "Raporu oluştur" : "Devam",
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
            NovaText(text: "Neyi raporlamak istiyorsunuz?", style: .sectionTitle)
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
            NovaText(text: "Firma ve dönem", style: .sectionTitle)
            NovaFilterField(label: "Firma", options: [.init(id: nil, title: "Tüm firmalar")] + companies.map {
                .init(id: $0.id.uuidString, title: $0.name)
            }, selected: company?.uuidString, identifier: "report.create.company") {
                company = $0.flatMap(UUID.init(uuidString:))
            }
            Picker("Dönem", selection: $period) {
                Text("Son 30 gün").tag("30"); Text("Son 90 gün").tag("90")
                Text("Son 1 yıl").tag("365"); Text("Tüm zamanlar").tag("all")
            }.pickerStyle(.segmented)
        case 2:
            reportContentStep
        case 3:
            NovaText(text: "Çıktı biçimi", style: .sectionTitle)
            Picker("Çıktı", selection: $format) { Text("PDF").tag("PDF"); Text("Excel").tag("Excel") }
                .pickerStyle(.segmented)
            NovaWhyDisclosure {
                NovaText(text: "PDF paylaşım ve imza süreçleri için; Excel ise filtreleme ve kurum içi çalışma için uygundur.", style: .metaQuiet)
            }
        default:
            NovaText(text: "Rapor özeti", style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    summary("Kapsam", kind.title); summary("Firma", companyName ?? "Tüm firmalar")
                    summary("Dönem", periodTitle)
                    summary("İçerik", "\(selectedContentTitles.count) başlık")
                    summary("Çıktı", format)
                }
            }
        }
    }

    private var reportContentStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: "Raporda neler yer alsın?", style: .sectionTitle)
            NovaHelpHint(text: "Önerilen başlıkların tamamı seçili gelir. İstemediğiniz başlıkları çıkarabilir veya rapora özel bir alan ekleyebilirsiniz.")
            HStack(spacing: 8) {
                NovaCompactActionButton(title: "Tümünü seç", symbol: "checkmark.circle") {
                    selectedContent = Set(contentOptions.map(\.id))
                }
                NovaCompactActionButton(title: "Seçimi temizle", symbol: "xmark.circle") {
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
                    NovaText(text: "Özel alan ekle", style: .bodyStrong)
                    HStack(spacing: 8) {
                        TextField("Örn. Yönetici notu", text: $customFieldDraft)
                            .font(NovaFont.font(.body)).textInputAutocapitalization(.sentences)
                        Button(action: addCustomField) {
                            Image(systemName: "plus").frame(width: 44, height: 44)
                        }.buttonStyle(NovaRowPressStyle())
                            .accessibilityLabel("Özel alanı ekle")
                            .accessibilityIdentifier("report.create.custom.add")
                    }
                    ForEach(customFields, id: \.self) { title in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                NovaText(text: title, style: .label)
                                Spacer(minLength: 0)
                                Button(role: .destructive) { removeCustomField(title) } label: {
                                    Image(systemName: "xmark.circle").frame(width: 44, height: 44)
                                }.buttonStyle(NovaRowPressStyle()).accessibilityLabel("\(title) alanını kaldır")
                            }
                            TextField("Bu raporda görünecek değer (isteğe bağlı)",
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
            failure = "Rapora en az bir başlık ekleyin."
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
        catch { failure = "Firmalar yüklenemedi; tüm firmalar kapsamında devam edebilirsiniz." }
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
            failure = "Rapor oluşturulamadı. Bağlantınızı kontrol edip yeniden deneyin."
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
        return (["Firma", "Süreç", "Toplam", "Tamamlanan", "Bekleyen", "Geciken", "Yaklaşan"] + customFields, rows.map { row in
            .init(columns: [row.company_name, NovaModuleTrackingSnapshot.Summary(id: row.kind,
                available: row.available, total: row.total ?? 0, pending: row.pending ?? 0,
                overdue: row.overdue ?? 0, upcoming: row.upcoming ?? 0, review: row.review ?? 0,
                nextOn: row.next_on).title, "\(row.total ?? 0)",
                "\(max(0, (row.total ?? 0) - (row.pending ?? 0)))", "\(row.pending ?? 0)",
                "\(row.overdue ?? 0)", "\(row.upcoming ?? 0)"] + customFields.map { customValues[$0] ?? "" })
        })
    }

    private static func contentOptions(for kind: NovaGeneratedReportKind) -> [NovaReportContentOption] {
        switch kind {
        case .training:
            return [
                .init(id: "training", title: "Eğitim", symbol: "graduationcap"),
                .init(id: "date", title: "Tarih", symbol: "calendar"),
                .init(id: "trainer", title: "Eğitici", symbol: "person.crop.rectangle"),
                .init(id: "company", title: "Firma", symbol: "building.2"),
                .init(id: "participants", title: "Katılımcı", symbol: "person.3")
            ]
        case .visits:
            return [
                .init(id: "company", title: "Firma", symbol: "building.2"),
                .init(id: "workplace", title: "İşyeri", symbol: "building"),
                .init(id: "date", title: "Tarih", symbol: "calendar"),
                .init(id: "duration", title: "Süre", symbol: "clock"),
                .init(id: "contact", title: "Görüşülen kişi", symbol: "person"),
                .init(id: "note", title: "Not", symbol: "text.alignleft")
            ]
        default:
            return [
                .init(id: "risk_assessment", title: "Risk değerlendirmeleri", symbol: "checkmark.shield"),
                .init(id: "emergency_plan", title: "Acil durum planları", symbol: "light.beacon.max"),
                .init(id: "drill", title: "Tatbikatlar", symbol: "figure.run"),
                .init(id: "appointment", title: "Atama ve temsilciler", symbol: "person.badge.shield.checkmark"),
                .init(id: "checklist_run", title: "Kontrol listeleri", symbol: "checklist"),
                .init(id: "equipment", title: "Periyodik kontroller", symbol: "checkmark.shield"),
                .init(id: "nonconformity", title: "Uygunsuzluklar", symbol: "exclamationmark.triangle"),
                .init(id: "training", title: "Eğitimler", symbol: "graduationcap"),
                .init(id: "site_visit", title: "Ziyaretler", symbol: "figure.walk"),
                .init(id: "annual_work_plan", title: "Yıllık çalışma planları", symbol: "calendar"),
                .init(id: "board", title: "Kurul ve toplantılar", symbol: "person.3"),
                .init(id: "katip_contract", title: "İSG-KATİP sözleşmeleri", symbol: "doc.text"),
                .init(id: "work_permit", title: "Çalışma izinleri", symbol: "doc.badge.gearshape"),
                .init(id: "ppe", title: "KKD zimmetleri", symbol: "shield")
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
                ("Seçilen kapsamda kayıt bulunamadı." as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: [.font: UIFont.systemFont(ofSize: 11)])
            }
        }
        return url
    }
}
