import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

private struct NovaRiskWizardFile: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// Risk level colours shared by chips, bars and the result list (mirrors the Excel bands).
enum NovaRiskLevelTone {
    static func colors(_ level: String, _ scheme: ColorScheme) -> (background: Color, ink: Color) {
        let dark = scheme == .dark
        func rgb(_ hex: UInt32, _ alpha: Double = 1) -> Color {
            Color(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255, blue: Double(hex & 255) / 255, opacity: alpha)
        }
        switch level {
        case "critical": return dark ? (rgb(0xFF5A50, 0.18), rgb(0xFF8A80)) : (rgb(0xFDECEC), rgb(0xB42318))
        case "high": return dark ? (rgb(0xFF9933, 0.18), rgb(0xFFB35C)) : (rgb(0xFFF4DE), rgb(0xC76A00))
        case "medium": return dark ? (rgb(0xF2D060, 0.16), rgb(0xF2D060)) : (rgb(0xFEF9C3), rgb(0x8A6100))
        case "low": return dark ? (rgb(0x50C878, 0.16), rgb(0x6FD08C)) : (rgb(0xE8F5EF), rgb(0x237A3B))
        default: return dark ? (rgb(0xAAB4BC, 0.14), rgb(0xAAB4BC)) : (rgb(0xEEF2F0), rgb(0x4B5563))
        }
    }
    static func bar(_ level: String) -> Color {
        switch level {
        case "critical": return Color(red: 0.84, green: 0.29, blue: 0.25)
        case "high": return Color(red: 0.89, green: 0.55, blue: 0.13)
        case "medium": return Color(red: 0.89, green: 0.74, blue: 0.16)
        case "low": return Color(red: 0.29, green: 0.69, blue: 0.42)
        default: return Color(red: 0.65, green: 0.70, blue: 0.68)
        }
    }
    static let order = ["critical", "high", "medium", "low", "insignificant"]
    static let names = ["critical": "Tolerans dışı", "high": "Yüksek", "medium": "Önemli / orta", "low": "Olası / düşük", "insignificant": "Önemsiz"]
}

/// V6 risk analysis and emergency plan wizard: one question per page. Answers live in RDBridge; this view only sends actions.
/// `mode: "emergency"` runs the Acil Durum Planı flow on the same answers; its pages live in NovaEmergencyWizardViews.swift.
/// `mode: "checklist"` builds a Kontrol Listesi (rd-checklist.js); its pages live in NovaChecklistWizardViews.swift.
struct NovaRiskWizardScreen: View {
    var mode = "risk"
    let companiesSource: () async throws -> [NovaAnalysisCompanyOption]
    let workplacesSource: (UUID) async throws -> [NovaWizardWorkplace]
    /// Risk mode files the Excel draft here; the other modes save through their own module.
    let files: NovaFileLibraryClient?
    var initialCompany: UUID?
    /// Emergency mode only: lists company personnel and saves the plan as a module record.
    var emergencyClient: NovaEmergencyClient? = nil
    /// Checklist mode only: publishes the list to Listelerim, then hands a run over to the start flow.
    var checklistClient: NovaChecklistClient? = nil
    var onChecklistStart: ((String) -> Void)? = nil
    let onBack: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.novaCanvasStyle) private var canvasStyle
    @State private var runtime: NovaRiskWizardRuntime?
    @State private var view: NovaRiskWizardView?
    @State private var result: NovaRiskWizardResult?
    @State private var plan: NovaEmergencyWizardPlan?
    @State private var planSaved = false
    @State private var checklistList: NovaChecklistWizardList?
    @State private var savedLists: [String] = []
    @State private var step = "firm"
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var workplaces: [NovaWizardWorkplace] = []
    @State private var company: UUID?
    @State private var workplace: UUID?
    @State private var query = ""
    @State private var sectorHits: [NovaRiskWizardSectorHit] = []
    @State private var searchHits: [NovaRiskWizardView.Pick] = []
    @State private var expanded: Set<String> = []
    @State private var filter = "all"
    @State private var scoreView = "fk"
    @State private var message: String?
    @State private var busy = false
    @State private var archivedName: String?
    @State private var exportFile = NovaRiskWizardFile(data: Data())
    @State private var exportName = "Risk_Degerlendirmesi.xlsx"
    @State private var exporting = false

    private static let titles = ["firm": "İşyeri", "sector": "Faaliyet", "areas": "Çalışma alanları", "equipment": "Ekipmanlar",
        "materials": "Maddeler", "tasks": "İşler", "cond": "Çalışma koşulları", "mgmt": "Genel konular", "method": "Yöntem",
        "cols": "Tablo sütunları", "summary": "Özet", "result": "Analiz"]

    var body: some View {
        NovaPageSurface(onEdgeBack: back) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    NovaPageHeading(title: view?.emergency?.text("title") ?? view?.checklist?.text("title") ?? RDLocalization.string("localizable.nova.risk.wizard.screen.risk.analizi.sihirbazi.2b3e1d43", table: .localizable, fallback: "Risk Analizi Sihirbazı"), subtitle: stepLabel, onBack: back)
                    progress
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let view { page(view).id("top") }
                            else if message == nil { ProgressView().frame(maxWidth: .infinity).padding(.top, 40) }
                            if let message { NovaHelpHint(text: message) }
                        }
                        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 120 + novaTabBarInset)
                        .disabled(busy)
                    }
                    .onChange(of: step) { _ in scroll.scrollTo("top", anchor: .top) }
                }
            }
            .overlay(alignment: .bottom) { if view != nil { footer } }
        }
        .task { await load() }
        .task(id: company) { await loadWorkplaces() }
        .fileExporter(isPresented: $exporting, document: exportFile,
            contentType: UTType(filenameExtension: (exportName as NSString).pathExtension) ?? .data,
            defaultFilename: exportName) { outcome in
                if case .failure = outcome { message = "Dosya kaydedilemedi. Tekrar deneyebilirsiniz." }
                exportFile = .init(data: Data())
            }
    }

    // MARK: Navigation

    private var steps: [String] { (view?.steps ?? ["firm"]) + ["result"] }
    private var stepIndex: Int { steps.firstIndex(of: step) ?? 0 }
    private var stepLabel: String {
        if let checklist = view?.checklist {
            if step == "result" { return checklist.text("step.result") + " · \(checklistList?.total ?? 0)" }
            let title = checklist.text("step." + (step.hasPrefix("fu:") ? "fu" : step))
            return "\(stepIndex + 1) / \(steps.count - 1)" + (title.isEmpty ? "" : " · " + title)
        }
        if let emergency = view?.emergency {
            if step == "result" { return emergency.text("step.result") + " · \(plan?.cards.count ?? 0)" }
            let title = step.hasPrefix("fu:") ? emergency.text("step.fu") : (emergency.texts["step." + step] ?? Self.titles[step] ?? "")
            return "\(stepIndex + 1) / \(steps.count - 1)" + (title.isEmpty ? "" : " · " + title)
        }
        if step == "result" { return RDLocalization.format("localizable.nova.risk.wizard.screen.analiz.1.madde.e620ebd5", table: .localizable, fallback: "Analiz · %1$@ madde", arguments: [String(describing: result?.total ?? 0)]) }
        let title = step.hasPrefix("fu:") ? "Takip sorusu" : (Self.titles[step] ?? "")
        return RDLocalization.format("localizable.nova.risk.wizard.screen.adim.1.2.3.f671c204", table: .localizable, fallback: "Adım %1$@ / %2$@ · %3$@", arguments: [String(describing: stepIndex + 1), String(describing: steps.count - 1), String(describing: title)])
    }
    private var progress: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(NovaColorToken.surfaceMuted.color(in: scheme))
                Capsule().fill(NovaColorToken.accent.color(in: scheme))
                    .frame(width: geometry.size.width * CGFloat(stepIndex + 1) / CGFloat(max(steps.count, 1)))
            }
        }.frame(height: 4).animation(.easeOut(duration: 0.25), value: stepIndex)
    }
    private var footer: some View {
        HStack(spacing: 10) {
            if step != "firm" {
                NovaButton(label: "Geri", symbol: "chevron.left", variant: .surface, compact: true) { back() }
                    .frame(width: 110)
            }
            if step == "result", let checklist = view?.checklist {
                NovaButton(label: checklist.text("result.download"), symbol: "arrow.down.doc", isEnabled: !busy && (checklistList?.total ?? 0) > 0) { export("docx") }
                    .accessibilityIdentifier("checklistWizard.download")
            } else if step == "result", let emergency = view?.emergency {
                NovaButton(label: emergency.text("result.download"), symbol: "arrow.down.doc", isEnabled: !busy) { export("docx") }
                    .accessibilityIdentifier("emergencyWizard.download")
            } else if step == "result" {
                NovaButton(label: RDLocalization.string("localizable.nova.risk.wizard.screen.excel.indir.3c929860", table: .localizable, fallback: "Excel indir"), symbol: "arrow.down.doc", isEnabled: !busy) { export("xlsx") }
                    .accessibilityIdentifier("riskWizard.excel")
            } else {
                NovaButton(label: nextLabel, symbol: step == "summary" ? "sparkles" : "chevron.right",
                           isEnabled: !busy && !(step == "sector" && (view?.sectors.isEmpty ?? true))
                               && !(step == "summary" && view?.checklist?.itemCount == 0)) { next() }
                    .accessibilityIdentifier("riskWizard.next")
            }
        }
        .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 10 + novaTabBarInset)
        .background(alignment: .top) {
            canvasStyle.color(in: scheme).ignoresSafeArea()
                .overlay(alignment: .top) { Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1) }
        }
    }
    private var nextLabel: String {
        if let checklist = view?.checklist {
            if step == "summary" { return checklist.text("next.summary") }
            if step.hasPrefix("fu:"), let followup = currentFollowup, !followup.options.contains(where: \.selected) { return checklist.text("next.skip") }
            return checklist.text("next")
        }
        if let emergency = view?.emergency, step == "summary" || !step.hasPrefix("fu:") {
            return emergency.text(step == "summary" ? "next.summary" : "next")
        }
        if step == "summary" { return RDLocalization.string("localizable.nova.risk.wizard.screen.analizi.olustur.13eacc1a", table: .localizable, fallback: "Analizi oluştur") }
        if step.hasPrefix("fu:"), let followup = currentFollowup, !followup.options.contains(where: \.selected) { return "Atla" }
        return RDLocalization.string("localizable.nova.risk.wizard.screen.devam.a94a296d", table: .localizable, fallback: "Devam")
    }
    private func back() {
        guard stepIndex > 0 else { onBack(); return }
        go(steps[stepIndex - 1])
    }
    private func next() {
        guard stepIndex + 1 < steps.count else { return }
        go(steps[stepIndex + 1])
    }
    private func go(_ target: String) {
        query = ""; searchHits = []; message = nil
        if target == "areas" { perform(["type": "enter", "step": "areas"]) }
        if target == "sector" { sectorHits = (try? runtime?.sectors("")) ?? [] }
        if target == "result" { reloadResult() }
        withAnimation(.easeOut(duration: 0.2)) { step = target }
    }
    private var currentFollowup: NovaRiskWizardView.Followup? {
        step.hasPrefix("fu:") ? view?.followups.first { "fu:" + $0.id == step } : nil
    }

    // MARK: Bridge

    private func load() async {
        do {
            let loaded = try NovaRiskWizardRuntime()
            runtime = loaded
            view = try loaded.start(firmName: "", date: Date().formatted(.dateTime.day(.twoDigits).month(.twoDigits).year()), mode: mode)
        } catch { message = error.localizedDescription }
        do {
            companies = try await companiesSource()
            if let initialCompany, companies.contains(where: { $0.id == initialCompany }) { selectCompany(initialCompany) }
        } catch { companies = [] }
    }
    private func loadWorkplaces() async {
        workplace = nil; workplaces = []
        guard let selected = company else { return }
        if let answer = try? await workplacesSource(selected), company == selected { workplaces = answer }
    }
    private func selectCompany(_ id: UUID?) {
        company = id
        if let name = companies.first(where: { $0.id == id })?.name { perform(["type": "firm", "field": "name", "value": name]) }
    }
    private func perform(_ action: [String: Any]) {
        guard let runtime else { return }
        do {
            view = try runtime.act(action)
            // A changed checklist is a new list; saving it again is allowed.
            if view?.checklist != nil { savedLists = [] }
            if step == "result" { reloadResult() }
        } catch { message = error.localizedDescription }
    }
    private func reloadResult() {
        if view?.checklist != nil {
            do { checklistList = try runtime?.checklistList() } catch { message = error.localizedDescription }
            return
        }
        if view?.emergency != nil {
            do { plan = try runtime?.plan() } catch { message = error.localizedDescription }
            return
        }
        do {
            let next = try runtime?.result()
            // The first finished draft is the use "Senin İçin" stops suggesting.
            if result == nil, next != nil { NovaForYouOutbox.recordUse("risk_wizard") }
            result = next
        } catch { message = error.localizedDescription }
    }

    // MARK: Pages

    @ViewBuilder private func page(_ v: NovaRiskWizardView) -> some View {
        switch step {
        case "firm": firmPage(v)
        case "sector": sectorPage(v)
        case "areas": picksPage(v, kind: "areas", title: RDLocalization.string("localizable.nova.risk.wizard.screen.hangi.alanlarda.calisiliyor.528aec74", table: .localizable, fallback: "Hangi alanlarda çalışılıyor?"), help: "Faaliyetinize göre önerilen alanlar seçili geldi; olmayanları kaldırın.")
        case "equipment": picksPage(v, kind: "equipment", title: RDLocalization.string("localizable.nova.risk.wizard.screen.hangi.ekipman.ve.makineler.kullaniliyor.74cf1aed", table: .localizable, fallback: "Hangi ekipman ve makineler kullanılıyor?"), help: "Yalnız işyerinde gerçekten kullanılanları seçin. Her ekipman kendi risklerini ekler.")
        case "materials": picksPage(v, kind: "materials", title: RDLocalization.string("localizable.nova.risk.wizard.screen.hangi.kimyasal.ve.malzemelerle.calisiliyor.2a17eeca", table: .localizable, fallback: "Hangi kimyasal ve malzemelerle çalışılıyor?"), help: "Yakıtlar, gazlar, tozlar ve süreçte açığa çıkan maddeler dahil.")
        case "tasks": picksPage(v, kind: "tasks", title: RDLocalization.string("localizable.nova.risk.wizard.screen.hangi.isler.yapiliyor.7107e89e", table: .localizable, fallback: "Hangi işler yapılıyor?"), help: "Rutin ve periyodik işleri seçin; bakım, temizlik ve ikmal gibi işler de riski değiştirir.")
        case "cond": listPage(title: RDLocalization.string("localizable.nova.risk.wizard.screen.hangi.kosullar.gecerli.ba4c345b", table: .localizable, fallback: "Hangi koşullar geçerli?"), help: "Özel politika gerektiren çalışan grupları ve çalışma düzeni ilgili maddeleri ekler.",
                              items: v.conditions) { perform(["type": "cond", "id": $0]) }
        case "mgmt": managementPage(v)
        case "method": methodPage(v)
        case "cols": columnsPage(v)
        case "purpose", "topics", "items": checklistPage(v)
        case "site", "cards", "team", "fields": emergencyPage(v)
        case "summary": if v.checklist != nil { checklistPage(v) } else if v.emergency != nil { emergencyPage(v) } else { summaryPage(v) }
        case "result": if v.checklist != nil { checklistResult } else if v.emergency != nil { emergencyResult } else { resultPage }
        default: if let followup = currentFollowup { followupPage(followup) }
        }
    }

    private func title(_ text: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: text, style: .sheetTitle)
            if !help.isEmpty { NovaText(text: help, style: .meta, color: NovaColorToken.textSecondary.color(in: scheme)) }
        }.padding(.bottom, 4)
    }

    private func firmPage(_ v: NovaRiskWizardView) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let emergency = v.emergency { title(emergency.text("firm.title"), emergency.text("firm.help")) }
            else if let checklist = v.checklist { title(checklist.text("firm.title"), checklist.text("firm.help")) }
            else { title("Analiz hangi işyeri için?", "İsteğe bağlı; rapor kapağında ve dosya adında kullanılır. Çalışan sayısı kurul ve temsilci gibi genel konuları etkiler.") }
            if !companies.isEmpty {
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: "Firma", style: .label).frame(maxWidth: .infinity, alignment: .leading)
                        Picker("Firma", selection: Binding(get: { company }, set: { selectCompany($0) })) {
                            Text(RDLocalization.string("localizable.nova.risk.wizard.screen.firma.secmeden.devam.et.52b96f77", table: .localizable, fallback: "Firma seçmeden devam et")).tag(nil as UUID?)
                            ForEach(companies) { Text($0.name).tag(Optional($0.id)) }
                        }.pickerStyle(.menu).accessibilityIdentifier("riskWizard.company")
                        if !workplaces.isEmpty {
                            Picker(RDLocalization.string("localizable.nova.risk.wizard.screen.isyeri.e5eb159e", table: .localizable, fallback: "İşyeri"), selection: $workplace) {
                                Text(RDLocalization.string("localizable.nova.risk.wizard.screen.isyeri.secmeden.devam.et.d526e82c", table: .localizable, fallback: "İşyeri seçmeden devam et")).tag(nil as UUID?)
                                ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                            }.pickerStyle(.menu)
                        }
                    }
                }
            }
            field(RDLocalization.string("localizable.nova.risk.wizard.screen.firma.isyeri.adi.a8f12086", table: .localizable, fallback: "Firma / işyeri adı"), value: v.firm.name, placeholder: RDLocalization.string("localizable.nova.risk.wizard.screen.orn.yildiz.sondaj.ltd.8f11f81e", table: .localizable, fallback: "Örn. Yıldız Sondaj Ltd."), key: "name")
            field(RDLocalization.string("localizable.nova.risk.wizard.screen.adres.b7778653", table: .localizable, fallback: "Adres"), value: v.firm.address, placeholder: RDLocalization.string("localizable.nova.risk.wizard.screen.ilce.il.0c60db8b", table: .localizable, fallback: "İlçe / il"), key: "address")
            if let emergency = v.emergency {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: emergency.text("firm.employees"), style: .label)
                    TextField(emergency.text("firm.employeesPlaceholder"), text: Binding(get: { emergency.employees.map { String($0) } ?? "" },
                                                                                        set: { perform(["type": "emp", "value": $0]) }))
                        .keyboardType(.numberPad).font(NovaFont.font(.body))
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("emergencyWizard.employees")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.calisan.sayisi.edbcee10", table: .localizable, fallback: "Çalışan sayısı"), style: .label)
                    chips([("1-9", "1–9"), ("10-49", "10–49"), ("50-249", "50–249"), ("250+", "250+")], selected: v.firm.employees) {
                        perform(["type": "firm", "field": "employees", "value": $0])
                    }
                }
            }
            field(v.emergency?.text("firm.date") ?? v.checklist?.text("firm.date") ?? RDLocalization.string("localizable.nova.risk.wizard.screen.degerlendirme.tarihi.36ecad58", table: .localizable, fallback: "Değerlendirme tarihi"), value: v.firm.date, placeholder: "gg.aa.yyyy", key: "date")
        }
    }
    private func field(_ label: String, value: String, placeholder: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: label, style: .label)
            TextField(placeholder, text: Binding(get: { value }, set: { perform(["type": "firm", "field": key, "value": $0]) }))
                .font(NovaFont.font(.body))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func sectorPage(_ v: NovaRiskWizardView) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title("İşyerinin ana faaliyeti nedir?", "Faaliyet adını, bilinen adıyla ya da NACE kodunu yazın. İlk seçtiğiniz ana faaliyet sayılır.")
            if !v.sectors.isEmpty {
                FlowChips(items: v.sectors.enumerated().map { index, s in (s.id, (index == 0 ? "Ana: " : "") + s.title) }, selected: Set(v.sectors.map(\.id)),
                          trailingSymbol: "xmark") { perform(["type": "sector", "id": $0]) }
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.tehlike.sinifi.59ac915c", table: .localizable, fallback: "Tehlike sınıfı"), style: .label).frame(maxWidth: .infinity, alignment: .leading)
                        NovaText(text: v.hazardClassManual ? "Elle seçildi" : "Faaliyete göre önerildi; firmanın NACE koduyla doğrulayın",
                                 style: .metaQuiet)
                        chips([("low", "Az tehlikeli"), ("medium", "Tehlikeli"), ("high", "Çok tehlikeli")], selected: v.hazardClass ?? "") {
                            perform(["type": "hc", "id": $0])
                        }
                    }
                }
            }
            NovaAnalysisSearchField(text: $query, placeholder: RDLocalization.string("localizable.nova.risk.wizard.screen.orn.su.sondaji.akaryakit.47.30.9caf04b4", table: .localizable, fallback: "Örn. su sondajı, akaryakıt, 47.30"), identifier: "riskWizard.sectorSearch")
                .onChange(of: query) { value in sectorHits = (try? runtime?.sectors(value)) ?? [] }
            NovaText(text: query.count < 2 ? "Sık seçilenler" : "\(sectorHits.count) sonuç", style: .overline)
            ForEach(sectorHits) { hit in
                optionRow(title: hit.title, subtitle: hit.subtitle, tags: [], badges: hit.hazardClassLabel.isEmpty ? [] : [hit.hazardClassLabel],
                          selected: v.sectors.contains { $0.id == hit.id }, single: false) {
                    perform(["type": "sector", "id": hit.id])
                    if !v.sectors.contains(where: { $0.id == hit.id }) { query = "" }
                    sectorHits = (try? runtime?.sectors(query)) ?? []
                }
            }
            if query.count >= 2 && sectorHits.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.bu.aramayla.faaliyet.bulunamadi.daha.genel.bir.k.811d0e95", table: .localizable, fallback: "Bu aramayla faaliyet bulunamadı. Daha genel bir kelime deneyin (ör. inşaat, depo, sondaj)."), style: .metaQuiet)
            }
        }
    }

    private func followupPage(_ f: NovaRiskWizardView.Followup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: f.context.uppercased(with: Locale(identifier: "tr_TR")), style: .overline)
            title(f.question, f.help)
            ForEach(f.options) { option in
                optionRow(title: option.title, subtitle: "", tags: [], badges: option.badges, selected: option.selected, single: !f.multi) {
                    perform(["type": "fu", "fid": f.id, "id": option.id])
                }
            }
        }
    }

    private func picksPage(_ v: NovaRiskWizardView, kind: String, title text: String, help: String) -> some View {
        let picks = v.picks[kind]
        return VStack(alignment: .leading, spacing: 10) {
            title(text, help)
            HStack {
                NovaText(text: RDLocalization.format("localizable.nova.risk.wizard.screen.onerilenler.1.e223bcd6", table: .localizable, fallback: "Önerilenler · %1$@", arguments: [String(describing: picks?.suggested.count ?? 0)]), style: .overline)
                Spacer()
                if !(picks?.suggested.isEmpty ?? true) {
                    Button(picks?.allSelected == true ? "Seçimi kaldır" : "Tümünü seç") { perform(["type": "all", "kind": kind]) }
                        .font(NovaFont.font(.label)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                }
            }
            if picks?.suggested.isEmpty ?? true {
                NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.bu.faaliyet.icin.hazir.oneri.yok.asagidan.arayar.74720492", table: .localizable, fallback: "Bu faaliyet için hazır öneri yok. Aşağıdan arayarak ekleyebilirsiniz."), style: .metaQuiet)
            }
            ForEach(picks?.suggested ?? []) { pickRow(kind, $0) }
            if let added = picks?.added, !added.isEmpty {
                NovaText(text: RDLocalization.format("localizable.nova.risk.wizard.screen.eklediginiz.1.6102f1aa", table: .localizable, fallback: "Eklediğiniz · %1$@", arguments: [String(describing: added.count)]), style: .overline).padding(.top, 8)
                ForEach(added) { pickRow(kind, $0) }
            }
            if let generic = picks?.generic, !generic.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.diger.genel.alanlar.0706d16d", table: .localizable, fallback: "Diğer genel alanlar"), style: .overline).padding(.top, 8)
                ForEach(generic) { pickRow(kind, $0) }
            }
            NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.baska.ekle.d35d84c8", table: .localizable, fallback: "Başka ekle"), style: .overline).padding(.top, 8)
            NovaAnalysisSearchField(text: $query, placeholder: RDLocalization.string("localizable.nova.risk.wizard.screen.listede.yoksa.arayin.cb5098f7", table: .localizable, fallback: "Listede yoksa arayın"), identifier: "riskWizard.search.\(kind)")
                .onChange(of: query) { value in searchHits = (try? runtime?.search(kind, value)) ?? [] }
            ForEach(searchHits) { hit in
                pickRow(kind, hit, afterTap: { searchHits = (try? runtime?.search(kind, query)) ?? [] })
            }
        }
    }
    private func pickRow(_ kind: String, _ pick: NovaRiskWizardView.Pick, afterTap: (() -> Void)? = nil) -> some View {
        optionRow(title: pick.title, subtitle: [pick.subtitle, pick.detail].filter { !$0.isEmpty }.joined(separator: "\n"),
                  tags: pick.reasons, badges: pick.badges, selected: pick.selected, single: false) {
            perform(["type": "pick", "kind": kind, "id": pick.id]); afterTap?()
        }
    }

    private func listPage(title text: String, help: String, items: [NovaRiskWizardView.Item], toggle: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title(text, help)
            ForEach(items) { item in
                optionRow(title: item.title, subtitle: item.subtitle ?? "", tags: [], badges: [], selected: item.selected, single: false) { toggle(item.id) }
            }
        }
    }
    private func managementPage(_ v: NovaRiskWizardView) -> some View {
        let on = v.management.filter(\.selected).count
        return VStack(alignment: .leading, spacing: 10) {
            title("Yönetim ve yasal yükümlülükler", "Eğitim, sağlık gözetimi, acil durum, KKD ve periyodik kontroller her işyerinde değerlendirilir. Uygulanmayanları kapatın.")
            HStack {
                NovaText(text: RDLocalization.format("localizable.nova.risk.wizard.screen.1.2.konu.acik.c640c007", table: .localizable, fallback: "%1$@ / %2$@ konu açık", arguments: [String(describing: on), String(describing: v.management.count)]), style: .overline)
                Spacer()
                Button(on == v.management.count ? "Tümünü kapat" : "Tümünü aç") { perform(["type": "mgAll"]) }
                    .font(NovaFont.font(.label)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
            }
            ForEach(v.management) { item in
                optionRow(title: item.title, subtitle: item.subtitle ?? "", tags: [], badges: [], selected: item.selected, single: false) {
                    perform(["type": "mg", "id": item.id])
                }
            }
        }
    }
    private func methodPage(_ v: NovaRiskWizardView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title("Risk hangi yöntemle skorlansın?", "İki yöntem de her zaman hesaplanır; burada raporda hangisinin gösterileceğini seçersiniz.")
            ForEach([("both", "Fine-Kinney ve 5×5 birlikte", "Önerilen · Denetimlerde en çok istenen biçim"),
                     ("fk", "Yalnız Fine-Kinney", "R = O × F × Ş · beş seviye"),
                     ("m5", "Yalnız 5×5 (L tipi matris)", "R = O × Ş · 1–25")], id: \.0) { item in
                optionRow(title: item.1, subtitle: item.2, tags: [], badges: [], selected: v.method == item.0, single: true) {
                    perform(["type": "method", "id": item.0])
                }
            }
            NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.wizard.screen.katalog.her.madde.icin.tipik.saha.kosulunda.olas.95c1c4f4", table: .localizable, fallback: "Katalog her madde için tipik saha koşulunda olasılık, frekans ve şiddet önerir. 5×5 olasılığı Fine-Kinney O × F çarpımından türetilir. Önlem sonrası skor, önerilen önlemlerin tamamı uygulandığında beklenen değerdir. Sonuç ekranında her satırı düzenleyebilirsiniz."))
        }
    }
    private func columnsPage(_ v: NovaRiskWizardView) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title("Tabloda hangi sütunlar olsun?", "Hazır bir düzen seçin ya da sütunları tek tek açıp kapatın. Zorunlu sütunlar kapatılamaz.")
            chips([("standard", "Standart"), ("compact", "Kompakt"), ("full", "Denetim için tam")], selected: v.preset) { perform(["type": "preset", "id": $0]) }
            ForEach(v.columns) { column in
                optionRow(title: column.title, subtitle: column.required ? "Zorunlu" : (column.residual ? "Önlem sonrası" : ""), tags: [], badges: [],
                          selected: column.selected, single: false) {
                    if !column.required { perform(["type": "col", "id": column.id]) }
                }
            }
        }
    }
    private func summaryPage(_ v: NovaRiskWizardView) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            title("\(v.rowCount) risk maddesiyle analiz hazır", "Seçimlerinizi kontrol edin. Analizi oluşturduktan sonra satırları düzenleyebilir, çıkarabilir ve indirebilirsiniz.")
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    summaryLine("İşyeri", v.firm.name.isEmpty ? "—" : v.firm.name, "firm")
                    summaryLine("Faaliyet", v.sectors.map(\.title).joined(separator: ", ") + (v.hazardClassLabel.isEmpty ? "" : " · " + v.hazardClassLabel), "sector")
                    summaryLine("Alanlar", "\(v.picks["areas"]?.count ?? 0) seçili", "areas")
                    summaryLine("Ekipmanlar", "\(v.picks["equipment"]?.count ?? 0) seçili", "equipment")
                    summaryLine("Maddeler", "\(v.picks["materials"]?.count ?? 0) seçili", "materials")
                    summaryLine("İşler", "\(v.picks["tasks"]?.count ?? 0) seçili", "tasks")
                    summaryLine("Genel konular", "\(v.management.filter(\.selected).count) konu", "mgmt")
                    summaryLine("Yöntem", ["both": "Fine-Kinney ve 5×5", "fk": "Fine-Kinney", "m5": "5×5"][v.method] ?? v.method, "method")
                }
            }
            NovaCard(padding: 14) { distribution(title: RDLocalization.string("localizable.nova.risk.wizard.screen.onerilen.skorlara.gore.fine.kinney.5c65684f", table: .localizable, fallback: "Önerilen skorlara göre · Fine-Kinney"), sets: [("Mevcut", v.counts["fk"] ?? [:])]) }
        }
    }
    private func summaryLine(_ label: String, _ value: String, _ target: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: label, style: .metaQuiet)
                NovaText(text: value, style: .body)
            }
            Spacer()
            Button(RDLocalization.string("localizable.nova.risk.wizard.screen.duzenle.da36b4c7", table: .localizable, fallback: "Düzenle")) { go(target) }.font(NovaFont.font(.label)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
        }
    }

    // MARK: Emergency plan

    @ViewBuilder private func emergencyPage(_ v: NovaRiskWizardView) -> some View {
        if let emergency = v.emergency {
            NovaEmergencyWizardPage(step: step, view: v, emergency: emergency, runtime: runtime,
                                    staffSource: staffSource, perform: perform, go: go)
        }
    }
    private var staffSource: (() async throws -> [NovaEmergencyWizardStaff])? {
        guard let client = emergencyClient, let company else { return nil }
        return {
            let catalogue = try? await client.catalogue(company)
            let support = Set((catalogue?.supportStaff ?? []).map(\.fullName))
            let page = try await client.employees(company, "", nil)
            return page.rows.filter { !$0.isArchived }.map {
                NovaEmergencyWizardStaff(id: $0.id, name: $0.name, detail: [$0.jobTitle, $0.departmentName].compactMap { $0 }.joined(separator: " · "),
                                         isSupportStaff: support.contains($0.name))
            }.sorted { ($0.isSupportStaff ? 0 : 1, $0.name) < ($1.isSupportStaff ? 0 : 1, $1.name) }
        }
    }
    @ViewBuilder private var emergencyResult: some View {
        if let plan, let emergency = view?.emergency {
            NovaEmergencyWizardResultView(plan: plan, emergency: emergency, busy: busy, canSave: emergencyClient != nil && company != nil,
                                          saved: planSaved, export: export) { Task { await savePlan() } }
        } else { ProgressView().frame(maxWidth: .infinity) }
    }
    private func savePlan() async {
        guard let runtime, let client = emergencyClient, let company, let emergency = view?.emergency, !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await NovaEmergencyWizardSaver.save(runtime: runtime, client: client, company: company, workplace: workplace, texts: emergency)
            planSaved = true
            message = emergency.text("result.saved")
        } catch let error as NovaEmergencyFailure { message = error.message }
        catch let error as NovaFileFailure { message = NovaFileScreenWords.failure(error) }
        catch { message = error.localizedDescription }
    }

    // MARK: Checklist

    @ViewBuilder private func checklistPage(_ v: NovaRiskWizardView) -> some View {
        if let checklist = v.checklist {
            NovaChecklistWizardPage(step: step, view: v, checklist: checklist, runtime: runtime, perform: perform, go: go)
        }
    }
    @ViewBuilder private var checklistResult: some View {
        if let checklistList, let checklist = view?.checklist {
            NovaChecklistWizardResultView(list: checklistList, checklist: checklist, busy: busy, canSave: checklistClient != nil,
                                          saved: savedLists, export: export, save: { Task { await saveChecklist() } }, start: onChecklistStart)
        } else { ProgressView().frame(maxWidth: .infinity) }
    }
    private func saveChecklist() async {
        guard let runtime, let client = checklistClient, let checklist = view?.checklist, !busy, savedLists.isEmpty else { return }
        busy = true; defer { busy = false }
        do {
            let codes = try await NovaChecklistWizardSaver.save(runtime: runtime, client: client, company: company)
            savedLists = codes
            message = codes.count > 1 ? "\(codes.count) " + checklist.text("result.savedMany") : checklist.text("result.saved")
        } catch let error as NovaChecklistFailure { message = error.message }
        catch { message = NovaChecklistFailure.unavailable.message }
    }

    // MARK: Result

    @ViewBuilder private var resultPage: some View {
        if let result {
            let showFK = result.method != "m5", showM5 = result.method != "fk"
            VStack(alignment: .leading, spacing: 12) {
                title(view?.firm.name.isEmpty == false ? view!.firm.name : "Risk değerlendirmesi",
                      "\(view?.sectors.map(\.title).joined(separator: ", ") ?? "") · \(result.total) madde" + (result.removedCount > 0 ? " · \(result.removedCount) çıkarıldı" : ""))
                if showFK { NovaCard(padding: 14) { distribution(title: "Fine-Kinney", sets: [("Mevcut", result.counts["fk"] ?? [:]), ("Önlem sonrası", result.counts["rfk"] ?? [:])]) } }
                if showM5 { NovaCard(padding: 14) { distribution(title: RDLocalization.string("localizable.nova.risk.wizard.screen.5.5.matris.fdf14b1a", table: .localizable, fallback: "5×5 matris"), sets: [("Mevcut", result.counts["m5"] ?? [:]), ("Önlem sonrası", result.counts["rm5"] ?? [:])]) } }
                HStack(spacing: 8) {
                    NovaButton(label: "Word", symbol: "doc.text", variant: .surface, isEnabled: !busy, compact: true) { export("docx") }
                    NovaButton(label: "PDF", symbol: "doc.richtext", variant: .surface, isEnabled: !busy, compact: true) { export("pdf") }
                    NovaButton(label: archivedName == nil ? "Arşive ekle" : "Arşivde", symbol: "folder.badge.plus", variant: .surface,
                               isEnabled: !busy && archivedName == nil, compact: true) { Task { await archive() } }
                }
                if result.method == "both" { chips([("fk", "Fine-Kinney"), ("m5", "5×5")], selected: scoreView) { scoreView = $0 } }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("all", "Tümü"), ("critical", "Tolerans dışı"), ("high", "Yüksek"), ("medium", "Önemli / orta"), ("low", "Olası / düşük"), ("removed", "Çıkarılan")], id: \.0) { item in
                            chip(item.1, selected: filter == item.0) { filter = item.0 }
                        }
                    }
                }
                let rows = result.rows.filter(matches)
                if rows.isEmpty { NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.bu.filtrede.madde.yok.4f70d853", table: .localizable, fallback: "Bu filtrede madde yok."), style: .metaQuiet) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index == 0 || rows[index - 1].section != row.section {
                        NovaText(text: row.section, style: .cardTitle).padding(.top, 10)
                    }
                    resultRow(row, showFK: showFK && (result.method != "both" || scoreView == "fk"), showM5: showM5 && (result.method != "both" || scoreView == "m5"))
                }
                NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.wizard.screen.skorlar.katalog.onerisidir.degerlendirme.ekibi.s.45d25ddb", table: .localizable, fallback: "Skorlar katalog önerisidir; değerlendirme ekibi sahada doğrulamalı ve gerektiğinde düzenlemelidir."))
            }
        } else { ProgressView().frame(maxWidth: .infinity) }
    }
    private func matches(_ row: NovaRiskWizardResult.Row) -> Bool {
        switch filter {
        case "all": return true
        case "removed": return row.removed
        default:
            let level = (result?.method == "m5" || (result?.method == "both" && scoreView == "m5")) ? row.m5.level : row.fk.level
            return !row.removed && level == filter
        }
    }
    private func resultRow(_ row: NovaRiskWizardResult.Row, showFK: Bool, showM5: Bool) -> some View {
        let open = expanded.contains(row.id)
        return NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { if open { expanded.remove(row.id) } else { expanded.insert(row.id) } }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        NovaText(text: row.removed ? "—" : "\(row.number)", style: .metaQuiet).frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: row.hazard, style: .bodyStrong)
                            NovaText(text: row.risk, style: .meta)
                            if showFK { scorePair("FK", row.fk, row.rfk) }
                            if showM5 || open { scorePair("5×5", row.m5, row.rm5) }
                            HStack(spacing: 6) {
                                if row.isNew { tag("Yeni", tone: "low") }
                                if row.edited { tag("Düzenlendi", tone: "info") }
                                if row.severe { tag("Ağır sonuç", tone: "high") }
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("riskWizard.row.\(row.id)")
                if open { rowDetail(row) }
            }
        }.opacity(row.removed ? 0.55 : 1)
    }
    private func rowDetail(_ row: NovaRiskWizardResult.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !row.check.isEmpty { NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.wizard.screen.sahada.kontrol.4ba7763b", table: .localizable, fallback: "Sahada kontrol: ") + row.check) }
            detailLine("Olası sonuç", row.consequence)
            if !row.affected.isEmpty { detailLine("Etkilenenler", row.affected) }
            detailLine("Neden geldi", row.reasons.joined(separator: " · "))
            if !row.owner.isEmpty { detailLine("Sorumlu", row.owner) }
            if !row.legal.isEmpty { detailLine("Mevzuat", row.legal.joined(separator: " · ")) }
            NovaText(text: RDLocalization.string("localizable.nova.risk.wizard.screen.alinacak.onlemler.4b1d48d8", table: .localizable, fallback: "Alınacak önlemler"), style: .label)
            ForEach(Array(row.controls.enumerated()), id: \.offset) { _, control in
                HStack(alignment: .top, spacing: 8) {
                    tag(control.label, tone: control.hierarchy == "ppe" ? "high" : control.hierarchy == "administrative" ? "neutral" : control.hierarchy == "engineering" ? "info" : "low")
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: control.text, style: .body)
                        if !control.owner.isEmpty { NovaText(text: control.owner, style: .metaQuiet) }
                    }
                }
            }
            fkEditor("Fine-Kinney · mevcut", key: "fk", score: row.fk, row: row)
            fkEditor("Fine-Kinney · önlem sonrası", key: "rfk", score: row.rfk, row: row)
            m5Editor("5×5 · mevcut", key: "m5", score: row.m5, manual: row.m5Manual, row: row)
            m5Editor("5×5 · önlem sonrası", key: "rm5", score: row.rm5, manual: row.rm5Manual, row: row)
            HStack(spacing: 8) {
                NovaButton(label: row.removed ? "Geri al" : "Analizden çıkar", symbol: row.removed ? "arrow.uturn.backward" : "trash", variant: .surface, compact: true) {
                    perform(["type": row.removed ? "restore" : "remove", "id": row.id])
                }
                if row.edited {
                    NovaButton(label: RDLocalization.string("localizable.nova.risk.wizard.screen.onerilen.skora.don.35a5bb7c", table: .localizable, fallback: "Önerilen skora dön"), symbol: "arrow.counterclockwise", variant: .surface, compact: true) { perform(["type": "reset", "id": row.id]) }
                }
            }
        }
    }
    private func detailLine(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            NovaText(text: label, style: .metaQuiet)
            NovaText(text: value, style: .body)
        }
    }
    private func fkEditor(_ label: String, key: String, score: NovaRiskWizardResult.Score, row: NovaRiskWizardResult.Row) -> some View {
        editorBox(label, score: score, note: nil) {
            factorMenu("O", values: [0.2, 0.5, 1, 3, 6, 10], current: score.p ?? 0) { perform(["type": "edit", "id": row.id, "key": key, "field": "p", "value": $0]) }
            factorMenu("F", values: [0.5, 1, 2, 3, 6, 10], current: score.f ?? 0) { perform(["type": "edit", "id": row.id, "key": key, "field": "f", "value": $0]) }
            factorMenu("Ş", values: [1, 3, 7, 15, 40, 100], current: score.s) { perform(["type": "edit", "id": row.id, "key": key, "field": "s", "value": $0]) }
        }
    }
    private func m5Editor(_ label: String, key: String, score: NovaRiskWizardResult.Score, manual: Bool, row: NovaRiskWizardResult.Row) -> some View {
        editorBox(label, score: score, note: manual ? "Elle girildi" : "FK’dan türetildi") {
            factorMenu("O", values: [1, 2, 3, 4, 5], current: score.l ?? 0) { perform(["type": "edit", "id": row.id, "key": key, "field": "l", "value": $0]) }
            factorMenu("Ş", values: [1, 2, 3, 4, 5], current: score.s) { perform(["type": "edit", "id": row.id, "key": key, "field": "s", "value": $0]) }
        }
    }
    private func editorBox<Content: View>(_ label: String, score: NovaRiskWizardResult.Score, note: String?, @ViewBuilder factors: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NovaText(text: label, style: .label)
                Spacer()
                if let note { NovaText(text: note, style: .metaQuiet) }
            }
            HStack(spacing: 8) {
                factors()
                Spacer(minLength: 0)
                NovaText(text: Self.number(score.score), style: .sectionTitle)
            }
            levelChip(score, showScore: false)
        }
        .padding(12)
        .background(NovaColorToken.surfaceMuted.color(in: scheme).opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }
    private func factorMenu(_ label: String, values: [Double], current: Double, pick: @escaping (Double) -> Void) -> some View {
        Menu {
            ForEach(values, id: \.self) { value in Button(Self.number(value)) { pick(value) } }
        } label: {
            VStack(spacing: 2) {
                NovaText(text: label, style: .micro)
                NovaText(text: Self.number(current), style: .bodyStrong)
            }
            .frame(minWidth: 46, minHeight: 44)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
        }.accessibilityLabel(Text(verbatim: "\(label) \(Self.number(current))"))
    }
    private static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: Shared pieces

    private func scorePair(_ label: String, _ before: NovaRiskWizardResult.Score, _ after: NovaRiskWizardResult.Score) -> some View {
        NovaWizardWrap(spacing: 6) {
            NovaText(text: label, style: .micro).frame(width: 26, alignment: .leading)
            levelChip(before, showScore: true)
            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .frame(height: 24)
            levelChip(after, showScore: true)
        }
    }
    private func levelChip(_ score: NovaRiskWizardResult.Score, showScore: Bool) -> some View {
        let tone = NovaRiskLevelTone.colors(score.level, scheme)
        return HStack(spacing: 5) {
            Circle().fill(tone.ink).frame(width: 6, height: 6)
            NovaText(text: (showScore ? Self.number(score.score) + " · " : "") + score.label, style: .badge, color: tone.ink)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 8))
    }
    private func tag(_ text: String, tone: String) -> some View { NovaWizardTag(text: text, tone: tone) }
    private func distribution(title text: String, sets: [(String, [String: Int])]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: text, style: .cardTitle)
            ForEach(sets, id: \.0) { label, counts in
                let total = max(1, counts.values.reduce(0, +))
                HStack(spacing: 8) {
                    NovaText(text: label, style: .metaQuiet).frame(width: 96, alignment: .leading)
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(NovaRiskLevelTone.order, id: \.self) { level in
                                Rectangle().fill(NovaRiskLevelTone.bar(level))
                                    .frame(width: geometry.size.width * CGFloat(counts[level] ?? 0) / CGFloat(total))
                            }
                        }.clipShape(Capsule())
                    }.frame(height: 10)
                    NovaText(text: "\(counts.values.reduce(0, +))", style: .meta).frame(width: 34, alignment: .trailing)
                }
            }
            ForEach(NovaRiskLevelTone.order, id: \.self) { level in
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3).fill(NovaRiskLevelTone.bar(level)).frame(width: 10, height: 10)
                    NovaText(text: NovaRiskLevelTone.names[level] ?? level, style: .meta)
                    Spacer()
                    ForEach(sets, id: \.0) { _, counts in NovaText(text: "\(counts[level] ?? 0)", style: .meta).frame(width: 44, alignment: .trailing) }
                }
            }
        }
    }
    private func optionRow(title: String, subtitle: String, tags: [String], badges: [String], selected: Bool, single: Bool, action: @escaping () -> Void) -> some View {
        NovaWizardOptionRow(title: title, subtitle: subtitle, tags: tags, badges: badges, selected: selected, single: single, action: action)
    }
    private func chips(_ items: [(String, String)], selected: String, pick: @escaping (String) -> Void) -> some View {
        NovaWizardWrap(spacing: 8) { ForEach(items, id: \.0) { item in chip(item.1, selected: selected == item.0) { pick(item.0) } } }
    }
    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaText(text: label, style: .label, color: selected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.text.color(in: scheme))
                .padding(.vertical, 9).padding(.horizontal, 14)
                .background((selected ? NovaColorToken.accentSoft : NovaColorToken.surface).color(in: scheme), in: Capsule())
                .overlay(Capsule().strokeBorder(selected ? NovaColorToken.accent.color(in: scheme) : .clear, lineWidth: 1.5))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Export

    private func export(_ format: String) {
        guard let runtime else { return }
        do {
            let file = try runtime.download(format: format)
            exportName = file.name; exportFile = .init(data: file.data); exporting = true
        } catch { message = error.localizedDescription }
    }
    private func archive() async {
        guard let runtime, let files, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let download = try runtime.download(format: "xlsx")
            let draft = NovaFileDraft(title: RDLocalization.string("localizable.nova.risk.wizard.screen.risk.degerlendirmesi.taslak.6f2aaae4", table: .localizable, fallback: "Risk Değerlendirmesi · Taslak"), category: "risk_assessment",
                note: "Risk analizi sihirbazı · \(runtime.catalogVersion)", fileName: download.name, fileExtension: "xlsx", bytes: download.data.count,
                sha256: SHA256.hash(data: download.data).map { String(format: "%02x", $0) }.joined())
            let entry = try await files.file(company, draft, download.data)
            guard !Task.isCancelled else { return }
            archivedName = download.name
            message = "Dosyalarım: " + NovaFileWords.state(entry.state) + "."
        } catch let error as NovaFileFailure { message = NovaFileScreenWords.failure(error) }
        catch { message = "Dosya arşive eklenemedi. İndirerek kullanabilir veya tekrar deneyebilirsiniz." }
    }
}

/// Selected-item chips with a trailing remove symbol.
private struct FlowChips: View {
    let items: [(String, String)]
    let selected: Set<String>
    var trailingSymbol: String?
    let tap: (String) -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NovaWizardWrap(spacing: 8) {
            ForEach(items, id: \.0) { item in
                Button { tap(item.0) } label: {
                    HStack(spacing: 6) {
                        NovaText(text: item.1, style: .label, color: NovaColorToken.accentInk.color(in: scheme))
                        if let trailingSymbol { Image(systemName: trailingSymbol).font(.system(size: 11, weight: .bold)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme)) }
                    }
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .background(NovaColorToken.accentSoft.color(in: scheme), in: Capsule())
                }.buttonStyle(.plain)
            }
        }
    }
}
