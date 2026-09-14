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
    @Environment(\.isNovaPopup) private var isNovaPopup
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
    @State private var query = ""
    private var filteredRows: [NovaDirectoryRow] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? rows : rows.filter { $0.title.localizedStandardContains(term) }
    }
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
                        HStack(spacing: 12) {
                            if !isNovaPopup { NovaBackButton { if let onBack { onBack() } else { dismiss() } }.accessibilityIdentifier("directory.back") }
                            NovaText(text: kind.title, style: .sectionTitle)
                        }
                        NovaHelpHint(text: kind.help)
                        HStack(spacing: 10) {
                            NovaCard(padding: 12) {
                                HStack(spacing: 8) {
                                    NovaIcon(symbol: "magnifyingglass", size: 16)
                                    TextField(RDLocalization.string("localizable.nova.directory.search", table: .localizable, fallback: "Kayıt ara…"), text: $query)
                                        .font(.custom("PlusJakartaSans-Medium", size: 14)).accessibilityIdentifier("directory.search")
                                }
                            }
                            if kind.isCatalog {
                                Toggle(isOn: $archived) { Image(systemName: "archivebox") }
                                    .toggleStyle(.button).buttonStyle(.bordered).frame(minHeight: 44)
                                    .accessibilityLabel(RDLocalization.string("localizable.nova.directory.screens.arsivdekileri.goster.885b965a", table: .localizable, fallback: "Arşivdekileri göster"))
                                    .onChange(of: archived) { _ in page = nil }
                            }
                        }
                        if let pending {
                            NovaCard(padding: 18) {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label(RDLocalization.string("localizable.nova.directory.pending.operation", table: .localizable, fallback: "Bekleyen işlem") + " · " + pending.kind.title, systemImage: "arrow.clockwise")
                                    NovaText(text: RDLocalization.string("localizable.nova.directory.screens.onceki.islemi.dogrulamadan.yeni.kayit.gondermeyi.87c426e4", table: .localizable, fallback: "Önceki işlemi doğrulamadan yeni kayıt göndermeyin."))
                                    NovaButton(label: RDLocalization.string("localizable.nova.directory.screens.bekleyen.islemi.tamamla.f65ddd7f", table: .localizable, fallback: "Bekleyen işlemi tamamla"), symbol: "arrow.clockwise", isEnabled: canWrite, isLoading: recovering) { recovering = true }
                                }
                            }
                        }
                        if !canWrite { NovaText(text: RDLocalization.string("localizable.nova.directory.screens.salt.okunur.kayit.gecmisiniz.korunuyor.2fdb9d4d", table: .localizable, fallback: "Salt okunur · kayıt geçmişiniz korunuyor."), style: .metaQuiet) }
                        NovaButton(label: kind == .employers ? RDLocalization.string("localizable.nova.directory.edit.employer.relationship", table: .localizable, fallback: "İşveren ilişkisini düzenle") : RDLocalization.string("localizable.nova.directory.new.record", table: .localizable, fallback: "Yeni kayıt"), symbol: "plus", isEnabled: canWrite && !loading && pending == nil && error == nil) { editor = Editor(row: kind == .employers ? rows.first : nil) }.accessibilityIdentifier("directory.add")
                        if let error { NovaCard(padding: 16) { VStack(alignment: .leading) { NovaText(text: error); NovaButton(label: RDLocalization.string("localizable.nova.directory.screens.tekrar.yukle.68942254", table: .localizable, fallback: "Tekrar yükle"), symbol: "arrow.clockwise", variant: .surface) { refresh = UUID() } } } }
                        ForEach(filteredRows) { row in
                            NovaCard(padding: 14) {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack { NovaIcon(symbol: kind.symbol, size: 24); NovaText(text: row.title, style: .cardTitle); Spacer(); if row.isArchived { NovaText(text: RDLocalization.string("localizable.nova.directory.screens.arsivde.65ab5741", table: .localizable, fallback: "Arşivde"), style: .metaQuiet) } }
                                    if let start = row.fields["starts_on"]?.text { NovaText(text: String(format: RDLocalization.string("localizable.nova.directory.engagement.range", table: .localizable, fallback: "%1$@ → %2$@"), start, row.fields["ends_before"]?.text ?? RDLocalization.string("localizable.nova.directory.engagement.ongoing", table: .localizable, fallback: "Devam ediyor")), style: .metaQuiet) }
                                    if let job = row.fields["department_name_snapshot"]?.text { NovaText(text: job, style: .metaQuiet) }
                                    HStack(spacing: 10) {
                                    if canWrite && (kind.isCatalog || kind == .engagements) { NovaButton(label: RDLocalization.string("localizable.nova.directory.screens.duzenle.7e356212", table: .localizable, fallback: "Düzenle"), symbol: "pencil", variant: .muted, isEnabled: !loading && error == nil && pending == nil) { editor = Editor(row: row) }.accessibilityIdentifier("directory.edit.\(row.id.uuidString.lowercased())") }
                                    if kind == .workplaces {
                                        NavigationLink { NovaDirectoryDestination(scope: scope, kind: .contexts, parent: row.id, client: client, canWrite: canWrite) } label: { Label(RDLocalization.string("localizable.nova.directory.history.short", table: .localizable, fallback: "Bilgi geçmişi"), systemImage: "clock.arrow.circlepath").font(.custom("PlusJakartaSans-Medium", size: 13)).frame(maxWidth: .infinity, minHeight: 44) }
                                    }
                                    if kind == .contractors {
                                        NavigationLink { NovaDirectoryDestination(scope: scope, kind: .engagements, parent: row.id, client: client, canWrite: canWrite) } label: { Label(RDLocalization.string("localizable.nova.directory.screens.calisilan.isyerleri.ab67bdf8", table: .localizable, fallback: "Çalışılan işyerleri"), systemImage: "building.2") }
                                    }
                                    }
                                }
                            }
                        }
                        if loading { ProgressView().frame(maxWidth: .infinity) }
                        if !loading && filteredRows.isEmpty && error == nil { NovaCard(padding: 14) { NovaText(text: query.isEmpty ? RDLocalization.string("localizable.nova.directory.screens.henuz.kayit.yok.282330e3", table: .localizable, fallback: "Henüz kayıt yok.") : RDLocalization.string("localizable.nova.directory.search.empty", table: .localizable, fallback: "Aramanızla eşleşen kayıt yok.")).frame(maxWidth: .infinity, minHeight: 24, alignment: .leading) } }
                        if let next { NovaButton(label: RDLocalization.string("localizable.nova.directory.screens.daha.fazla.f2dbe624", table: .localizable, fallback: "Daha fazla"), symbol: "chevron.down", variant: .surface, isEnabled: !loading) { page = next } }
                    }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 18)
                        .novaPopupContentSize()
                }
                .task(id: Key(scope: scope, kind: kind, parent: parent, page: page, archived: archived, refresh: refresh)) {
                    loading = true; error = nil; next = nil
                    if page == nil { rows = []; parentVersion = 0 }
                    do {
                        let p = try await client.pending(scope); try Task.checkCancellation(); pending = p
                        let result = try await client.read(scope, kind, parent, page, archived); try Task.checkCancellation()
                        rows = page == nil ? result.rows : rows + result.rows.filter { new in !rows.contains { $0.id == new.id } }
                        next = result.next; parentVersion = result.parentVersion ?? 0; loading = false
                        if !query.isEmpty, let cursor = result.next, cursor != page { page = cursor }
                    } catch { if !Task.isCancelled { loading = false; self.error = RDLocalization.string("localizable.nova.directory.error.records.not.loaded", table: .localizable, fallback: "Kayıtlar yüklenemedi. Erişiminizi ve bağlantınızı kontrol edin.") } }
                }
                .onChange(of: query) { value in
                    if !value.isEmpty, !loading, let next, next != page { page = next }
                }
                .task(id: recovering) {
                    guard canWrite, recovering, let pending else { return }
                    do { _ = try await client.save(pending); try Task.checkCancellation(); self.pending = nil; recovering = false; refresh = UUID() }
                    catch { if !Task.isCancelled { recovering = false; self.error = RDLocalization.string("localizable.nova.directory.error.not.verified.yet", table: .localizable, fallback: "İşlem henüz doğrulanamadı."); refresh = UUID() } }
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
    @Environment(\.isNovaPopup) private var isNovaPopup
    private var definition: [DirectoryField] {
        let name = DirectoryField(id: "name", label: RDLocalization.string("localizable.nova.directory.screens.ad.unvan.409140cb", table: .localizable, fallback: "Ad / unvan")), code = DirectoryField(id: "code", label: "Kod")
        let workplace = DirectoryField(id: "workplace_id", label: RDLocalization.string("localizable.nova.directory.screens.isyeri.dad72a5a", table: .localizable, fallback: "İşyeri"), choices: .workplaces)
        let org = DirectoryField(id: "organization_id", label: RDLocalization.string("localizable.nova.directory.screens.dis.firma.193c52c0", table: .localizable, fallback: "Dış firma"), choices: .contractors)
        let start = DirectoryField(id: "starts_on", label: RDLocalization.string("localizable.nova.directory.screens.gecerlilik.baslangici.yyyy.aa.gg.d31f4d4c", table: .localizable, fallback: "Geçerlilik başlangıcı · YYYY-AA-GG"))
        switch kind {
        case .workplaces: return [name,code,.init(id: "address", label: RDLocalization.string("localizable.nova.directory.screens.adres.0d741be0", table: .localizable, fallback: "Adres"), nullable: true)]
        case .departments: return [name,code,workplace,.init(id: "parent_id", label: RDLocalization.string("localizable.nova.directory.screens.ust.departman.8976d96f", table: .localizable, fallback: "Üst departman"), choices: .departments, nullable: true)]
        case .jobs: return [name,code,.init(id: "description", label: RDLocalization.string("localizable.nova.directory.screens.gorev.aciklamasi.106374f8", table: .localizable, fallback: "Görev açıklaması"), nullable: true)]
        case .contractors: return [name,code,.init(id: "relationship", label: RDLocalization.string("localizable.nova.directory.screens.iliski.turu.795a1713", table: .localizable, fallback: "İlişki türü"))]
        case .engagements: return [org,workplace,start,.init(id: "ends_before", label: RDLocalization.string("localizable.nova.directory.screens.bitis.haric.yyyy.aa.gg.377bce27", table: .localizable, fallback: "Bitiş (hariç) · YYYY-AA-GG"), nullable: true),.init(id: "description", label: RDLocalization.string("localizable.nova.directory.screens.yapilan.is.403402ce", table: .localizable, fallback: "Yapılan iş"), nullable: true)]
        case .contexts: return [start,.init(id: "previous_id", label: RDLocalization.string("localizable.nova.directory.screens.onceki.donem.d174ff93", table: .localizable, fallback: "Önceki dönem"), nullable: true),.init(id: "timezone", label: RDLocalization.string("localizable.nova.directory.screens.saat.dilimi.or.europe.istanbul.d7de0b12", table: .localizable, fallback: "Saat dilimi · ör. Europe/Istanbul")),.init(id: "jurisdiction", label: RDLocalization.string("localizable.nova.directory.screens.mevzuat.bolgesi.91602319", table: .localizable, fallback: "Mevzuat bölgesi")),.init(id: "hazard_class", label: RDLocalization.string("localizable.nova.directory.screens.tehlike.sinifi.95aff6af", table: .localizable, fallback: "Tehlike sınıfı")),.init(id: "industry_code", label: RDLocalization.string("localizable.nova.directory.screens.faaliyet.kodu.65b694cf", table: .localizable, fallback: "Faaliyet kodu"), nullable: true),.init(id: "evidence_note", label: RDLocalization.string("localizable.nova.directory.screens.baglam.degisikliginin.dayanagi.52cc1a59", table: .localizable, fallback: "Bağlam değişikliğinin dayanağı"))]
        case .assignments: return [workplace,.init(id: "department_id", label: "Departman", choices: .departments),.init(id: "job_role_id", label: RDLocalization.string("localizable.nova.directory.screens.gorev.unvan.e8ecd075", table: .localizable, fallback: "Görev / unvan"), choices: .jobs),start,.init(id: "previous_id", label: RDLocalization.string("localizable.nova.directory.screens.onceki.gorevlendirme.f27c09cd", table: .localizable, fallback: "Önceki görevlendirme"), nullable: true),.init(id: "reason", label: RDLocalization.string("localizable.nova.directory.screens.degisiklik.nedeni.saglik.bilgisi.yazmayin.3e3e4fa2", table: .localizable, fallback: "Değişiklik nedeni · sağlık bilgisi yazmayın"), nullable: true)]
        case .employers: return [.init(id: "organization_id", label: RDLocalization.string("localizable.nova.directory.screens.isveren.bos.ise.ana.firma.596cbfb9", table: .localizable, fallback: "İşveren · boş ise ana firma"), choices: .contractors, nullable: true)]
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if !isNovaPopup { NovaBackButton(isEnabled: !submitting, action: onBack).accessibilityIdentifier("directory.editor.back") }
                    NovaText(text: kind.title, style: .sectionTitle)
                }
                if [.contexts, .assignments].contains(kind) { NovaCard(padding: 16) { NovaText(text: RDLocalization.string("localizable.nova.directory.screens.onceki.donemi.secerseniz.bu.kayit.baslangic.tari.aa072143", table: .localizable, fallback: "Önceki dönemi seçerseniz bu kayıt başlangıç tarihinde bölünür; eski bilgiler korunur. Bitiş günü döneme dahil değildir."), style: .metaQuiet) } }
                if kind == .engagements && original != nil { NovaText(text: RDLocalization.string("localizable.nova.directory.screens.firma.isyeri.ve.baslangic.degismez.bitisi.ve.aci.5e2c5767", table: .localizable, fallback: "Firma, işyeri ve başlangıç değişmez. Bitişi ve açıklamayı düzenleyebilirsiniz."), style: .metaQuiet) }
                ForEach(definition) { field in
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack { NovaIcon(symbol: field.choices?.symbol ?? "pencil", size: 20); NovaText(text: field.label, style: .cardTitle) }
                            if field.choices != nil || field.id == "previous_id" {
                                Button { expanded = expanded == field.id ? nil : field.id } label: {
                                    HStack { NovaText(text: options[field.id]?.first(where: { $0.id.uuidString.lowercased() == fields[field.id] })?.title ?? (fields[field.id, default: ""].isEmpty ? "Seçilmedi" : "Seçildi")); Spacer(); NovaIcon(symbol: "chevron.down", size: 16) }
                                }.buttonStyle(.plain).accessibilityIdentifier("directory.field.\(field.id)")
                                if expanded == field.id {
                                    if field.nullable { Button(RDLocalization.string("localizable.nova.directory.screens.secimi.kaldir.0db468a9", table: .localizable, fallback: "Seçimi kaldır")) { fields[field.id] = ""; expanded = nil } }
                                    ForEach(visibleOptions(field)) { option in
                                        Button {
                                            fields = NovaDirectoryFormRules.selecting(field.id, value: option.id.uuidString.lowercased(), in: fields)
                                            expanded = nil
                                        } label: { HStack { NovaIcon(symbol: "checkmark.circle", size: 20); NovaText(text: option.title + (option.fields["starts_on"]?.text.map { " · " + $0 + " → " + (option.fields["ends_before"]?.text ?? RDLocalization.string("localizable.nova.directory.engagement.ongoing", table: .localizable, fallback: "Devam ediyor")) } ?? "")) }.frame(minHeight: 44) }.accessibilityIdentifier("directory.option.\(field.id).\(option.id.uuidString.lowercased())")
                                    }
                                    if optionCursor[field.id] != nil { Button(RDLocalization.string("localizable.nova.directory.screens.diger.kayitlar.65cf0945", table: .localizable, fallback: "Diğer kayıtlar")) { loadingMore = field.id }.disabled(loadingMore != nil || optionsLoading) }
                                }
                            } else if field.id == "relationship" {
                                Picker(field.label, selection: binding(field.id)) { Text(RDLocalization.string("localizable.nova.directory.screens.alt.isveren.963bc955", table: .localizable, fallback: "Alt işveren")).tag("subcontractor"); Text(RDLocalization.string("localizable.nova.directory.screens.yuklenici.3d11aad1", table: .localizable, fallback: "Yüklenici")).tag("contractor"); Text(RDLocalization.string("localizable.nova.directory.screens.tedarikci.dfce7f7e", table: .localizable, fallback: "Tedarikçi")).tag("supplier"); Text(RDLocalization.string("localizable.nova.directory.screens.diger.fbcfe757", table: .localizable, fallback: "Diğer")).tag("other") }.pickerStyle(.segmented)
                            } else if field.id == "hazard_class" {
                                Picker(field.label, selection: binding(field.id)) { Text(RDLocalization.string("localizable.nova.directory.screens.secin.5519ecdd", table: .localizable, fallback: "Seçin")).tag(""); Text("Az").tag("low"); Text("Tehlikeli").tag("medium"); Text(RDLocalization.string("localizable.nova.directory.screens.cok.5c09224d", table: .localizable, fallback: "Çok")).tag("high") }.pickerStyle(.segmented)
                            } else { TextField(field.label, text: binding(field.id)).font(.custom("PlusJakartaSans-Medium", size: 15)).textInputAutocapitalization(["starts_on", "ends_before", "timezone", "code"].contains(field.id) ? .never : .sentences).autocorrectionDisabled().focused($focusedField, equals: field.id).submitLabel(.done).onSubmit { focusedField = nil }.accessibilityIdentifier("directory.field.\(field.id)") }
                        }.disabled(pending != nil || (kind == .engagements && original != nil && ["organization_id", "workplace_id", "starts_on"].contains(field.id)))
                    }
                }
                if original != nil && kind.isCatalog { Toggle(RDLocalization.string("localizable.nova.directory.screens.arsivle.16066149", table: .localizable, fallback: "Arşivle"), isOn: $archived).disabled(pending != nil) }
                if optionsLoading || loadingMore != nil { ProgressView() }
                if optionsFailed { NovaButton(label: RDLocalization.string("localizable.nova.directory.screens.secenekleri.tekrar.yukle.df9dc016", table: .localizable, fallback: "Seçenekleri tekrar yükle"), symbol: "arrow.clockwise", variant: .surface, isEnabled: !optionsLoading && pending == nil) { optionsRefresh = UUID() }.accessibilityIdentifier("directory.options.retry") }
                if let message { NovaText(text: message).accessibilityIdentifier("directory.error") }
                NovaButton(label: pending == nil ? RDLocalization.string("localizable.nova.directory.save", table: .localizable, fallback: "Kaydet") : RDLocalization.string("localizable.nova.directory.recheck.same.operation", table: .localizable, fallback: "Aynı işlemi tekrar kontrol et"), symbol: pending == nil ? "checkmark" : "arrow.clockwise", isEnabled: pending != nil || (!optionsLoading && !optionsFailed && loadingMore == nil), isLoading: submitting) { begin() }.accessibilityIdentifier("directory.save")
            }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 18)
                .novaPopupContentSize()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(NovaKeyboardDismissArea())
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
                        self.pending = nil; message = RDLocalization.string("localizable.nova.directory.error.record.rejected", table: .localizable, fallback: "Kayıt kabul edilmedi. Bilgileri kontrol edin; kayıt değiştiyse geri dönüp güncel halini yükleyin.")
                    } else { message = RDLocalization.string("localizable.nova.directory.error.operation.unverified", table: .localizable, fallback: "İşlem doğrulanamadı. Bilgileri değiştirmeden aynı işlemi kontrol edin veya geri dönüp bekleyen işlem durumunu yenileyin.") }
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
        } catch { if !Task.isCancelled { optionsFailed = true; message = RDLocalization.string("localizable.nova.directory.error.options.not.loaded", table: .localizable, fallback: "Seçenekler yüklenemedi. Bilgileriniz korunuyor; tekrar yükleyin.") } }
    }
    private func begin() {
        if pending != nil { submitting = true; return }
        var body: [String: NovaDirectoryValue] = [:]
        for field in definition {
            let text = fields[field.id, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty && !field.nullable { message = String(format: RDLocalization.string("localizable.nova.directory.field.required", table: .localizable, fallback: "%@ gerekli."), field.label); return }
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
