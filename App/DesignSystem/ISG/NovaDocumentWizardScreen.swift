import SwiftUI
import UniformTypeIdentifiers
import CryptoKit

struct NovaWizardWorkplace: Identifiable {
    let id: UUID
    let name: String
}
private struct NovaWizardFile: FileDocument {
    static let readableContentTypes: [UTType] = [.data]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// A single accordion page, matching EducationEditor. Scope is optional at every step.
struct NovaDocumentWizardScreen: View {
    let domain: String
    let companiesSource: () async throws -> [NovaAnalysisCompanyOption]
    let workplacesSource: (UUID) async throws -> [NovaWizardWorkplace]
    let files: NovaFileLibraryClient
    var initialCompany: UUID?
    let onBack: () -> Void

    @State private var runtime: NovaDocumentWizardRuntime?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var workplaces: [NovaWizardWorkplace] = []
    @State private var company: UUID?
    @State private var workplace: UUID?
    @State private var selections: [String: Set<String>] = [:]
    @State private var states: [String: String] = [:]
    @State private var method = "fk"
    @State private var preset = "standard"
    @State private var step = 0
    @State private var search = ""
    @State private var shown = 12
    @State private var preview: NovaWizardPreview?
    @State private var message: String?
    @State private var scopeMessage: String?
    @State private var busy = false
    @State private var archivedHash: String?
    @State private var exportFile = NovaWizardFile(data: Data())
    @State private var exportName = "ISGADA.docx"
    @State private var exporting = false

    private var questions: [NovaWizardQuestion] { (runtime?.questions ?? []).filter { domain == "risk" || !["method", "preset"].contains($0.field) } }
    private var title: String { domain == "risk" ? "Risk Analizi Sihirbazı" : "Acil Durum Planı Sihirbazı" }
    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        NovaPageHeading(title: title, onBack: onBack)
                        if let runtime {
                            NovaHelpHint(text: RDLocalization.string("localizable.nova.document.wizard.screen.kapsaminizi.secin.taslagi.olusturun.ve.word.exce.eddf3ec3", table: .localizable, fallback: "Kapsamınızı seçin, taslağı oluşturun ve Word, Excel veya PDF olarak indirin. Firma seçimi isteğe bağlıdır."))
                            ForEach(Array(questions.enumerated()), id: \.element.id) { index, q in
                                NovaCard(padding: 14) {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Button { move(to: index) } label: {
                                            HStack(alignment: .top) {
                                                Text("\(index + 1)").font(NovaFont.font(.meta))
                                                VStack(alignment: .leading, spacing: 4) {
                                                    NovaText(text: q.text_tr, style: .cardTitle)
                                                    if step != index { NovaText(text: answerSummary(q.field), style: .metaQuiet) }
                                                }
                                                Spacer(minLength: 4)
                                                Image(systemName: step == index ? "chevron.up" : "chevron.down")
                                            }.contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityIdentifier("wizard.step.\(q.field)")
                                        if step == index {
                                            NovaText(text: q.help_tr, style: .meta)
                                            question(q, runtime: runtime)
                                            HStack {
                                                if index > 0 { NovaButton(label: "Geri", symbol: "chevron.left", variant: .surface) { move(to: index - 1) } }
                                                Spacer(minLength: 0)
                                                NovaButton(label: index == questions.count - 1 ? "Taslak oluştur" : "Devam", symbol: "chevron.right", isEnabled: !busy) {
                                                    if index == questions.count - 1 { generate() } else { move(to: index + 1) }
                                                }.accessibilityIdentifier("wizard.next")
                                            }
                                        }
                                    }
                                }.id(index).disabled(busy)
                            }
                            if let preview { result(preview).id(questions.count) }
                        } else if message == nil { ProgressView().frame(maxWidth: .infinity) }
                        if let message { NovaText(text: message, style: .meta) }
                    }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24 + novaTabBarInset)
                }
                .onChange(of: step) { value in
                    withAnimation(.easeInOut(duration: 0.2)) { scroll.scrollTo(value, anchor: .top) }
                }
            }
        }
        .task {
            do { runtime = try NovaDocumentWizardRuntime() } catch { message = error.localizedDescription }
            do {
                companies = try await companiesSource()
                if let initialCompany, companies.contains(where: { $0.id == initialCompany }) { company = initialCompany }
            } catch { scopeMessage = "Firmalar yüklenemedi. Firma seçmeden devam edebilir veya sayfayı yeniden açabilirsiniz." }
        }
        .task(id: company) { await loadWorkplaces() }
        .fileExporter(isPresented: $exporting, document: exportFile,
            contentType: UTType(filenameExtension: (exportName as NSString).pathExtension) ?? .data,
            defaultFilename: exportName) { result in
                if case .failure = result { message = "Dosya kaydedilemedi. Tekrar deneyebilirsiniz." }
                exportFile = .init(data: Data())
            }
    }

    @ViewBuilder private func question(_ q: NovaWizardQuestion, runtime: NovaDocumentWizardRuntime) -> some View {
        if q.field == "scope" {
            Picker("Firma", selection: $company) {
                Text(RDLocalization.string("localizable.nova.document.wizard.screen.firma.secmeden.devam.et.36ce6fb4", table: .localizable, fallback: "Firma seçmeden devam et")).tag(nil as UUID?)
                ForEach(companies) { Text($0.name).tag(Optional($0.id)) }
            }.pickerStyle(.menu).accessibilityIdentifier("wizard.company")
                .onChange(of: company) { _ in workplace = nil; workplaces = []; changed() }
            if !workplaces.isEmpty {
                Picker(RDLocalization.string("localizable.nova.document.wizard.screen.isyeri.198609fd", table: .localizable, fallback: "İşyeri"), selection: $workplace) {
                    Text(RDLocalization.string("localizable.nova.document.wizard.screen.isyeri.secmeden.devam.et.7f870416", table: .localizable, fallback: "İşyeri seçmeden devam et")).tag(nil as UUID?)
                    ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.menu).accessibilityIdentifier("wizard.workplace")
                    .onChange(of: workplace) { _ in changed() }
            }
            if let scopeMessage { NovaText(text: scopeMessage, style: .metaQuiet) }
        } else if q.field == "method" || q.field == "preset" {
            let selected = q.field == "method" ? method : preset
            ForEach((runtime.options[q.field] ?? [:]).keys.sorted(), id: \.self) { key in
                option(runtime.options[q.field]?[key] ?? key, selected: selected == key) {
                    if q.field == "method" { method = key } else { preset = key }; changed()
                }
            }
        } else {
            let choices = runtime.choices[q.field] ?? []
            NovaAnalysisSearchField(text: $search, placeholder: RDLocalization.string("localizable.nova.document.wizard.screen.secenek.ara.7bf34387", table: .localizable, fallback: "Seçenek ara"), identifier: "wizard.search.\(q.field)")
                .onChange(of: search) { _ in shown = 12 }
            let selected = selections[q.field] ?? []
            let filtered = choices.filter { search.isEmpty || ([$0.label] + $0.aliases).contains { searchKey($0).contains(searchKey(search)) } }
                .sorted { a, b in selected.contains(a.id) != selected.contains(b.id) ? selected.contains(a.id) : a.label.localizedStandardCompare(b.label) == .orderedAscending }
            ForEach(Array(filtered.prefix(shown))) { choice in
                option(choice.label, selected: selected.contains(choice.id)) {
                    var next = selected
                    if next.contains(choice.id) { next.remove(choice.id) }
                    else if next.count < 100 { next.insert(choice.id) }
                    else { message = "Bu başlıkta en fazla 100 seçenek seçebilirsiniz."; return }
                    selections[q.field] = next; states[q.field] = next.isEmpty ? "unknown" : "selected"; changed()
                }
            }
            if filtered.isEmpty { NovaText(text: RDLocalization.string("localizable.nova.document.wizard.screen.eslesen.secenek.yok.diger.sorulardan.kapsam.ekle.cc0f299e", table: .localizable, fallback: "Eşleşen seçenek yok. Diğer sorulardan kapsam ekleyebilirsiniz."), style: .metaQuiet) }
            if filtered.count > shown { NovaButton(label: RDLocalization.string("localizable.nova.document.wizard.screen.daha.fazla.goster.956cb4d1", table: .localizable, fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) { shown += 20 } }
            option("Yok", selected: states[q.field] == "none") { selections[q.field] = []; states[q.field] = "none"; changed() }
            option("Bilmiyorum / sonra tamamlayacağım", selected: (states[q.field] ?? "unknown") == "unknown") { selections[q.field] = []; states[q.field] = "unknown"; changed() }
            NovaText(text: RDLocalization.format("localizable.nova.document.wizard.screen.1.secenek.secildi.fd69b1e3", table: .localizable, fallback: "%1$@ seçenek seçildi", arguments: [String(describing: selected.count)]), style: .metaQuiet)
        }
    }
    private func option(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                NovaText(text: label, style: .body)
                Spacer(minLength: 0)
            }.padding(.vertical, 8).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func searchKey(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .replacingOccurrences(of: "ı", with: "i")
    }
    private func move(to index: Int) { step = index; search = ""; shown = 12 }
    private func changed() { preview = nil; archivedHash = nil; message = nil }
    private func answerSummary(_ field: String) -> String {
        if field == "scope" { return companies.first { $0.id == company }?.name ?? "Firma seçmeden" }
        if field == "method" { return runtime?.options[field]?[method] ?? method }
        if field == "preset" { return runtime?.options[field]?[preset] ?? preset }
        if states[field] == "none" { return "Yok" }
        let count = selections[field]?.count ?? 0
        return count == 0 ? "Belirtilmedi" : "\(count) seçenek"
    }
    private func loadWorkplaces() async {
        workplace = nil; workplaces = []
        guard let selected = company else { return }
        do {
            let answer = try await workplacesSource(selected)
            guard !Task.isCancelled, company == selected else { return }
            workplaces = answer; scopeMessage = nil
        } catch {
            guard !Task.isCancelled, company == selected else { return }
            scopeMessage = "İşyeri listesi yüklenemedi. İşyeri seçmeden devam edebilirsiniz."
        }
    }
    private func generate() {
        guard let runtime else { return }
        var answers: [String: Any] = ["method": method, "preset": preset,
            "scope": ["company_id": company?.uuidString ?? "", "workplace_id": workplace?.uuidString ?? "",
                "company_name": companies.first { $0.id == company }?.name ?? "", "workplace_name": workplaces.first { $0.id == workplace }?.name ?? ""]]
        for key in runtime.choices.keys { answers[key] = ["state": states[key] ?? "unknown", "ids": Array(selections[key] ?? []).sorted()] }
        do {
            preview = try runtime.generate(answers: answers, domain: domain); step = questions.count; message = nil
            if domain == "emergency" { NovaForYouOutbox.recordUse("emergency_wizard") }
        }
        catch { message = error.localizedDescription }
    }
    @ViewBuilder private func result(_ preview: NovaWizardPreview) -> some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: RDLocalization.string("localizable.nova.document.wizard.screen.taslak.hazir.538b19f8", table: .localizable, fallback: "Taslak hazır"), style: .cardTitle)
                NovaText(text: domain == "risk" ? "\(preview.rows.count) risk · \(preview.unresolved.count) kapsamı netleşmemiş konu · \(preview.omitted.count) sınır dışında" : "\(preview.cards.count) acil durum eylem kartı", style: .meta)
                ForEach(preview.input_conflicts, id: \.self) { NovaHelpHint(text: $0) }
                ForEach(["docx", "xlsx", "pdf"], id: \.self) { format in
                    NovaButton(label: ["docx":"Word indir", "xlsx":"Excel indir", "pdf":"PDF indir"][format]!, symbol: "arrow.down.doc", variant: .surface, isEnabled: !busy) {
                        do { guard let runtime else { throw NovaWizardError.unavailable }; let file = try runtime.download(format: format); exportName = file.name; exportFile = .init(data: file.data); exporting = true }
                        catch { message = error.localizedDescription }
                    }
                }
                NovaButton(label: archivedHash == preview.content_sha256 ? "Arşive gönderildi" : "Word dosyasını arşive ekle", symbol: "folder.badge.plus", isEnabled: !busy && archivedHash != preview.content_sha256) {
                    Task { await archive(preview) }
                }
                if busy { ProgressView() }
                DisclosureGroup("Belge içeriği") {
                    if domain == "risk" { ForEach(preview.rows) { NovaText(text: "\($0.id) · \($0.scenario_tr)", style: .meta).padding(.vertical, 4) } }
                    else { ForEach(preview.cards) { NovaText(text: "\($0.id) · \($0.title_tr)", style: .meta).padding(.vertical, 4) } }
                }
                if domain == "risk" && !preview.unresolved.isEmpty {
                    DisclosureGroup("Kapsamı netleşmemiş konular") {
                        ForEach(preview.unresolved) { gap in
                            NovaText(text: "\(gap.title)\nGerekli bilgi: \(gap.missing_labels.joined(separator: "; "))", style: .meta).padding(.vertical, 6)
                        }
                    }
                    NovaText(text: RDLocalization.string("localizable.nova.document.wizard.screen.ilgili.soruya.donup.kapsam.secimini.genisletebil.49c4cc1e", table: .localizable, fallback: "İlgili soruya dönüp kapsam seçimini genişletebilirsiniz. Bu konular belgenin ekinde de yer alır."), style: .metaQuiet)
                }
                if domain == "risk" && !preview.omitted.isEmpty {
                    DisclosureGroup("Satır sınırı dışında kalan konular") { ForEach(preview.omitted) { NovaText(text: "\($0.id) · \($0.title)", style: .meta).padding(.vertical, 4) } }
                }
            }
        }
    }
    private func archive(_ preview: NovaWizardPreview) async {
        guard let runtime, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let download = try runtime.download(format: "docx")
            let draft = NovaFileDraft(title: title + " · Taslak", category: domain == "risk" ? "risk_assessment" : "emergency_plan",
                note: "Sihirbaz taslağı · \(preview.content_sha256)", fileName: download.name, fileExtension: "docx", bytes: download.data.count,
                sha256: SHA256.hash(data: download.data).map { String(format: "%02x", $0) }.joined())
            let entry = try await files.file(company, draft, download.data)
            guard !Task.isCancelled else { return }
            archivedHash = preview.content_sha256
            message = "Dosyalarım: " + NovaFileWords.state(entry.state) + "."
        } catch let error as NovaFileFailure { message = NovaFileScreenWords.failure(error) }
        catch { message = "Dosya arşive eklenemedi. İndirerek kullanabilir veya tekrar deneyebilirsiniz." }
    }
}
