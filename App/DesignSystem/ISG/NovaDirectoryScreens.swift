import SwiftUI

/// Catalog forms share the reference canvas/cards; dates appear only in advanced history flows.
struct NovaDirectoryDestination: View {
    let scope: NovaPersonnelScope
    let kind: NovaDirectoryKind
    var parent: UUID? = nil
    let client: NovaDirectoryClient
    var onBack: (() -> Void)? = nil
    var canWrite = true
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [NovaDirectoryRow] = []
    @State private var next: UUID?
    @State private var page: UUID?
    @State private var parentVersion: Int64 = 0
    @State private var archived = false
    @State private var refresh = UUID()
    @State private var loading = true
    @State private var error: String?
    @State private var editor: Editor?
    @State private var pending: NovaDirectoryIntent?
    @State private var recovering = false
    private struct Editor: Identifiable { let id = UUID(); let row: NovaDirectoryRow? }
    private struct Key: Equatable { let scope: NovaPersonnelScope; let kind: NovaDirectoryKind; let parent: UUID?; let page: UUID?; let archived: Bool; let refresh: UUID }
    var body: some View {
        NovaPageSurface {
            if let editor, canWrite {
                NovaDirectoryEditor(scope: scope, kind: kind, parent: parent, parentVersion: parentVersion, original: editor.row, history: rows, client: client,
                    onBack: { self.editor = nil; refresh = UUID() }, onSaved: { self.editor = nil; page = nil; refresh = UUID() }).id(editor.id)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        HStack { Button { if let onBack { onBack() } else { dismiss() } } label: { NovaIcon(symbol: "chevron.left", size: 24).frame(width: 44, height: 44) }.accessibilityLabel("Geri").accessibilityIdentifier("directory.back"); NovaText(text: kind.title, style: .screenTitle) }
                        if kind.isCatalog { Toggle("Arşivdekileri göster", isOn: $archived).onChange(of: archived) { _ in page = nil } }
                        if let pending {
                            NovaCard(padding: 18) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("Bekleyen işlem · \(pending.kind.title)", systemImage: "arrow.clockwise")
                                    NovaText(text: "Önceki işlemi doğrulamadan yeni kayıt göndermeyin.")
                                    NovaButton(label: "Bekleyen işlemi tamamla", symbol: "arrow.clockwise", isEnabled: canWrite, isLoading: recovering) { recovering = true }
                                }
                            }
                        }
                        if !canWrite { NovaText(text: "Salt okunur · kayıt geçmişiniz korunuyor.", style: .metaQuiet) }
                        NovaButton(label: kind == .employers ? "İşveren ilişkisini düzenle" : "Yeni kayıt", symbol: "plus", isEnabled: canWrite && !loading && pending == nil && error == nil) { editor = Editor(row: kind == .employers ? rows.first : nil) }.accessibilityIdentifier("directory.add")
                        if let error { NovaCard(padding: 16) { VStack(alignment: .leading) { NovaText(text: error); NovaButton(label: "Tekrar yükle", symbol: "arrow.clockwise", variant: .surface) { refresh = UUID() } } } }
                        ForEach(rows) { row in
                            NovaCard(padding: 18) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack { NovaIcon(symbol: kind.symbol, size: 24); NovaText(text: row.title, style: .cardTitle); Spacer(); if row.isArchived { NovaText(text: "Arşivde", style: .metaQuiet) } }
                                    if let code = row.fields["code"]?.text { NovaText(text: code, style: .metaQuiet) }
                                    if let start = row.fields["starts_on"]?.text { NovaText(text: "\(start) → \(row.fields["ends_before"]?.text ?? "Devam ediyor")", style: .metaQuiet) }
                                    if let job = row.fields["department_name_snapshot"]?.text { NovaText(text: job, style: .metaQuiet) }
                                    if canWrite && (kind.isCatalog || kind == .engagements) { NovaButton(label: "Düzenle", symbol: "pencil", variant: .surface, isEnabled: !loading && error == nil && pending == nil) { editor = Editor(row: row) }.accessibilityIdentifier("directory.edit.\(row.id.uuidString.lowercased())") }
                                    if kind == .workplaces {
                                        NavigationLink { NovaDirectoryDestination(scope: scope, kind: .contexts, parent: row.id, client: client, canWrite: canWrite) } label: { Label("Tarihli bağlam", systemImage: "clock.arrow.circlepath") }
                                    }
                                    if kind == .contractors {
                                        NavigationLink { NovaDirectoryDestination(scope: scope, kind: .engagements, parent: row.id, client: client, canWrite: canWrite) } label: { Label("Çalışılan işyerleri", systemImage: "building.2") }
                                    }
                                }
                            }
                        }
                        if loading { ProgressView().frame(maxWidth: .infinity) }
                        if !loading && rows.isEmpty && error == nil { NovaCard(padding: 18) { NovaText(text: "Henüz kayıt yok.") } }
                        if let next { NovaButton(label: "Daha fazla", symbol: "chevron.down", variant: .surface, isEnabled: !loading) { page = next } }
                    }.padding(18)
                }
                .task(id: Key(scope: scope, kind: kind, parent: parent, page: page, archived: archived, refresh: refresh)) {
                    loading = true; error = nil; next = nil
                    if page == nil { rows = []; parentVersion = 0 }
                    do {
                        let p = try await client.pending(scope); try Task.checkCancellation(); pending = p
                        let result = try await client.read(scope, kind, parent, page, archived); try Task.checkCancellation()
                        rows = page == nil ? result.rows : rows + result.rows.filter { new in !rows.contains { $0.id == new.id } }
                        next = result.next; parentVersion = result.parentVersion ?? 0; loading = false
                    } catch { if !Task.isCancelled { loading = false; self.error = "Kayıtlar yüklenemedi. Erişiminizi ve bağlantınızı kontrol edin." } }
                }
                .task(id: recovering) {
                    guard canWrite, recovering, let pending else { return }
                    do { _ = try await client.save(pending); try Task.checkCancellation(); self.pending = nil; recovering = false; refresh = UUID() }
                    catch { if !Task.isCancelled { recovering = false; self.error = "İşlem henüz doğrulanamadı."; refresh = UUID() } }
                }
            }
        }
    }
}

private struct DirectoryField: Identifiable {
    let id: String; let label: String; var choices: NovaDirectoryKind? = nil; var nullable = false
}
private struct NovaDirectoryEditor: View {
    let scope: NovaPersonnelScope; let kind: NovaDirectoryKind; let parent: UUID?; let parentVersion: Int64
    let original: NovaDirectoryRow?; let history: [NovaDirectoryRow]; let client: NovaDirectoryClient
    let onBack: () -> Void; let onSaved: () -> Void
    @State private var fields: [String: String] = [:]
    @State private var options: [String: [NovaDirectoryRow]] = [:]
    @State private var optionCursor: [String: UUID] = [:]
    @State private var expanded: String?
    @State private var archived = false
    @State private var pending: NovaDirectoryIntent?
    @State private var submitting = false
    @State private var message: String?
    @State private var optionsLoading = true
    @State private var optionsFailed = false
    @State private var optionsRefresh = UUID()
    @State private var loadingMore: String?
    @FocusState private var focusedField: String?
    private var definition: [DirectoryField] {
        let name = DirectoryField(id: "name", label: "Ad / unvan"), code = DirectoryField(id: "code", label: "Kod")
        let workplace = DirectoryField(id: "workplace_id", label: "İşyeri", choices: .workplaces)
        let org = DirectoryField(id: "organization_id", label: "Dış firma", choices: .contractors)
        let start = DirectoryField(id: "starts_on", label: "Geçerlilik başlangıcı · YYYY-AA-GG")
        switch kind {
        case .workplaces: return [name,code,.init(id: "address", label: "Adres", nullable: true)]
        case .departments: return [name,code,workplace,.init(id: "parent_id", label: "Üst departman", choices: .departments, nullable: true)]
        case .jobs: return [name,code,.init(id: "description", label: "Görev açıklaması", nullable: true)]
        case .contractors: return [name,code,.init(id: "relationship", label: "İlişki türü")]
        case .engagements: return [org,workplace,start,.init(id: "ends_before", label: "Bitiş (hariç) · YYYY-AA-GG", nullable: true),.init(id: "description", label: "Yapılan iş", nullable: true)]
        case .contexts: return [start,.init(id: "previous_id", label: "Önceki dönem", nullable: true),.init(id: "timezone", label: "Saat dilimi · ör. Europe/Istanbul"),.init(id: "jurisdiction", label: "Mevzuat bölgesi"),.init(id: "hazard_class", label: "Tehlike sınıfı"),.init(id: "industry_code", label: "Faaliyet kodu", nullable: true),.init(id: "evidence_note", label: "Bağlam değişikliğinin dayanağı")]
        case .assignments: return [workplace,.init(id: "department_id", label: "Departman", choices: .departments),.init(id: "job_role_id", label: "Görev / unvan", choices: .jobs),start,.init(id: "previous_id", label: "Önceki görevlendirme", nullable: true),.init(id: "reason", label: "Değişiklik nedeni · sağlık bilgisi yazmayın", nullable: true)]
        case .employers: return [.init(id: "organization_id", label: "İşveren · boş ise ana firma", choices: .contractors, nullable: true)]
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Button(action: onBack) { NovaIcon(symbol: "chevron.left", size: 24).frame(width: 44, height: 44) }.disabled(submitting).accessibilityLabel("Geri").accessibilityIdentifier("directory.editor.back"); NovaText(text: kind.title, style: .screenTitle) }
                if [.contexts, .assignments].contains(kind) { NovaCard(padding: 16) { NovaText(text: "Önceki dönemi seçerseniz bu kayıt başlangıç tarihinde bölünür; eski bilgiler korunur. Bitiş günü döneme dahil değildir.", style: .metaQuiet) } }
                if kind == .engagements && original != nil { NovaText(text: "Firma, işyeri ve başlangıç değişmez. Bitişi ve açıklamayı düzenleyebilirsiniz.", style: .metaQuiet) }
                ForEach(definition) { field in
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { NovaIcon(symbol: field.choices?.symbol ?? "pencil", size: 20); NovaText(text: field.label, style: .cardTitle) }
                            if field.choices != nil || field.id == "previous_id" {
                                Button { expanded = expanded == field.id ? nil : field.id } label: {
                                    HStack { NovaText(text: options[field.id]?.first(where: { $0.id.uuidString.lowercased() == fields[field.id] })?.title ?? (fields[field.id, default: ""].isEmpty ? "Seçilmedi" : "Seçildi")); Spacer(); NovaIcon(symbol: "chevron.down", size: 16) }
                                }.buttonStyle(.plain).accessibilityIdentifier("directory.field.\(field.id)")
                                if expanded == field.id {
                                    if field.nullable { Button("Seçimi kaldır") { fields[field.id] = ""; expanded = nil } }
                                    ForEach(visibleOptions(field)) { option in
                                        Button {
                                            fields = NovaDirectoryFormRules.selecting(field.id, value: option.id.uuidString.lowercased(), in: fields)
                                            expanded = nil
                                        } label: { HStack { NovaIcon(symbol: "checkmark.circle", size: 20); NovaText(text: option.title + (option.fields["starts_on"]?.text.map { " · " + $0 + " → " + (option.fields["ends_before"]?.text ?? "Devam ediyor") } ?? "")) }.frame(minHeight: 44) }.accessibilityIdentifier("directory.option.\(field.id).\(option.id.uuidString.lowercased())")
                                    }
                                    if optionCursor[field.id] != nil { Button("Diğer kayıtlar") { loadingMore = field.id }.disabled(loadingMore != nil || optionsLoading) }
                                }
                            } else if field.id == "relationship" {
                                Picker(field.label, selection: binding(field.id)) { Text("Alt işveren").tag("subcontractor"); Text("Yüklenici").tag("contractor"); Text("Tedarikçi").tag("supplier"); Text("Diğer").tag("other") }.pickerStyle(.segmented)
                            } else if field.id == "hazard_class" {
                                Picker(field.label, selection: binding(field.id)) { Text("Seçin").tag(""); Text("Az").tag("low"); Text("Tehlikeli").tag("medium"); Text("Çok").tag("high") }.pickerStyle(.segmented)
                            } else { TextField(field.label, text: binding(field.id)).font(.custom("PlusJakartaSans-Medium", size: 15)).textInputAutocapitalization(["starts_on", "ends_before", "timezone", "code"].contains(field.id) ? .never : .sentences).autocorrectionDisabled().focused($focusedField, equals: field.id).submitLabel(.done).onSubmit { focusedField = nil }.accessibilityIdentifier("directory.field.\(field.id)") }
                        }.disabled(pending != nil || (kind == .engagements && original != nil && ["organization_id", "workplace_id", "starts_on"].contains(field.id)))
                    }
                }
                if original != nil && kind.isCatalog { Toggle("Arşivle", isOn: $archived).disabled(pending != nil) }
                if optionsLoading || loadingMore != nil { ProgressView() }
                if optionsFailed { NovaButton(label: "Seçenekleri tekrar yükle", symbol: "arrow.clockwise", variant: .surface, isEnabled: !optionsLoading && pending == nil) { optionsRefresh = UUID() }.accessibilityIdentifier("directory.options.retry") }
                if let message { NovaText(text: message).accessibilityIdentifier("directory.error") }
                NovaButton(label: pending == nil ? "Kaydet" : "Aynı işlemi tekrar kontrol et", symbol: pending == nil ? "checkmark" : "arrow.clockwise", isEnabled: pending != nil || (!optionsLoading && !optionsFailed && loadingMore == nil), isLoading: submitting) { begin() }.accessibilityIdentifier("directory.save")
            }.padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .task {
            fields = original?.fields.reduce(into: [:]) { result, entry in result[entry.key] = entry.value.text ?? "" } ?? [:]
            if kind == .jobs { fields["name"] = original?.fields["title"]?.text ?? "" }
            if kind == .employers { fields["organization_id"] = original?.fields["employer_org_id"]?.text ?? "" }
            if kind == .engagements && original == nil { fields["organization_id"] = parent?.uuidString.lowercased() ?? "" }
            if original == nil { fields["code"] = String(UUID().uuidString.prefix(8)); fields["relationship"] = "other" }
            archived = original?.isArchived ?? false
        }
        .task(id: optionsRefresh) {
            optionsLoading = true; optionsFailed = false; message = nil
            for field in definition {
                if Task.isCancelled { return }
                if field.id == "previous_id" { await loadOptions(field, more: false); continue }
                if field.choices != nil { await loadOptions(field, more: false) }
            }
            if !Task.isCancelled { optionsLoading = false }
        }
        .task(id: loadingMore) {
            guard let field = definition.first(where: { $0.id == loadingMore }) else { return }
            await loadOptions(field, more: true)
            if !Task.isCancelled { loadingMore = nil }
        }
        .task(id: submitting) {
            guard submitting, let pending else { return }
            do { _ = try await client.save(pending); try Task.checkCancellation(); submitting = false; onSaved() }
            catch {
                if !Task.isCancelled {
                    submitting = false
                    if let failure = error as? NovaPersonnelFailure, failure == .validation || failure == .conflict {
                        self.pending = nil; message = "Kayıt kabul edilmedi. Bilgileri kontrol edin; kayıt değiştiyse geri dönüp güncel halini yükleyin."
                    } else { message = "İşlem doğrulanamadı. Bilgileri değiştirmeden aynı işlemi kontrol edin veya geri dönüp bekleyen işlem durumunu yenileyin." }
                }
            }
        }
    }
    private func binding(_ key: String) -> Binding<String> { .init(get: { fields[key, default: ""] }, set: { fields[key] = $0 }) }
    private func visibleOptions(_ field: DirectoryField) -> [NovaDirectoryRow] {
        NovaDirectoryFormRules.allowedOptions(options[field.id, default: []], field: field.id, workplace: fields["workplace_id"], originalID: original?.id)
    }
    private func loadOptions(_ field: DirectoryField, more: Bool) async {
        guard let kind = field.choices ?? (field.id == "previous_id" ? self.kind : nil) else { return }
        do {
            let result = try await client.read(scope, kind, field.id == "previous_id" ? parent : nil, more ? optionCursor[field.id] : nil, false); try Task.checkCancellation()
            let existing = more ? options[field.id, default: []] : []
            options[field.id] = existing + result.rows.filter { row in !existing.contains(where: { $0.id == row.id }) }
            optionCursor[field.id] = result.next
        } catch { if !Task.isCancelled { optionsFailed = true; message = "Seçenekler yüklenemedi. Bilgileriniz korunuyor; tekrar yükleyin." } }
    }
    private func begin() {
        if pending != nil { submitting = true; return }
        var body: [String: NovaDirectoryValue] = [:]
        for field in definition {
            let text = fields[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && !field.nullable { message = "\(field.label) gerekli."; return }
            body[field.id] = text.isEmpty && field.nullable && !["description","reason"].contains(field.id) ? .null : .string(text)
        }
        if let error = NovaDirectoryFormRules.validation(kind: kind, fields: fields, options: options, originalID: original?.id) { message = error; return }
        if kind.isCatalog { body["is_archived"] = .bool(archived) }
        if kind == .contexts { guard let parent else { return }; body["workplace_id"] = .string(parent.uuidString.lowercased()) }
        if kind == .assignments { guard let parent else { return }; body["employee_id"] = .string(parent.uuidString.lowercased()) }
        let expected = [.contexts,.assignments].contains(kind) ? parentVersion : original?.version ?? 0
        pending = .init(scope: scope, kind: kind, operationID: UUID(), mutationID: UUID(), entityID: kind == .employers ? parent : original?.id, expectedVersion: expected, body: body)
        submitting = true; message = nil
    }
}
