import SwiftUI

struct NovaPilotProcessGate: View {
    let identity: NovaSessionIdentity
    let kind: String
    var initialCompany: UUID?
    var parent: UUID?
    var canWrite = true
    let onBack: () -> Void
    @State private var company: UUID?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var rows: [NovaProcessRow] = []
    @State private var creating = false
    @State private var selected: NovaProcessRow?
    @State private var search = ""
    @State private var hasMore = false
    @State private var busy = false
    @State private var failure: String?
    @State private var createCompany: UUID?
    private var spec: NovaProcessKind { .get(kind) }
    private var service: NovaProcessService { .init(identity:identity) }
    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    HStack(spacing: 8) {
                        NovaBackButton(action: onBack)
                        // Some of these titles ("Yıllık Çalışma Planı") are long
                        // enough to push an unstyled trailing button off the
                        // right edge on a phone-width screen — it looked like
                        // the add action simply did nothing. Scale the title
                        // down instead of letting it claim unlimited width.
                        NovaText(text:spec.title,style:.screenTitle)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 8)
                        Button { creating = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                                Text("Ekle").font(.system(size: 13, weight: .semibold))
                            }
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Color.accentColor.opacity(canWrite ? 1 : 0.4), in: Capsule())
                            .foregroundStyle(.white)
                        }.buttonStyle(.plain).disabled(!canWrite)
                            .accessibilityIdentifier("process.add")
                    }
                    if parent == nil && initialCompany == nil {
                        Picker("Firma",selection:$company) {
                            Text("Tüm firmalar").tag(UUID?.none)
                            ForEach(companies) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    HStack {
                        Image(systemName:"magnifyingglass")
                        TextField("Kayıt ara",text:$search).onSubmit { Task { await load() } }
                        Button("Ara") { Task { await load() } }
                    }.padding(12).background(.white,in:RoundedRectangle(cornerRadius:14))
                    if busy { ProgressView("Yükleniyor…") }
                    if let failure { Text(failure).font(NovaFont.font(.meta)); Button("Yeniden dene") { Task { await load() } } }
                    if rows.isEmpty && !busy && failure == nil { NovaText(text:"Henüz kayıt yok. Ekle düğmesiyle başlayabilirsiniz.",style:.body) }
                    ForEach(rows) { row in
                        Button { selected = row } label: {
                            NovaCard(padding:16) {
                                VStack(alignment:.leading,spacing:8) {
                                    NovaText(text:row.title.replacingOccurrences(of:"[\"",with:"").replacingOccurrences(of:"\"]",with:""),style:.cardTitle)
                                    NovaText(text:row.company_name + " · " + String(row.date.prefix(10)),style:.meta)
                                    if let state = row.values["state"]?.text, !state.isEmpty {
                                        NovaText(text: spec.fields.first(where: { $0.id == "state" })?.choices[state] ?? ["active":"Aktif", "closed":"Kapalı"][state] ?? state, style: .meta)
                                    }
                                    if let summary = row.child_summary {
                                        NovaText(text: "\(summary.total) alt kayıt · \(summary.open) açık · \(summary.overdue) gecikmiş", style: .meta)
                                    }
                                    Label("Aç / Düzenle",systemImage:"chevron.right").font(NovaFont.font(.meta))
                                }.frame(maxWidth:.infinity,alignment:.leading)
                            }
                        }.buttonStyle(.plain)
                    }
                    if hasMore { Button("Daha fazla") { Task { await load(more:true) } }.disabled(busy) }
                }.padding(16)
            }
        }
        .font(.custom("PlusJakartaSans-Regular",size:14)).tint(.primary)
        .task { company = initialCompany; await load() }
        .onChange(of:company) { _ in Task { await load() } }
        .sheet(isPresented:$creating,onDismiss:{createCompany = nil; Task { await load() }}) {
            if (parent != nil || initialCompany != nil), let company {
                NovaProcessEditor(identity:identity,kind:kind,company:company,parent:parent,canWrite:canWrite)
            } else {
                NovaCompanyCreateFlow(title:spec.title,companies:{try await NovaAnalysisWorkspace.companyOptions(identity:identity)},catalogue:{ selected in
                    try JSONDecoder().decode(NovaProcessPage.self,from:await service.read(kind:kind,company:selected))
                },onSelect:{createCompany = $0}) { _ in
                    // createCompany is set by onSelect just above, synchronously,
                    // before this content closure can ever run with a loaded
                    // catalogue — but a screen must never go silently blank if
                    // that assumption is ever wrong, so the failure is visible
                    // and recoverable instead of an empty popup.
                    if let company = createCompany {
                        NovaProcessEditor(identity:identity,kind:kind,company:company,parent:parent,canWrite:canWrite)
                    } else {
                        VStack(spacing: 12) {
                            NovaText(text: "Firma seçimi kayboldu. Firmayı yeniden seçin.", style: .body)
                            NovaButton(label: "Kapat", symbol: "xmark", variant: .surface) { creating = false }
                        }.padding(20)
                    }
                }
            }
        }
        .sheet(item:$selected,onDismiss:{Task { await load() }}) { row in
            NovaProcessEditor(identity:identity,kind:kind,company:row.company_id,parent:parent,record:row.id,canWrite:canWrite)
        }
    }
    private func load(more:Bool = false) async {
        let scope = company; busy = true; failure = nil
        defer { busy = false }
        do {
            if companies.isEmpty { companies = try await NovaAnalysisWorkspace.companyOptions(identity:identity) }
            let page = try JSONDecoder().decode(NovaProcessPage.self,from:await service.read(kind:kind,company:scope,parent:parent,query:search,offset:more ? rows.count : 0))
            guard company == scope else { return }
            rows = more ? rows + page.rows : page.rows; hasMore = page.has_more
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
    @Environment(\.dismiss) private var dismiss
    private var spec: NovaProcessKind { .get(kind) }
    private var service: NovaProcessService { .init(identity:identity) }
    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    NovaText(text:spec.title,style:.screenTitle)
                    if kind == "katip_contract" { NovaText(text:"Uzmanın sözleşme kaydıdır; resmî İSG-KATİP işlemi yapılmaz.",style:.meta) }
                    if kind == "work_permit" { NovaText(text:"Form hazırlama aracıdır. Çalışmayı başlatma veya saha onayı vermez.",style:.meta) }
                    if loading { ProgressView("Kayıt yükleniyor…") }
                    if let catalogue, !loading {
                        ForEach(spec.fields) { field in
                            VStack(alignment:.leading,spacing:6) {
                                NovaText(text:field.title + (field.required ? " *" : ""),style:.label)
                                control(field,catalogue)
                            }
                        }
                        Picker("Firma evrak kaydı",selection:$document) {
                            Text("Bağlantı yok").tag("")
                            ForEach(catalogue.documents) { Text($0.name).tag($0.id.uuidString) }
                        }
                        if catalogue.documents.isEmpty { NovaText(text:"Evrak Takibi bölümüne eklediğiniz firma kayıtları burada seçilebilir.",style:.meta) }
                        if kind == "annual_work_item" || kind == "board_decision" || kind == "site_observation" {
                            VStack(alignment: .leading, spacing: 8) {
                                NovaText(text: "İlgili süreç kaydı", style: .label)
                                NovaText(text: relatedID.isEmpty ? "Gerçek kayda bağlantı ekleyebilirsiniz." : (relatedTitle.isEmpty ? "Bağlı kayıt" : relatedTitle), style: .meta)
                                HStack {
                                    Button(relatedID.isEmpty ? "Kayıt seç" : "Değiştir") { choosingRelated = true }
                                    if !relatedID.isEmpty { Button("Bağlantıyı kaldır") { relatedKind = ""; relatedID = ""; relatedTitle = "" } }
                                }.disabled(!canWrite)
                            }
                        }
                        if row != nil {
                            if let child = spec.child {
                                Button(NovaProcessKind.get(child).title) { children = true }
                            }
                            Button { Task { await export() } } label:{Label("PDF indir",systemImage:"arrow.down.doc")}
                            Button("Excel indir") { Task { await export(excel: true) } }
                            Button("Kaydı sil",role:.destructive) { deletePrompt = true }.disabled(!canWrite)
                        }
                        NovaButton(label:busy ? "Kaydediliyor…" : "Kaydet",symbol:"checkmark",variant:.primary) { Task { await save() } }
                            .disabled(busy || !valid || !canWrite)
                    }
                    if let failure { Text(failure).font(NovaFont.font(.meta)) }
                }.padding(20).novaPopupContentSize().disabled(busy)
            }
        }
        .preference(key:NovaPopupBusyKey.self,value:busy)
        .task { await load() }
        .confirmationDialog("Kayıt aktif listeden kaldırılacak. Geçmişi korunur.",isPresented:$deletePrompt,titleVisibility:.visible) {
            Button("Sil",role:.destructive) { Task { await remove() } }
        }
        .sheet(isPresented:$children, onDismiss: { Task { await load() } }) {
            if let child = spec.child, let row {
                NovaPilotProcessGate(identity:identity,kind:child,initialCompany:company,parent:row.id,canWrite:canWrite,onBack:{children = false})
            }
        }
        .sheet(isPresented: $choosingRelated) {
            NovaProcessLinkPicker(identity: identity, company: company, excluding: record) { selected, selectedKind in
                relatedID = selected.id.uuidString; relatedKind = selectedKind; relatedTitle = selected.title
            }
        }
        .sheet(item:$pdf) { NovaFileShareSheet(url:$0) }
    }
    private var valid: Bool {
        spec.fields.filter(\.required).allSatisfy { field in
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
    @ViewBuilder private func control(_ field:NovaProcessField,_ cat:NovaProcessPage) -> some View {
        switch field.type {
        case "choice":
            Picker(field.title,selection:text(field.id)) {
                Text("Seçin").tag("")
                ForEach(field.choices.keys.sorted(),id:\.self) { Text(field.choices[$0] ?? $0).tag($0) }
            }
        case "workplaces","organizations":
            Picker(field.title,selection:text(field.id)) {
                Text("Seçin").tag("")
                ForEach(field.type == "workplaces" ? cat.workplaces : cat.organizations) { Text($0.name).tag($0.id.uuidString) }
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
                Toggle("Tarih belirt", isOn: Binding(get: { !(values[field.id]?.text.isEmpty ?? true) }, set: { enabled in
                    values[field.id] = enabled ? .string(field.type == "datetime" ? ISO8601DateFormatter().string(from: Date()) : NovaDayField.text(Date())) : .null
                }))
            }
            if field.required || !(values[field.id]?.text.isEmpty ?? true) {
                DatePicker(field.title, selection: dateBinding(field), displayedComponents: field.type == "datetime" ? [.date, .hourAndMinute] : [.date])
                    .labelsHidden()
            }
        default:
            TextField(field.title,text:text(field.id),axis:field.type == "multiline" || field.type == "lines" ? .vertical : .horizontal)
                .lineLimit(field.type == "multiline" || field.type == "lines" ? 3...8 : 1...1)
                .keyboardType(field.type == "number" ? .numberPad : .default)
        }
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
                    else { relatedTitle = "Bağlı kayıt artık erişilebilir değil. Bağlantıyı değiştirebilir veya kaldırabilirsiniz." }
                }
            } else {
                for field in spec.fields {
                    values[field.id] = field.type == "employees" ? .array([]) : .string("")
                }
                let today = NovaDayField.text(Date())
                for key in ["starts_on","planned_on","visited_on"] where spec.fields.contains(where:{$0.id == key}) { values[key] = .string(today) }
                if kind == "annual_work_plan" { values["plan_year"] = .string(String(Calendar.current.component(.year,from:Date()))) }
                if kind == "board" { values["applicability"] = .string("voluntary") }
                if spec.fields.contains(where:{$0.id == "state"}) { values["state"] = .string(kind == "board_decision" ? "open" : "planned") }
                if kind == "work_permit" { values["template_code"] = .string("general") }
                if let key = spec.parentKey, let parent { values[key] = .string(parent.uuidString) }
                if kind == "contractor_engagement", let parent { values["organization_id"] = .string(parent.uuidString) }
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
            } else { selected[field.id] = value.text.isEmpty && field.type != "employees" ? .null : value.rpc }
        }
        if let key = spec.parentKey { selected[key] = values[key]?.rpc ?? .null }
        if kind == "board" {
            if values["state"]?.text != "held" { selected["held_on"] = .null; selected["attendance"] = .null }
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
        do { _ = try await service.mutate(company:company,action:"save",payload:payload()); dismiss() }
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
                    NovaText(text: "İlgili kaydı seç", style: .cardTitle)
                    Picker("Kayıt türü", selection: $kind) {
                        ForEach(kinds, id: \.self) { Text(NovaProcessService.referenceTitle($0)).tag($0) }
                    }
                    HStack {
                        TextField("Kayıt ara", text: $query).onSubmit { Task { await load() } }
                        Button("Ara") { Task { await load() } }.disabled(loading)
                    }
                    if loading { ProgressView("Kayıtlar yükleniyor…") }
                    if let error { Text(error); Button("Yeniden dene") { Task { await load() } } }
                    ForEach(rows) { row in
                        Button { onSelect(row, kind); dismiss() } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).fixedSize(horizontal: false, vertical: true)
                                Text(String(row.date.prefix(10))).font(NovaFont.font(.meta))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        }.buttonStyle(.plain).disabled(loading)
                    }
                    if rows.isEmpty && !loading && error == nil { Text("Bu firmada uygun kayıt bulunamadı.") }
                    if hasMore { Button("Daha fazla") { Task { await load(more: true) } }.disabled(loading) }
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
