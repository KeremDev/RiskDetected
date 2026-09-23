import SwiftUI

struct NovaPilotProcessGate: View {
    let identity: NovaSessionIdentity
    let kind: String
    var initialCompany: UUID?
    var parent: UUID?
    var canWrite = true
    /// Opened from the company page's own empty-state "Ekle" action.
    var startInAddMode = false
    let onBack: () -> Void
    @State private var company: UUID?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var rows: [NovaProcessRow] = []
    @State private var creating = false
    @State private var selected: NovaProcessRow?
    @State private var search = ""
    @State private var hasMore = false
    @State private var visitSummary: NovaVisitSummary?
    @State private var busy = false
    @State private var failure: String?
    private var spec: NovaProcessKind { .get(kind) }
    private var service: NovaProcessService { .init(identity:identity) }
    private var fileService: NovaFileLibraryService { .live() }
    private var fileClient: NovaFileLibraryClient {
        .init(
            catalogue: { try await fileService.catalogue(identity) },
            library: { request in try await fileService.library(identity, query: request) },
            companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
            file: { company, draft, data in try await fileService.file(identity, company: company, draft: draft, data: data) },
            rename: { entry, title, category, note in
                try await fileService.rename(identity, entry: entry, title: title, category: category, note: note) },
            archive: { entry in try await fileService.archive(identity, entry: entry) },
            cancel: { entry in try await fileService.cancel(identity, entry: entry) },
            recheck: { entry in try await fileService.recheck(identity, entry: entry) },
            contents: { entry in try await fileService.contents(identity, entry: entry) },
            download: { bucket, path in try await fileService.download(identity, bucket: bucket, path: path) })
    }
    var body: some View {
        if kind == "work_permit" {
            NovaWorkPermitLibraryScreen(onBack: onBack)
        } else if startInAddMode, let initialCompany {
            // The existing editor still handles other process kinds.
            NovaProcessEditor(identity: identity, kind: kind, company: initialCompany, parent: parent, canWrite: canWrite, fileClient: fileClient)
        } else {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    NovaListHeading(title: spec.title, onBack: onBack) {
                        NovaButton(label: "Ekle", symbol: "plus", isEnabled: canWrite, compact: true) { creating = true }
                            .accessibilityIdentifier("process.add")
                    }
                    NovaHelpHint(text: spec.help)
                    if parent == nil && initialCompany == nil {
                        NovaFilterField(label: "Firma", options: [.init(id: nil, title: RDLocalization.string("localizable.nova.pilot.process.gate.tum.firmalar.9c5ba7ce", table: .localizable, fallback: "Tüm firmalar"))] + companies.map { .init(id: $0.id.uuidString, title: $0.name) },
                            selected: company?.uuidString, identifier: "process.company") { company = $0.flatMap(UUID.init(uuidString:)) }
                    }
                    if kind == "site_visit", let summary = visitSummary {
                        NovaCard(padding: 14) {
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Label("\(summary.visits)", systemImage: "figure.walk").font(NovaFont.font(.cardTitle))
                                    NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.toplam.ziyaret.b5b31200", table: .localizable, fallback: "Toplam ziyaret"), style: .meta)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Label(summary.recorded_minutes.map { "\($0) dk" } ?? "—", systemImage: "clock").font(NovaFont.font(.cardTitle))
                                    NovaText(text: RDLocalization.format("localizable.nova.pilot.process.gate.1.kayitta.sure.belirtilmis.ac720882", table: .localizable, fallback: "%1$@ kayıtta süre belirtilmiş", arguments: [String(describing: summary.timed_visits)]), style: .meta)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    HStack {
                        Image(systemName:"magnifyingglass")
                        TextField(RDLocalization.string("localizable.nova.pilot.process.gate.kayit.ara.95a19ded", table: .localizable, fallback: "Kayıt ara"),text:$search).onSubmit { Task { await load() } }
                        Button("Ara") { Task { await load() } }
                    }.padding(12).background(.white,in:RoundedRectangle(cornerRadius:14))
                    if busy { ProgressView(RDLocalization.string("localizable.nova.pilot.process.gate.yukleniyor.60f83b7a", table: .localizable, fallback: "Yükleniyor…")) }
                    if let failure { Text(failure).font(NovaFont.font(.meta)); Button(RDLocalization.string("localizable.nova.pilot.process.gate.yeniden.dene.63ec1d6a", table: .localizable, fallback: "Yeniden dene")) { Task { await load() } } }
                    if rows.isEmpty && !busy && failure == nil {
                        NovaEmptyState(title: spec.emptyTitle, message: spec.emptyMessage)
                    }
                    ForEach(rows) { row in
                        Button { selected = row } label: {
                            NovaCard(padding:16) {
                                VStack(alignment:.leading,spacing:8) {
                                    NovaText(text:row.title.replacingOccurrences(of:"[\"",with:"").replacingOccurrences(of:"\"]",with:""),style:.cardTitle)
                                    NovaText(text:row.company_name + " · " + String(row.date.prefix(10)),style:.meta)
                                    if kind == "site_visit" {
                                        if let duration = row.values["duration_minutes"], !duration.text.isEmpty {
                                            NovaText(text: duration.text + " dk", style: .meta)
                                        }
                                        if let contact = row.values["responsible_contact"]?.text, !contact.isEmpty {
                                            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.gorusulen.3e7dafa0", table: .localizable, fallback: "Görüşülen: ") + contact, style: .meta)
                                        }
                                    }
                                    if let state = row.values["state"]?.text, !state.isEmpty {
                                        NovaText(text: spec.fields.first(where: { $0.id == "state" })?.choices[state] ?? ["active":"Aktif", "closed":RDLocalization.string("localizable.nova.pilot.process.gate.kapali.beee63d1", table: .localizable, fallback: "Kapalı")][state] ?? state, style: .meta)
                                    }
                                    if let summary = row.child_summary {
                                        NovaText(text: RDLocalization.format("localizable.nova.pilot.process.gate.1.alt.kayit.2.acik.3.gecikmis.a7444ff8", table: .localizable, fallback: "%1$@ alt kayıt · %2$@ açık · %3$@ gecikmiş", arguments: [String(describing: summary.total), String(describing: summary.open), String(describing: summary.overdue)]), style: .meta)
                                    }
                                    Label(RDLocalization.string("localizable.nova.pilot.process.gate.ac.duzenle.b23b0bf9", table: .localizable, fallback: "Aç / Düzenle"),systemImage:"chevron.right").font(NovaFont.font(.meta))
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }
                        }.buttonStyle(NovaRowPressStyle())
                    }
                    if hasMore { Button(RDLocalization.string("localizable.nova.pilot.process.gate.daha.fazla.ff0c7e09", table: .localizable, fallback: "Daha fazla")) { Task { await load(more:true) } }.disabled(busy) }
                }.padding(16)
            }
        }
        .font(.custom("PlusJakartaSans-Regular",size:14)).tint(.primary)
        .task { company = initialCompany; await load() }
        .onChange(of:company) { _ in Task { await load() } }
        .novaFullScreenCover(isPresented: longCreatePresentation, onDismiss: { Task { await load() } }) {
            createContent
        }
        .novaPopup(isPresented: shortCreatePresentation, onDismiss: { Task { await load() } }) {
            createContent
        }
        .novaFullScreenCover(item: longSelection, onDismiss: { Task { await load() } }) { row in
            NovaProcessEditor(identity:identity,kind:kind,company:row.company_id,parent:parent,record:row.id,canWrite:canWrite,fileClient:fileClient)
        }
        .novaPopup(item: shortSelection,onDismiss:{Task { await load() }}) { row in
            NovaProcessEditor(identity:identity,kind:kind,company:row.company_id,parent:parent,record:row.id,canWrite:canWrite,fileClient:fileClient)
        }
        }
    }

    private var longTaskKinds: Set<String> {
        ["site_visit", "annual_work_plan", "board", "completed_drill", "work_permit",
         "katip_contract", "contractor", "contractor_engagement"]
    }
    private var isLongTask: Bool { longTaskKinds.contains(kind) }
    private var longCreatePresentation: Binding<Bool> {
        Binding(get: { creating && isLongTask }, set: { if !$0 { creating = false } })
    }
    private var shortCreatePresentation: Binding<Bool> {
        Binding(get: { creating && !isLongTask }, set: { if !$0 { creating = false } })
    }
    private var longSelection: Binding<NovaProcessRow?> {
        Binding(get: { isLongTask ? selected : nil }, set: { selected = $0 })
    }
    private var shortSelection: Binding<NovaProcessRow?> {
        Binding(get: { isLongTask ? nil : selected }, set: { selected = $0 })
    }

    @ViewBuilder private var createContent: some View {
        if (parent != nil || initialCompany != nil), let company {
            NovaProcessEditor(identity: identity, kind: kind, company: company, parent: parent,
                canWrite: canWrite, fileClient: fileClient)
        } else {
            NovaCompanyCreateFlow(title: spec.title,
                companies: { try await NovaAnalysisWorkspace.companyOptions(identity: identity) },
                catalogue: { selected in
                    try JSONDecoder().decode(NovaProcessPage.self,
                        from: await service.read(kind: kind, company: selected))
                }, onSelect: { _ in }, fullScreenTask: isLongTask,
                onClose: { creating = false }) { _, company in
                    NovaProcessEditor(identity: identity, kind: kind, company: company, parent: parent,
                        canWrite: canWrite, fileClient: fileClient)
                }
        }
    }
    private func load(more:Bool = false) async {
        let scope = company; busy = true; failure = nil
        if !more { visitSummary = nil }
        defer { busy = false }
        do {
            if companies.isEmpty { companies = try await NovaAnalysisWorkspace.companyOptions(identity:identity) }
            let page = try JSONDecoder().decode(NovaProcessPage.self,from:await service.read(kind:kind,company:scope,parent:parent,query:search,offset:more ? rows.count : 0))
            guard company == scope else { return }
            rows = more ? rows + page.rows : page.rows; hasMore = page.has_more
            if kind == "site_visit" {
                let summary = try await service.visitSummary(company: scope)
                guard company == scope else { return }
                visitSummary = summary
            }
        } catch { failure = NovaProcessService.message(error) }
    }
}

struct NovaProcessEditor: View {
    let identity: NovaSessionIdentity
    let kind: String
    let company: UUID
    var parent: UUID?
    var record: UUID?
    var canWrite = true
    let fileClient: NovaFileLibraryClient
    @State private var row: NovaProcessRow?
    @State private var catalogue: NovaProcessPage?
    @State private var values: [String:NovaModuleValue] = [:]
    @State private var document = ""
    @State private var relatedKind = ""
    @State private var relatedID = ""
    @State private var choosingRelated = false
    @State private var relatedTitle = ""
    @State private var busy = false
    @State private var loading = true
    @State private var failure: String?
    @State private var deletePrompt = false
    @State private var children = false
    @State private var pdf: URL?
    @State private var attachment: NovaFileEntry?
    @State private var cancelling = false
    @State private var visitStep = 0
    @State private var visitSaved = false
    @State private var processStep = 0
    @State private var processSaved = false
    @State private var personSearch = ""
    @State private var photoDraft = ""
    @State private var cancelReason = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private var spec: NovaProcessKind { .get(kind) }
    private var service: NovaProcessService { .init(identity:identity) }
    /// Board meetings drop the planning fields from the form — the expert
    /// records what happened, not what is scheduled — and cancelling is its
    /// own action instead of a state choice sitting in the general form.
    private var visibleFields: [NovaProcessField] {
        if kind == "completed_drill" || kind == "personnel_certificate" {
            return spec.fields.filter { field in
                if field.id == "valid_until" { return !automaticDeadline || values["due_override"]?.text == "true" }
                if field.id == "due_override" { return automaticDeadline }
                return true
            }
        }
        guard kind == "board" else { return spec.fields }
        return spec.fields.filter { !["applicability","state","held_on","cancelled_reason"].contains($0.id) && ($0.id != "initial_decisions" || record == nil) }
    }
    var body: some View {
        Group {
            if kind == "site_visit" {
                if visitSaved {
                    NovaTaskSuccessView(title: record == nil ? RDLocalization.string("localizable.nova.pilot.process.gate.saha.ziyareti.kaydedildi.a361d5c6", table: .localizable, fallback: "Saha ziyareti kaydedildi") : RDLocalization.string("localizable.nova.pilot.process.gate.saha.ziyareti.guncellendi.c76ffdcb", table: .localizable, fallback: "Saha ziyareti güncellendi"),
                        message: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.bilgileri.ve.eklediginiz.kanitlar.firma..7c1bb328", table: .localizable, fallback: "Ziyaret bilgileri ve eklediğiniz kanıtlar firma kaydına işlendi."),
                        nextTitle: nil, onNext: nil, doneTitle: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaretlere.don.833d2bf5", table: .localizable, fallback: "Ziyaretlere dön")) { dismiss() }
                } else {
                    NovaPageSurface(onEdgeBack: visitBack) { siteVisitWizard }
                }
            } else if usesGenericWizard {
                if processSaved {
                    NovaTaskSuccessView(title: "\(spec.title) kaydedildi",
                        message: RDLocalization.string("localizable.nova.pilot.process.gate.kayit.firma.kapsamina.eklendi.ve.ilgili.listede..2e7ce026", table: .localizable, fallback: "Kayıt firma kapsamına eklendi ve ilgili listede kullanıma hazır."),
                        doneTitle: RDLocalization.string("localizable.nova.pilot.process.gate.listeye.don.45797e82", table: .localizable, fallback: "Listeye dön")) { dismiss() }
                } else {
                    NovaPageSurface(onEdgeBack: processBack) { processWizard }
                }
            } else if isLongTaskKind {
                NovaPageSurface(onEdgeBack: { dismiss() }) { formContent }
            } else {
                NovaPopup { formContent }
            }
        }
        .preference(key:NovaPopupBusyKey.self,value:busy)
        .task { await load() }
        .onChange(of: values["certificate_kind"]?.text) { new in
            guard kind == "personnel_certificate", row == nil else { return }
            let defaults = ["first_aid":RDLocalization.string("localizable.nova.pilot.process.gate.ilk.yardim.belgesi.af891e72", table: .localizable, fallback: "İlk Yardım Belgesi"), "myk":RDLocalization.string("localizable.nova.pilot.process.gate.myk.belgesi.b674676d", table: .localizable, fallback: "MYK Belgesi"), "custom":""]
            let current = values["title"]?.text ?? ""
            if current.isEmpty || defaults.values.contains(current) { values["title"] = .string(defaults[new ?? ""] ?? "") }
        }
        .confirmationDialog(RDLocalization.string("localizable.nova.pilot.process.gate.kayit.aktif.listeden.kaldirilacak.gecmisi.korunu.616065a6", table: .localizable, fallback: "Kayıt aktif listeden kaldırılacak. Geçmişi korunur."),isPresented:$deletePrompt,titleVisibility:.visible) {
            Button("Sil",role:.destructive) { Task { await remove() } }
        }
        .novaPopup(isPresented:$children, onDismiss: { Task { await load() } }) {
            if let child = spec.child, let row {
                NovaPilotProcessGate(identity:identity,kind:child,initialCompany:company,parent:row.id,canWrite:canWrite,onBack:{children = false})
            }
        }
        .novaPopup(isPresented: $choosingRelated) {
            NovaProcessLinkPicker(identity: identity, company: company, excluding: record) { selected, selectedKind in
                relatedKind = selectedKind; relatedID = selected.id.uuidString; relatedTitle = selected.title
            }
        }
        .novaPopup(item: $attachment) { file in
            NovaFileEntrySheet(entry: file, catalogue: [], assurance: .init(), client: fileClient,
                canWrite: false, onChanged: {}, onClosed: { attachment = nil })
        }
        .sheet(item:$pdf) { NovaFileShareSheet(url:$0) }
    }

    private var isLongTaskKind: Bool {
        ["annual_work_plan", "board", "completed_drill", "work_permit", "katip_contract",
         "contractor", "contractor_engagement"].contains(kind)
    }
    private var usesGenericWizard: Bool { record == nil && isLongTaskKind }

    private var processWizard: some View {
        VStack(spacing: 0) {
            NovaTaskHeader(title: spec.title, step: processStep + 1, total: 4,
                stepTitle: processStepTitle, onClose: processBack)
                .padding(.horizontal, 18).padding(.top, 10)
            if loading {
                NovaLoadingView(message: RDLocalization.string("localizable.nova.pilot.process.gate.form.hazirlaniyor.02441b51", table: .localizable, fallback: "Form hazırlanıyor…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let catalogue {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        processStepContent(catalogue)
                        if let failure { NovaTaskErrorSummary(message: failure) }
                    }.padding(20).padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NovaTaskStickyActions(primaryTitle: processStep == 3 ? RDLocalization.string("localizable.nova.pilot.process.gate.kaydet.52d1fc82", table: .localizable, fallback: "Kaydet") : RDLocalization.string("localizable.nova.pilot.process.gate.devam.21535294", table: .localizable, fallback: "Devam"),
                        primarySymbol: processStep == 3 ? "checkmark" : "arrow.right",
                        isWorking: busy, canGoBack: true, onBack: processBack, onPrimary: processAdvance)
                }
            } else {
                NovaTaskErrorSummary(message: failure ?? RDLocalization.string("localizable.nova.pilot.process.gate.form.hazirlanamadi.d2df5aa4", table: .localizable, fallback: "Form hazırlanamadı.")).padding(20)
                Spacer()
            }
        }
        .accessibilityIdentifier("nova.process.wizard.\(kind).step.\(processStep + 1)")
    }

    @ViewBuilder private func processStepContent(_ catalogue: NovaProcessPage) -> some View {
        let scopeTypes = Set(["workplaces", "employee", "organizations"])
        let fileTypes = Set(["file", "photo", "pdf", "photos"])
        switch processStep {
        case 0:
            NovaText(text: "Kapsam", style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.process.gate.firma.secimi.korunur.isyeri.ve.ilgili.kapsam.son.41c7fc9e", table: .localizable, fallback: "Firma seçimi korunur; işyeri ve ilgili kapsam sonraki adımlara otomatik taşınır."))
            ForEach(visibleFields.filter { scopeTypes.contains($0.type) }) { field in
                fieldRow(field) { control(field, catalogue) }
            }
            if visibleFields.allSatisfy({ !scopeTypes.contains($0.type) }) {
                NovaFormValueRow(label: RDLocalization.string("localizable.nova.pilot.process.gate.firma.kapsami.487d914d", table: .localizable, fallback: "Firma kapsamı"), symbol: "building.2") {
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.secili.firma.3e5ddba9", table: .localizable, fallback: "Seçili firma"), style: .bodyStrong)
                }
            }
        case 1:
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.kayit.bilgileri.801b901b", table: .localizable, fallback: "Kayıt bilgileri"), style: .sectionTitle)
            ForEach(visibleFields.filter { !scopeTypes.contains($0.type) && !fileTypes.contains($0.type) }) { field in
                fieldRow(field) { control(field, catalogue) }
            }
        case 2:
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.dosya.ve.kanit.fe5f3536", table: .localizable, fallback: "Dosya ve kanıt"), style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.process.gate.dosya.ve.fotograflar.istege.baglidir.kaydi.daha..86687b3c", table: .localizable, fallback: "Dosya ve fotoğraflar isteğe bağlıdır; kaydı daha sonra da tamamlayabilirsiniz."))
            ForEach(visibleFields.filter { fileTypes.contains($0.type) }) { field in
                fieldRow(field) { control(field, catalogue) }
            }
            if visibleFields.allSatisfy({ !fileTypes.contains($0.type) }) {
                NovaEmptyState(title: RDLocalization.string("localizable.nova.pilot.process.gate.bu.kayit.icin.dosya.gerekmiyor.df004ccd", table: .localizable, fallback: "Bu kayıt için dosya gerekmiyor"),
                    message: RDLocalization.string("localizable.nova.pilot.process.gate.devam.ederek.girdiginiz.bilgileri.kontrol.edebil.836b4102", table: .localizable, fallback: "Devam ederek girdiğiniz bilgileri kontrol edebilirsiniz."))
            }
        default:
            NovaText(text: "Kontrol", style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.process.gate.kaydetmeden.once.bilgileri.dogrulayin.degisiklik.a55956f7", table: .localizable, fallback: "Kaydetmeden önce bilgileri doğrulayın; değişiklik için Geri ile ilgili adıma dönebilirsiniz."))
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    visitReviewRow(RDLocalization.string("localizable.nova.pilot.process.gate.kayit.0da24f7e", table: .localizable, fallback: "Kayıt"), spec.title)
                    visitReviewRow(RDLocalization.string("localizable.nova.pilot.process.gate.zorunlu.alanlar.0bc14850", table: .localizable, fallback: "Zorunlu alanlar"), valid ? RDLocalization.string("localizable.nova.pilot.process.gate.tamamlandi.6db189bc", table: .localizable, fallback: "Tamamlandı") : RDLocalization.string("localizable.nova.pilot.process.gate.eksik.bilgi.var.587de8f6", table: .localizable, fallback: "Eksik bilgi var"))
                    visitReviewRow("Dosya", visibleFields.filter { fileTypes.contains($0.type) }
                        .contains { !(values[$0.id]?.text.isEmpty ?? true) } ? "Eklendi" : "Eklenmedi")
                }
            }
        }
    }

    private var processStepTitle: String {
        ["Kapsam", RDLocalization.string("localizable.nova.pilot.process.gate.kayit.bilgileri.9a4421e7", table: .localizable, fallback: "Kayıt bilgileri"), "Dosya", "Kontrol"][processStep]
    }
    private func processBack() {
        failure = nil
        if processStep > 0 { processStep -= 1 } else { dismiss() }
    }
    private func processAdvance() {
        failure = nil
        if processStep == 0 {
            let scopeFields = visibleFields.filter { ["workplaces", "employee", "organizations"].contains($0.type) && $0.required }
            guard scopeFields.allSatisfy({ !(values[$0.id]?.text.isEmpty ?? true) }) else {
                failure = RDLocalization.string("localizable.nova.pilot.process.gate.kapsam.secimini.tamamlayin.280a6d84", table: .localizable, fallback: "Kapsam seçimini tamamlayın.")
                return
            }
        }
        if processStep == 3 {
            guard valid else { failure = RDLocalization.string("localizable.nova.pilot.process.gate.zorunlu.alanlari.ve.tarihleri.kontrol.edin.b1d81384", table: .localizable, fallback: "Zorunlu alanları ve tarihleri kontrol edin."); return }
            Task { await save() }
        } else { processStep += 1 }
    }

    private var siteVisitWizard: some View {
        VStack(spacing: 0) {
            NovaTaskHeader(title: record == nil ? RDLocalization.string("localizable.nova.pilot.process.gate.saha.ziyareti.ekle.129badad", table: .localizable, fallback: "Saha ziyareti ekle") : RDLocalization.string("localizable.nova.pilot.process.gate.saha.ziyaretini.duzenle.566f0445", table: .localizable, fallback: "Saha ziyaretini düzenle"),
                step: visitStep + 1, total: 4, stepTitle: visitStepTitle, onClose: visitBack)
                .padding(.horizontal, 18).padding(.top, 10)
            if loading {
                NovaLoadingView(message: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.formu.hazirlaniyor.d2be7da5", table: .localizable, fallback: "Ziyaret formu hazırlanıyor…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let catalogue {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        siteVisitStep(catalogue)
                        if let failure { NovaTaskErrorSummary(message: failure) }
                    }
                    .padding(20).padding(.bottom, 18)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NovaTaskStickyActions(primaryTitle: visitStep == 3 ? RDLocalization.string("localizable.nova.pilot.process.gate.ziyareti.kaydet.1b4c46b6", table: .localizable, fallback: "Ziyareti kaydet") : RDLocalization.string("localizable.nova.pilot.process.gate.devam.047ffa02", table: .localizable, fallback: "Devam"),
                        primarySymbol: visitStep == 3 ? "checkmark" : "arrow.right",
                        isWorking: busy, canGoBack: true, onBack: visitBack) {
                            visitAdvance()
                        }
                }
            } else {
                NovaTaskErrorSummary(message: failure ?? RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.formu.hazirlanamadi.14387c32", table: .localizable, fallback: "Ziyaret formu hazırlanamadı."))
                    .padding(20)
                Spacer()
            }
        }
        .accessibilityIdentifier("nova.site.visit.wizard.step.\(visitStep + 1)")
    }

    @ViewBuilder private func siteVisitStep(_ catalogue: NovaProcessPage) -> some View {
        switch visitStep {
        case 0:
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.isyeri.3797b165", table: .localizable, fallback: "İşyeri"), style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaretin.yapildigi.isyerini.secin.bu.secim.sonr.d1ad82de", table: .localizable, fallback: "Ziyaretin yapıldığı işyerini seçin. Bu seçim sonraki adımlara otomatik taşınır."))
            if let field = spec.fields.first(where: { $0.id == "workplace_id" }) {
                fieldRow(field) { control(field, catalogue) }
            }
        case 1:
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.tarih.saat.ve.sure.18c4b7f0", table: .localizable, fallback: "Tarih, saat ve süre"), style: .sectionTitle)
            if let field = spec.fields.first(where: { $0.id == "visited_on" }) {
                fieldRow(field) { control(field, catalogue) }
            }
            NovaCard(padding: 12) {
                fieldIcon("clock") {
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.suresi.dakika.b4b148dc", table: .localizable, fallback: "Ziyaret süresi (dakika)"), style: .label)
                        TextField(RDLocalization.string("localizable.nova.pilot.process.gate.orn.60.9e2993e1", table: .localizable, fallback: "Örn. 60"), text: text("duration_minutes"))
                            .keyboardType(.numberPad)
                    }
                }
            }
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.saat.bilgisi.dosya.zaman.cizelgesinde.korunur.su.4a527a60", table: .localizable, fallback: "Saat bilgisi dosya zaman çizelgesinde korunur; süreyi bilmiyorsanız boş bırakabilirsiniz."), style: .metaQuiet)
        case 2:
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.ayrintilari.346744f1", table: .localizable, fallback: "Ziyaret ayrıntıları"), style: .sectionTitle)
            ForEach(spec.fields.filter { ["expert_note", "location_note", "responsible_contact"].contains($0.id) }) { field in
                fieldRow(field) { control(field, catalogue) }
            }
        default:
            NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.dosya.ve.kontrol.4c444b2e", table: .localizable, fallback: "Dosya ve kontrol"), style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.pilot.process.gate.fotograf.veya.belge.eklemek.istege.baglidir.kayd.b08488fd", table: .localizable, fallback: "Fotoğraf veya belge eklemek isteğe bağlıdır. Kaydetmeden önce özet bilgileri kontrol edin."))
            if let field = spec.fields.first(where: { $0.id == "visit_asset_id" }) {
                fieldRow(field) { control(field, catalogue) }
            }
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 9) {
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.ozeti.c9845cf8", table: .localizable, fallback: "Ziyaret özeti"), style: .bodyStrong)
                    visitReviewRow(RDLocalization.string("localizable.nova.pilot.process.gate.isyeri.7316118a", table: .localizable, fallback: "İşyeri"), catalogue.workplaces.first(where: {
                        $0.id.uuidString.lowercased() == values["workplace_id"]?.text.lowercased()
                    })?.name ?? "—")
                    visitReviewRow("Tarih", values["visited_on"]?.text ?? "—")
                    visitReviewRow(RDLocalization.string("localizable.nova.pilot.process.gate.sure.e9f43d80", table: .localizable, fallback: "Süre"), (values["duration_minutes"]?.text).flatMap { $0.isEmpty ? nil : "\($0) dk" } ?? "Belirtilmedi")
                    visitReviewRow(RDLocalization.string("localizable.nova.pilot.process.gate.gorusulen.kisi.eaf53bcc", table: .localizable, fallback: "Görüşülen kişi"), values["responsible_contact"]?.text.isEmpty == false
                        ? values["responsible_contact"]!.text : "Belirtilmedi")
                }
            }
        }
    }

    private func visitReviewRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            NovaText(text: title, style: .metaQuiet)
            Spacer(minLength: 8)
            NovaText(text: value, style: .bodyStrong).multilineTextAlignment(.trailing)
        }
    }

    private var visitStepTitle: String {
        [RDLocalization.string("localizable.nova.pilot.process.gate.isyeri.c8b1b839", table: .localizable, fallback: "İşyeri"), RDLocalization.string("localizable.nova.pilot.process.gate.tarih.ve.sure.1012bb97", table: .localizable, fallback: "Tarih ve süre"), RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.ayrintilari.178e0b9e", table: .localizable, fallback: "Ziyaret ayrıntıları"), RDLocalization.string("localizable.nova.pilot.process.gate.dosya.ve.kontrol.f31ea776", table: .localizable, fallback: "Dosya ve kontrol")][visitStep]
    }

    private func visitBack() {
        failure = nil
        if visitStep > 0 { visitStep -= 1 } else { dismiss() }
    }

    private func visitAdvance() {
        failure = nil
        guard visitStepIsValid else {
            failure = visitStep == 0 ? RDLocalization.string("localizable.nova.pilot.process.gate.ziyaretin.yapildigi.isyerini.secin.e7b13b8b", table: .localizable, fallback: "Ziyaretin yapıldığı işyerini seçin.")
                : visitStep == 1 ? RDLocalization.string("localizable.nova.pilot.process.gate.sure.girildiginde.1.ile.1440.dakika.arasinda.olm.761367bc", table: .localizable, fallback: "Süre girildiğinde 1 ile 1440 dakika arasında olmalıdır.")
                : RDLocalization.string("localizable.nova.pilot.process.gate.ziyaret.notunu.yazin.e8f21376", table: .localizable, fallback: "Ziyaret notunu yazın.")
            return
        }
        if visitStep < 3 { visitStep += 1 }
        else { Task { await save() } }
    }

    private var visitStepIsValid: Bool {
        switch visitStep {
        case 0: return !(values["workplace_id"]?.text.isEmpty ?? true)
        case 1:
            guard !(values["visited_on"]?.text.isEmpty ?? true) else { return false }
            let duration = values["duration_minutes"]?.text ?? ""
            return duration.isEmpty || (Int(duration).map { (1...1440).contains($0) } ?? false)
        case 2: return !(values["expert_note"]?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        default: return valid
        }
    }

    @ViewBuilder private var formContent: some View {
            ScrollView {
                VStack(alignment:.leading,spacing:10) {
                    HStack(spacing: 10) {
                        Image(systemName: kindSymbol).font(.system(size: 19, weight: .regular))
                            .foregroundStyle(NovaColorToken.text.color(in: scheme)).frame(width: 34, height: 34)
                        NovaText(text: kind == "site_visit"
                            ? (record == nil ? RDLocalization.string("localizable.nova.pilot.process.gate.saha.ziyareti.ekle.d9538e05", table: .localizable, fallback: "Saha ziyareti ekle") : RDLocalization.string("localizable.nova.pilot.process.gate.saha.ziyaretini.duzenle.35285294", table: .localizable, fallback: "Saha ziyaretini düzenle"))
                            : spec.title, style: .sheetTitle)
                        Spacer(minLength: 0)
                    }
                    if kind == "katip_contract" { NovaText(text:RDLocalization.string("localizable.nova.pilot.process.gate.uzmanin.sozlesme.kaydidir.resmi.isg.katip.islemi.dd896d0b", table: .localizable, fallback: "Uzmanın sözleşme kaydıdır; resmî İSG-KATİP işlemi yapılmaz."),style:.meta) }
                    if kind == "work_permit" { NovaText(text:RDLocalization.string("localizable.nova.pilot.process.gate.form.hazirlama.aracidir.calismayi.baslatma.veya..49cd8142", table: .localizable, fallback: "Form hazırlama aracıdır. Çalışmayı başlatma veya saha onayı vermez."),style:.meta) }
                    if kind == "board", values["state"]?.text == "cancelled" {
                        NovaCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.bu.toplanti.iptal.edildi.57569c31", table: .localizable, fallback: "Bu toplantı iptal edildi."), style: .label, color: NovaColorToken.statusDangerInk.color(in: scheme))
                                if let reason = values["cancelled_reason"]?.text, !reason.isEmpty {
                                    NovaText(text: reason, style: .metaQuiet)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if loading { ProgressView(RDLocalization.string("localizable.nova.pilot.process.gate.kayit.yukleniyor.550e7267", table: .localizable, fallback: "Kayıt yükleniyor…")) }
                    if let catalogue, !loading {
                        if kind == "board" { boardCompactFields(catalogue) }
                        else if kind == "katip_contract" { katipCompactFields(catalogue) }
                        else {
                            if automaticDeadline {
                                NovaHelpHint(text: deadlineHint)
                            }
                            ForEach(visibleFields) { field in
                                fieldRow(field) { control(field,catalogue) }
                            }
                        }
                        if kind == "annual_work_item" || kind == "board_decision" || kind == "site_observation" {
                            NovaCard(padding: 12) {
                                fieldIcon("link") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.ilgili.surec.kaydi.c7af8e1d", table: .localizable, fallback: "İlgili süreç kaydı"), style: .label)
                                        NovaText(text: relatedID.isEmpty ? RDLocalization.string("localizable.nova.pilot.process.gate.gercek.kayda.baglanti.ekleyebilirsiniz.7cf3edfc", table: .localizable, fallback: "Gerçek kayda bağlantı ekleyebilirsiniz.") : (relatedTitle.isEmpty ? RDLocalization.string("localizable.nova.pilot.process.gate.bagli.kayit.0e83b622", table: .localizable, fallback: "Bağlı kayıt") : relatedTitle), style: .meta)
                                        HStack {
                                            Button(relatedID.isEmpty ? RDLocalization.string("localizable.nova.pilot.process.gate.kayit.sec.06eaed55", table: .localizable, fallback: "Kayıt seç") : RDLocalization.string("localizable.nova.pilot.process.gate.degistir.2b477c31", table: .localizable, fallback: "Değiştir")) { choosingRelated = true }
                                            if !relatedID.isEmpty { Button(RDLocalization.string("localizable.nova.pilot.process.gate.baglantiyi.kaldir.ab2c7d1e", table: .localizable, fallback: "Bağlantıyı kaldır")) { relatedKind = ""; relatedID = ""; relatedTitle = "" } }
                                        }.disabled(!canWrite)
                                    }
                                }
                            }
                        }
                        if kind == "board", row != nil, values["state"]?.text != "cancelled" {
                            NovaCard(padding: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    if cancelling {
                                        NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.iptal.gerekcesi.24caef5f", table: .localizable, fallback: "İptal gerekçesi"), style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                                        TextField(RDLocalization.string("localizable.nova.pilot.process.gate.iptal.gerekcesi.4a5415d7", table: .localizable, fallback: "İptal gerekçesi"), text: $cancelReason, axis: .vertical).lineLimit(2...4)
                                        HStack(spacing: 10) {
                                            NovaButton(label: RDLocalization.string("localizable.nova.pilot.process.gate.vazgec.26597986", table: .localizable, fallback: "Vazgeç"), symbol: "xmark", variant: .surface) { cancelling = false; cancelReason = "" }
                                            NovaButton(label: RDLocalization.string("localizable.nova.pilot.process.gate.toplantiyi.iptal.et.659db154", table: .localizable, fallback: "Toplantıyı iptal et"), symbol: "xmark.seal", variant: .primary,
                                                isEnabled: !cancelReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                                                Task { await cancelMeeting() }
                                            }
                                        }
                                    } else {
                                        Button(RDLocalization.string("localizable.nova.pilot.process.gate.toplantiyi.iptal.et.2ada5aa0", table: .localizable, fallback: "Toplantıyı iptal et")) { cancelling = true }
                                            .disabled(!canWrite)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        if row != nil {
                            if let child = spec.child {
                                Button(NovaProcessKind.get(child).title) { children = true }
                            }
                            if !["approved_notebook", "personnel_certificate"].contains(kind) {
                            Button { Task { await export() } } label:{Label(RDLocalization.string("localizable.nova.pilot.process.gate.pdf.indir.cab43f63", table: .localizable, fallback: "PDF indir"),systemImage:"arrow.down.doc")}
                            Button(RDLocalization.string("localizable.nova.pilot.process.gate.excel.indir.fd80e946", table: .localizable, fallback: "Excel indir")) { Task { await export(excel: true) } }
                            }
                            Button(RDLocalization.string("localizable.nova.pilot.process.gate.kaydi.sil.9b68b199", table: .localizable, fallback: "Kaydı sil"),role:.destructive) { deletePrompt = true }.disabled(!canWrite)
                        }
                        NovaButton(label:busy ? "Kaydediliyor…" : RDLocalization.string("localizable.nova.pilot.process.gate.kaydet.e9da903e", table: .localizable, fallback: "Kaydet"),symbol:"checkmark",variant:.primary) { Task { await save() } }
                            .disabled(busy || !valid || !canWrite)
                    }
                    if let failure { Text(failure).font(NovaFont.font(.meta)) }
                }.padding(20).novaPopupContentSize().disabled(busy)
            }
    }
    private var automaticDeadline: Bool { kind == "completed_drill" || (kind == "personnel_certificate" && values["certificate_kind"]?.text == "first_aid") }
    private var deadlineHint: String {
        let start = values[kind == "completed_drill" ? "held_on" : "issued_on"]?.text ?? ""
        let months = kind == "completed_drill" ? Int(row?.values["period_months"]?.text ?? "12") ?? 12 : 36
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let due = NovaDayField.date(start).flatMap { calendar.date(byAdding: .month, value: months, to: $0) }.map(NovaDayField.text) ?? "—"
        return kind == "completed_drill" ? RDLocalization.format("localizable.nova.pilot.process.gate.otomatik.takip.1.genel.aralik.12.ay.kayitli.made.7e488b8c", table: .localizable, fallback: "Otomatik takip: %1$@. Genel aralık 12 ay; kayıtlı maden işyerinde sunucu 6 ay uygular. Gerektiğinde tarihi değiştirebilirsiniz.", arguments: [String(describing: due)]) : RDLocalization.format("localizable.nova.pilot.process.gate.ilk.yardim.belgesi.icin.3.yil.1.belgenizdeki.tar.a42c3f40", table: .localizable, fallback: "İlk yardım belgesi için 3 yıl: %1$@. Belgenizdeki tarih farklıysa değiştirebilirsiniz.", arguments: [String(describing: due)])
    }
    private var photoIDs: [String] {
        if case .array(let items) = values["photo_ids"] { return items.map(\.text) }; return []
    }
    private var valid: Bool {
        if kind == "personnel_certificate" && (!automaticDeadline || values["due_override"]?.text == "true") && (values["valid_until"]?.text.isEmpty ?? true) { return false }

        if kind == "site_visit", let duration = values["duration_minutes"]?.text, !duration.isEmpty {
            guard let minutes = Int(duration), (1...1440).contains(minutes) else { return false }
        }
        return spec.fields.filter(\.required).allSatisfy { field in
            if case .array(let list) = values[field.id] { return !list.isEmpty }
            return !(values[field.id]?.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ?? true)
        }
    }
    private func text(_ key:String) -> Binding<String> {
        Binding(get:{
            if case .number(let n) = values[key] { return String(Int(n)) }
            if case .array(let list) = values[key] { return list.map(\.text).joined(separator:"\n") }
            return values[key]?.text ?? ""
        },set:{values[key] = .string($0)})
    }
    private var kindSymbol: String {
        switch kind {
        case "katip_contract": return "signature"
        case "annual_work_plan": return "calendar"
        case "annual_work_item": return "checkmark.circle"
        case "board": return "person.3"
        case "board_decision": return "checkmark.seal"
        case "site_visit": return "figure.walk"
        case "approved_notebook": return "book.closed"
        case "site_observation": return "eye"
        case "work_permit": return "doc.badge.gearshape"
        case "contractor": return "building.2.crop.circle"
        default: return "briefcase"
        }
    }
    /// A plain line icon in front of one field's label+control — no tint, no
    /// background chip, just the glyph.
    @ViewBuilder private func fieldIcon<V: View>(_ symbol: String, @ViewBuilder _ content: @escaping () -> V) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme)).frame(width: 20, height: 22)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func fieldRow<V: View>(_ field: NovaProcessField, @ViewBuilder _ value: @escaping () -> V) -> some View {
        if field.type == "date" {
            NovaDayField(label: field.title + (field.required ? " *" : ""), value: text(field.id), identifier: "process.date.\(field.id)", isClearable: !field.required)
        } else if ["file", "photo", "pdf", "photos"].contains(field.type) {
            value()
        } else {
            NovaCard(padding: 12) {
                fieldIcon(fieldSymbol(field)) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: field.title + (field.required ? " *" : ""), style: .label)
                        value()
                    }
                }
            }
        }
    }
    /// Keep the company scope and meeting date first, with enough width for each control.
    @ViewBuilder private func boardCompactFields(_ catalogue: NovaProcessPage) -> some View {
        if let workplaceField = spec.fields.first(where: { $0.id == "workplace_id" }) {
            fieldRow(workplaceField) { control(workplaceField, catalogue) }
        }
        if let dateField = spec.fields.first(where: { $0.id == "planned_on" }) {
            fieldRow(dateField) { control(dateField, catalogue) }
        }
        ForEach(visibleFields.filter { $0.id != "workplace_id" && $0.id != "planned_on" }) { field in
            fieldRow(field) { control(field, catalogue) }
        }
    }
    /// KATİP is entered often, so its text fields use their placeholder as the
    /// only caption. Dates remain labelled and share one compact row.
    @ViewBuilder private func katipCompactFields(_ catalogue: NovaProcessPage) -> some View {
        let dates = visibleFields.filter { ["starts_on", "ends_before"].contains($0.id) }
        let beforeDates = visibleFields.filter { ["workplace_id", "counterparty", "expert_contact", "scope"].contains($0.id) }
        let afterDates = visibleFields.filter { !["workplace_id", "counterparty", "expert_contact", "scope", "starts_on", "ends_before"].contains($0.id) }
        ForEach(beforeDates) { field in
            if field.type == "file" || field.type == "photo" || field.type == "pdf" || field.type == "workplaces" {
                fieldRow(field) { control(field, catalogue) }
            } else {
                NovaCard(padding: 12) {
                    fieldIcon(fieldSymbol(field)) { control(field, catalogue) }
                }
            }
        }
        HStack(alignment: .top, spacing: 8) {
            ForEach(dates) { field in
                NovaDayField(label: field.title + (field.required ? " *" : ""), value: text(field.id),
                    identifier: "process.date.\(field.id)", isClearable: !field.required)
                    .frame(maxWidth: .infinity)
            }
        }
        ForEach(afterDates) { field in
            if field.type == "file" || field.type == "photo" || field.type == "pdf" {
                fieldRow(field) { control(field, catalogue) }
            } else {
                NovaCard(padding: 12) {
                    fieldIcon(fieldSymbol(field)) { control(field, catalogue) }
                }
            }
        }
    }
    private func cancelMeeting() async {
        values["state"] = .string("cancelled")
        values["cancelled_reason"] = .string(cancelReason.trimmingCharacters(in: .whitespacesAndNewlines))
        await save()
        cancelling = false
    }
    private func fieldSymbol(_ field: NovaProcessField) -> String {
        switch field.type {
        case "choice": return "list.bullet.circle"
        case "workplaces","organizations": return "building.2"
        case "employees": return "person.2"
        case "date": return "calendar"
        case "datetime": return "calendar.badge.clock"
        case "multiline","lines": return "text.alignleft"
        case "number": return "number"
        case "file","photo": return "paperclip"
        default: return "pencil.line"
        }
    }
    /// The heading a filed document is tagged with in Dosyalarım, per kind.
    private func fileCategory(_ kind: String) -> String {
        switch kind {
        case "katip_contract": return "contract"
        case "work_permit": return "permit_form"
        case "board", "board_decision": return "board_document"
        case "contractor", "contractor_engagement": return "contractor_document"
        default: return "other"
        }
    }
    @ViewBuilder private func control(_ field:NovaProcessField,_ cat:NovaProcessPage) -> some View {
        switch field.type {
        case "lines":
            NovaNumberedItemsEditor(title: field.title, value: text(field.id))
        case "bool":
            Toggle(field.title, isOn: Binding(get: { values[field.id]?.text == "true" }, set: { values[field.id] = .bool($0) })).labelsHidden()
        case "employee":
            TextField(RDLocalization.string("localizable.nova.pilot.process.gate.personel.ara.a97c0517", table: .localizable, fallback: "Personel ara"), text: $personSearch)
            ForEach(cat.employees.filter { personSearch.isEmpty || $0.name.localizedStandardContains(personSearch) }) { person in
                Button { values[field.id] = .string(person.id.uuidString) } label: {
                    HStack { Text(person.name); Spacer(); Image(systemName: values[field.id]?.text.lowercased() == person.id.uuidString.lowercased() ? "checkmark.circle" : "circle") }
                        .font(NovaFont.font(.body)).padding(.vertical, 6)
                }.buttonStyle(NovaRowPressStyle())
            }
        case "photos":
            ForEach(Array(photoIDs.enumerated()), id: \.element) { index, id in
                HStack {
                    Label(RDLocalization.format("localizable.nova.pilot.process.gate.fotograf.1.b7530b66", table: .localizable, fallback: "Fotoğraf %1$@", arguments: [String(describing: index + 1)]), systemImage: "photo")
                    Spacer()
                    if row != nil { Button(RDLocalization.string("localizable.nova.pilot.process.gate.ac.7d524072", table: .localizable, fallback: "Aç")) { Task { await openAttachment("photo_ids:" + id, row!.id) } } }
                    Button { values["photo_ids"] = .array(photoIDs.filter { $0 != id }.map(NovaModuleValue.string)) } label: { Image(systemName: "xmark") }
                }
            }
            if photoIDs.count < 10 {
                NovaInlineFileField(imagesOnly: true, category: "other", company: company, fileClient: fileClient, assetID: $photoDraft)
                    .id(photoIDs.count)
                    .onChange(of: photoDraft) { value in
                        guard !value.isEmpty else { return }
                        if !photoIDs.contains(value) { values["photo_ids"] = .array((photoIDs + [value]).map(NovaModuleValue.string)) }
                        photoDraft = ""
                    }
            }
        case "file","photo","pdf":
            NovaInlineFileField(imagesOnly: field.type == "photo", pdfOnly: field.type == "pdf",
                label: field.title, category: fileCategory(kind), company: company,
                fileClient: fileClient, assetID: text(field.id))
            if let row, let saved = row.values[field.id]?.text, !saved.isEmpty, saved == values[field.id]?.text {
                Button { Task { await openAttachment(field.id, row.id) } } label: {
                    Label(RDLocalization.string("localizable.nova.pilot.process.gate.ekli.dosyayi.ac.17d11d19", table: .localizable, fallback: "Ekli dosyayı aç"), systemImage: "doc.viewfinder")
                }
            }
        case "choice":
            Picker(field.title,selection:text(field.id)) {
                Text(RDLocalization.string("localizable.nova.pilot.process.gate.secin.61f5a91b", table: .localizable, fallback: "Seçin")).tag("")
                ForEach(field.choices.keys.sorted(),id:\.self) { Text(field.choices[$0] ?? $0).tag($0) }
            }
        case "workplaces":
            // No workplace to open a record under, or exactly one: nothing to
            // ask. A picker only appears when there is a real choice.
            if cat.workplaces.count <= 1 {
                NovaText(text: cat.workplaces.first?.name
                    ?? RDLocalization.string("localizable.nova.pilot.process.gate.bu.firmada.kayit.acilacak.bir.isyeri.yok.71414654", table: .localizable, fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .cardTitle)
            } else {
                Picker(field.title,selection:text(field.id)) {
                    Text(RDLocalization.string("localizable.nova.pilot.process.gate.secin.3fbe11b8", table: .localizable, fallback: "Seçin")).tag("")
                    ForEach(cat.workplaces) { Text($0.name).tag($0.id.uuidString) }
                }
            }
        case "organizations":
            Picker(field.title,selection:text(field.id)) {
                Text(RDLocalization.string("localizable.nova.pilot.process.gate.secin.d7ebe960", table: .localizable, fallback: "Seçin")).tag("")
                ForEach(cat.organizations) { Text($0.name).tag($0.id.uuidString) }
            }
        case "employees":
            ForEach(cat.employees) { person in
                Toggle(person.name,isOn:Binding(get:{selectedPeople.contains(person.id.uuidString.lowercased())},set:{ checked in
                    var list = people
                    list.removeAll { if case .object(let obj) = $0 { return obj["id"]?.text.lowercased() == person.id.uuidString.lowercased() };return false }
                    if checked { list.append(.object(["id":.string(person.id.uuidString),"name":.string(person.name)])) }
                    values[field.id] = .array(list)
                }))
            }
        case "date","datetime":
            if !field.required {
                Toggle(RDLocalization.string("localizable.nova.pilot.process.gate.tarih.belirt.279003ea", table: .localizable, fallback: "Tarih belirt"), isOn: Binding(get: { !(values[field.id]?.text.isEmpty ?? true) }, set: { enabled in
                    values[field.id] = enabled ? .string(field.type == "datetime" ? ISO8601DateFormatter().string(from: Date()) : NovaDayField.text(Date())) : .null
                }))
            }
            if field.required || !(values[field.id]?.text.isEmpty ?? true) {
                DatePicker(field.title, selection: dateBinding(field), displayedComponents: field.type == "datetime" ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
            }
        default:
            TextField(field.title + (field.required ? " *" : ""),text:text(field.id),axis:field.type == "multiline" || field.type == "lines" ? .vertical : .horizontal)
                .lineLimit(field.type == "multiline" || field.type == "lines" ? 3...8 : 1...1)
                .keyboardType(field.type == "number" ? .numberPad : .default)
        }
    }
    private func openAttachment(_ field: String, _ record: UUID) async {
        busy = true; failure = nil; defer { busy = false }
        do { attachment = try await service.attachment(kind: kind, record: record, field: field) }
        catch { failure = NovaProcessService.message(error) }
    }
    private func dateBinding(_ field: NovaProcessField) -> Binding<Date> {
        Binding(get: {
            let value = values[field.id]?.text ?? ""
            return field.type == "datetime" ? (ISO8601DateFormatter().date(from: value) ?? Date()) : (NovaDayField.date(value) ?? Date())
        }, set: { value in
            values[field.id] = .string(field.type == "datetime" ? ISO8601DateFormatter().string(from: value) : NovaDayField.text(value))
        })
    }
    private var people: [NovaModuleValue] {
        if case .array(let list) = values[kind == "board" ? "attendance" : "parties"] { return list };return []
    }
    private var selectedPeople: Set<String> { Set(people.compactMap { if case .object(let obj) = $0 { return obj["id"]?.text.lowercased() };return nil }) }
    private func load() async {
        loading = true; defer { loading = false }
        do {
            catalogue = try JSONDecoder().decode(NovaProcessPage.self,from:await service.read(kind:kind,company:company,parent:parent))
            if let record {
                row = try JSONDecoder().decode(NovaProcessRow.self,from:await service.read(kind:kind,company:company,id:record))
                values = row?.values ?? [:]; document = row?.document_id?.uuidString ?? ""
                relatedKind = row?.related_kind ?? ""; relatedID = row?.related_id?.uuidString ?? ""
                if let related = row?.related_id, !relatedKind.isEmpty {
                    if let page = try? await service.references(kind: relatedKind, company: company, id: related),
                       let linked = page.rows.first { relatedTitle = linked.title }
                    else { relatedTitle = RDLocalization.string("localizable.nova.pilot.process.gate.bagli.kayit.artik.erisilebilir.degil.baglantiyi..2f12e665", table: .localizable, fallback: "Bağlı kayıt artık erişilebilir değil. Bağlantıyı değiştirebilir veya kaldırabilirsiniz.") }
                }
            } else {
                for field in spec.fields {
                    values[field.id] = ["employees","photos"].contains(field.type) ? .array([]) : field.type == "bool" ? .bool(false) : .string("")
                }
                let today = NovaDayField.text(Date())
                for key in ["starts_on","planned_on","visited_on","held_on","issued_on"] where spec.fields.contains(where:{$0.id == key}) { values[key] = .string(today) }
                if kind == "completed_drill" { values["drill_type"] = .string("emergency"); values["announcement"] = .string("announced") }
                if kind == "personnel_certificate" { values["certificate_kind"] = .string("first_aid"); values["title"] = .string(RDLocalization.string("localizable.nova.pilot.process.gate.ilk.yardim.belgesi.7b0df9a9", table: .localizable, fallback: "İlk Yardım Belgesi")); if let parent { values["employee_id"] = .string(parent.uuidString) } }
                if kind == "approved_notebook" { values["title"] = .string(RDLocalization.string("localizable.nova.pilot.process.gate.onayli.defter.8a5c0622", table: .localizable, fallback: "Onaylı Defter")) }
                if kind == "annual_work_plan" { values["plan_year"] = .string(String(Calendar.current.component(.year,from:Date()))) }
                if kind == "board" {
                    // No planning workflow: a board record is entered as a
                    // meeting that already happened, not one being scheduled.
                    values["applicability"] = .string("mandatory")
                    values["state"] = .string("held")
                    values["held_on"] = .string(today)
                } else if spec.fields.contains(where:{$0.id == "state"}) { values["state"] = .string(kind == "board_decision" ? "open" : "planned") }
                if kind == "work_permit" { values["template_code"] = .string("general") }
                if let key = spec.parentKey, let parent { values[key] = .string(parent.uuidString) }
                if kind == "contractor_engagement", let parent { values["organization_id"] = .string(parent.uuidString) }
                // One workplace is not a choice; fill it in rather than
                // asking again for the same answer.
                if spec.fields.contains(where: {$0.id == "workplace_id"}), let only = catalogue?.workplaces, only.count == 1 {
                    values["workplace_id"] = .string(only[0].id.uuidString)
                }
            }
        } catch { failure = NovaProcessService.message(error) }
    }
    private func payload() -> [String:PersonnelRPCValue] {
        var selected: [String:PersonnelRPCValue] = [:]
        for field in spec.fields {
            let value = values[field.id] ?? .null
            if field.type == "lines" {
                let lines = text(field.id).wrappedValue.components(separatedBy:"\n").map{$0.trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
                selected[field.id] = .array(lines.map(PersonnelRPCValue.string))
            } else if field.type == "number", case .number(let n) = value {
                selected[field.id] = .string(String(Int(n)))
            } else { selected[field.id] = value.text.isEmpty && !["employees","photos","bool"].contains(field.type) ? .null : value.rpc }
        }
        if automaticDeadline && values["due_override"]?.text != "true" { selected["valid_until"] = .null }
        if let key = spec.parentKey { selected[key] = values[key]?.rpc ?? .null }
        if kind == "board" {
            if values["state"]?.text == "held" { selected["held_on"] = selected["planned_on"] }
            else { selected["held_on"] = .null; selected["attendance"] = .null }
            if values["state"]?.text != "cancelled" { selected["cancelled_reason"] = .null }
        }
        if kind == "annual_work_item" {
            if values["state"]?.text != "performed" { selected["performed_on"] = .null }
            if values["state"]?.text != "carried_over" { selected["carry_over_reason"] = .null }
        }
        return ["kind":.string(kind),"id":row.map{.id($0.id)} ?? .null,"expected":row.map{.string($0.expected)} ?? .null,"values":.object(selected),"related_kind":relatedKind.isEmpty ? .null : .string(relatedKind),"related_id":UUID(uuidString:relatedID).map(PersonnelRPCValue.id) ?? .null,"document_id":UUID(uuidString:document).map(PersonnelRPCValue.id) ?? .null]
    }
    private func save() async {
        busy = true; failure = nil; defer {busy = false}
        do {
            _ = try await service.mutate(company:company,action:"save",payload:payload())
            if kind == "site_visit" { visitSaved = true }
            else if usesGenericWizard { processSaved = true }
            else { dismiss() }
        }
        catch { failure = NovaProcessService.message(error) }
    }
    private func remove() async {
        busy = true; failure = nil; defer {busy = false}
        do { _ = try await service.mutate(company:company,action:"delete",payload:payload());dismiss() }
        catch { failure = NovaProcessService.message(error) }
    }
    private func export(excel: Bool = false) async {
        busy = true; failure = nil; defer {busy = false}
        do {
            let data = try await service.mutate(company:company,action:"export",payload:payload())
            let snapshot = try JSONDecoder().decode(NovaProcessRow.self,from:data)
            pdf = try excel ? NovaProcessXLSX.write(snapshot,kind:spec,owner:identity.userID) : NovaProcessPDF.write(snapshot,kind:spec,owner:identity.userID)
        } catch { failure = NovaProcessService.message(error) }
    }
}


/// Search is always constrained to the editor's company; choosing a source
/// never changes its state or marks the activity performed.
private struct NovaProcessLinkPicker: View {
    let identity: NovaSessionIdentity
    let company: UUID
    let excluding: UUID?
    let onSelect: (NovaProcessRow, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "site_visit"
    @State private var query = ""
    @State private var rows: [NovaProcessRow] = []
    @State private var offset = 0
    @State private var hasMore = false
    @State private var loading = false
    @State private var error: String?
    private let kinds = ["checklist_run", "training_record", "equipment_inspection", "nonconformity", "site_visit", "board", "work_permit", "katip_contract", "annual_work_plan", "contractor"]
    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NovaText(text: RDLocalization.string("localizable.nova.pilot.process.gate.ilgili.kaydi.sec.f489b9ca", table: .localizable, fallback: "İlgili kaydı seç"), style: .cardTitle)
                    Picker(RDLocalization.string("localizable.nova.pilot.process.gate.kayit.turu.736f14d4", table: .localizable, fallback: "Kayıt türü"), selection: $kind) {
                        ForEach(kinds, id: \.self) { Text(NovaProcessService.referenceTitle($0)).tag($0) }
                    }
                    HStack {
                        TextField(RDLocalization.string("localizable.nova.pilot.process.gate.kayit.ara.aeb263ea", table: .localizable, fallback: "Kayıt ara"), text: $query).onSubmit { Task { await load() } }
                        Button("Ara") { Task { await load() } }.disabled(loading)
                    }
                    if loading { ProgressView(RDLocalization.string("localizable.nova.pilot.process.gate.kayitlar.yukleniyor.51cda1db", table: .localizable, fallback: "Kayıtlar yükleniyor…")) }
                    if let error { Text(error); Button(RDLocalization.string("localizable.nova.pilot.process.gate.yeniden.dene.33b96639", table: .localizable, fallback: "Yeniden dene")) { Task { await load() } } }
                    ForEach(rows) { row in
                        Button { onSelect(row, kind); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).fixedSize(horizontal: false, vertical: true)
                                Text(String(row.date.prefix(10))).font(NovaFont.font(.meta))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.buttonStyle(NovaRowPressStyle()).disabled(loading)
                    }
                    if rows.isEmpty && !loading && error == nil { Text(RDLocalization.string("localizable.nova.pilot.process.gate.bu.firmada.uygun.kayit.bulunamadi.42d9fdef", table: .localizable, fallback: "Bu firmada uygun kayıt bulunamadı.")) }
                    if hasMore { Button(RDLocalization.string("localizable.nova.pilot.process.gate.daha.fazla.c68e878d", table: .localizable, fallback: "Daha fazla")) { Task { await load(more: true) } }.disabled(loading) }
                }.padding(20).novaPopupContentSize()
            }
        }.task(id: kind) { query = ""; await load() }
    }
    private func load(more: Bool = false) async {
        let selectedKind = kind; let search = query
        loading = true; error = nil
        if !more { rows = []; offset = 0 }
        defer { if selectedKind == kind { loading = false } }
        do {
            let page = try await NovaProcessService(identity: identity).references(kind: selectedKind, company: company, query: search, offset: more ? offset : 0)
            try Task.checkCancellation()
            guard kind == selectedKind, query == search else { return }
            rows = (more ? rows : []) + page.rows.filter { $0.id != excluding }
            offset += page.rows.count; hasMore = page.has_more
        } catch is CancellationError { }
        catch { if selectedKind == kind { self.error = NovaProcessService.message(error) } }
    }
}
