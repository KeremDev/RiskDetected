import SwiftUI

struct NovaTrainingSessionEditor: View {
    let identity: NovaSessionIdentity
    let personnel: NovaPersonnelClient
    let companies: [NovaPilotCompanySummary]
    let initialCompany: UUID?
    let catalog: [NovaTrainingCatalog]
    let original: NovaTrainingSession?
    let canWrite: Bool
    let writableCompanies: Set<UUID>
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.novaCelebrate) private var celebrate
    @State private var choices: [NovaTrainingCatalog] = []
    @State private var selectedCatalog: UUID?
    @State private var selected: [UUID: Set<UUID>] = [:]
    @State private var employees: [UUID: [NovaEmployeeRow]] = [:]
    @State private var trainer = ""
    @State private var held = Date()
    @State private var method = "face_to_face"
    @State private var location = ""
    @State private var notes = ""
    @State private var search = ""
    @State private var busy = false
    @State private var loaded = false
    @State private var uncertain = false
    @State private var error: String?
    @State private var deleteConfirmation = false
    @State private var custom = false
    @State private var customTitle = ""
    @State private var customMinutes = "60"
    @State private var customMonths = "12"
    @State private var export: NovaTrainingPDFDocument?
    @State private var exporting = false
    private var service: NovaTrainingSessionService { .init(identity: identity) }
    private var item: NovaTrainingCatalog? { choices.first { $0.id == selectedCatalog } }
    private var formatter: DateFormatter {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Istanbul"); f.dateFormat = "yyyy-MM-dd"; return f
    }
    private var writable: Bool { canWrite && loaded && !busy && !uncertain }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label(original == nil ? "Eğitim Ekle" : "Eğitim Düzenle", systemImage: "graduationcap").font(NovaFont.font(.cardTitle))
                form
                participants
                NovaHelpHint(text: "Kaydettiğinizde seçilen personelin bu eğitime katıldığını beyan etmiş olursunuz. Ayrı planlama veya yoklama adımı yoktur.")
                if let error { NovaHelpHint(text: error) }
                if !loaded { ProgressView(); if error != nil { Button("Tekrar dene") { Task { await load() } } } }
                if uncertain {
                    NovaButton(label: "Bekleyen işlemi tamamla", symbol: "arrow.clockwise", isEnabled: !busy) { Task { await retry() } }
                } else {
                    NovaButton(label: "Eğitimi kaydet", symbol: "checkmark", isEnabled: writable && item != nil, isLoading: busy) { Task { await save() } }
                    if let original {
                        NovaButton(label: "Kayıt belgesi indir (PDF)", symbol: "arrow.down.doc", variant: .surface) {
                            export = NovaTrainingPDFDocument(session: original); exporting = true
                        }
                        NovaText(text: "PDF son kaydedilen sürümden üretilir. İmzalı resmî sertifika yerine geçmez.", style: .metaQuiet)
                        NovaButton(label: "Eğitimi sil", symbol: "trash", variant: .danger, isEnabled: writable) { deleteConfirmation = true }
                    }
                }
            }.padding(18).novaPopupContentSize()
        }.scrollDismissesKeyboard(.interactively)
            .task { await load() }
            .alert("Eğitim silinsin mi?", isPresented: $deleteConfirmation) {
                Button("Sil", role: .destructive) { Task { await remove() } }
                Button("Vazgeç", role: .cancel) {}
            } message: { Text("Tüm bağlı firmaların eğitim listesinden kaldırılır. Önceki sürüm kayıtları korunur.") }
            .fileExporter(isPresented: $exporting, document: export, contentType: .pdf, defaultFilename: "Egitim-kaydi") { result in
                if case .failure(let e) = result { error = e.localizedDescription }
            }
    }
    private var form: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                Menu {
                    ForEach(choices) { value in Button(value.title) { selectedCatalog = value.id } }
                } label: {
                    HStack { Image(systemName: "books.vertical"); Text(item?.title ?? "Kayıtlı eğitim seçin *"); Spacer(); Image(systemName: "chevron.down") }
                }.tint(.primary)
                Button { custom.toggle() } label: { Label("Yeni eğitim başlığı oluştur", systemImage: "plus") }.font(NovaFont.font(.body))
                if custom {
                    field("Eğitim başlığı *", "graduationcap", $customTitle)
                    field("Süre · dakika *", "clock", $customMinutes).keyboardType(.numberPad)
                    field("Geçerlilik · ay (0: tekrar tarihi yok)", "calendar", $customMonths).keyboardType(.numberPad)
                    Button("Başlığı kaydet") { Task { await saveCatalog() } }.disabled(!writable || selected.isEmpty)
                }
                Divider()
                Picker("Yöntem", selection: $method) {
                    Text("Yüz yüze").tag("face_to_face"); Text("Online").tag("online"); Text("Karma").tag("mixed")
                }.pickerStyle(.segmented)
                if item?.code == "basic" || item?.code == "renewal" {
                    Text("Karma: ortak konular online, işyerine özgü bölüm yüz yüze. İşyerine özgü içerik her firma için ayrıca sağlanmalıdır.").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                }
                field("Eğitmen *", "person", $trainer)
                DatePicker("Eğitimin tamamlandığı tarih", selection: $held, in: ...Date(), displayedComponents: .date).font(NovaFont.font(.body))
                field("Yer / bağlantı", "mappin.and.ellipse", $location)
                TextField("Notlar", text: $notes, axis: .vertical).lineLimit(2...4).font(NovaFont.font(.body))
            }.disabled(!writable)
        }
    }
    private var participants: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("Firmalar ve katılımcılar", systemImage: "person.2").font(NovaFont.font(.body))
                TextField("Personel ara…", text: $search).font(NovaFont.font(.body))
                ForEach(companies) { company in
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            if selected[company.id] != nil { selected.removeValue(forKey: company.id) }
                            else { selected[company.id] = [] }
                        } label: {
                            HStack { Image(systemName: selected[company.id] == nil ? "circle" : "checkmark.circle"); Text(company.name); Spacer() }
                        }.buttonStyle(.plain).font(NovaFont.font(.body)).disabled(!writable || !writableCompanies.contains(company.id))
                        if let ids = selected[company.id] {
                            if let rule = item?.rules[company.hazard_class] {
                                Text("\(rule.minutes / 60) sa \(rule.minutes % 60) dk · \(validity(rule.months))")
                                    .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                            }
                            ForEach((employees[company.id] ?? []).filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { person in
                                Button {
                                    if ids.contains(person.id) { selected[company.id]?.remove(person.id) }
                                    else { selected[company.id]?.insert(person.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: ids.contains(person.id) ? "checkmark.square" : "square")
                                        Text(person.name); Spacer()
                                    }.font(NovaFont.font(.body)).frame(minHeight: 34)
                                }.buttonStyle(.plain).disabled(!writable)
                            }
                            if employees[company.id]?.isEmpty != false { Text("Bu firmada aktif personel yok.").font(NovaFont.font(.meta)) }
                            ForEach(original?.companies.first(where: { $0.company_id == company.id })?.participants.filter { person in
                                !(employees[company.id] ?? []).contains { $0.id == person.id }
                            } ?? []) { person in
                                Button {
                                    if ids.contains(person.id) { selected[company.id]?.remove(person.id) }
                                    else { selected[company.id]?.insert(person.id) }
                                } label: {
                                    Label("\(person.name) · eski kayıt", systemImage: ids.contains(person.id) ? "checkmark.square" : "square").font(NovaFont.font(.meta))
                                }.buttonStyle(.plain).disabled(!writable)
                            }
                        }
                    }.padding(.vertical, 5)
                }
            }
        }
    }
    private func field(_ title: String, _ icon: String, _ binding: Binding<String>) -> some View {
        HStack { Image(systemName: icon).frame(width: 20); TextField(title, text: binding) }.font(NovaFont.font(.body)).frame(minHeight: 34)
    }
    private func validity(_ months: Int) -> String {
        guard months > 0 else { return "Tekrar tarihi tanımlı değil" }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return "Sonraki eğitim: \(formatter.string(from: calendar.date(byAdding: .month, value: months, to: held) ?? held))"
    }
    private func load() async {
        error = nil
        do {
            choices = catalog
            if let original {
                selectedCatalog = original.catalog_id; trainer = original.trainer; method = original.method
                held = formatter.date(from: original.held_on) ?? Date(); location = original.location; notes = original.notes
                selected = Dictionary(uniqueKeysWithValues: original.companies.map { ($0.company_id, Set($0.participants.map(\.id))) })
            } else { trainer = app.profile?.fullName ?? ""; if let initialCompany { selected[initialCompany] = [] } }
            for company in companies {
                employees[company.id] = try await service.employees(company: company.id)
            }
            uncertain = try service.pending() != nil; loaded = true
        } catch { if !Task.isCancelled { self.error = NovaTrainingSessionService.message(error) } }
    }
    private func save() async {
        guard !trainer.trimmingCharacters(in: .whitespaces).isEmpty, !selected.isEmpty,
              selected.values.allSatisfy({ !$0.isEmpty }), let selectedCatalog else { error = "Eğitim, eğitmen ve her firmadan katılımcı seçin."; return }
        var value = NovaTrainingSessionDraft()
        value.id = original?.id; value.expected_version = original?.version ?? 0; value.catalog_id = selectedCatalog
        value.trainer = trainer; value.method = method; value.held_on = formatter.string(from: held); value.location = location; value.notes = notes
        value.companies = selected.keys.sorted { $0.uuidString < $1.uuidString }.map { .init(id: $0, participants: (selected[$0] ?? []).sorted { $0.uuidString < $1.uuidString }) }
        await submit(value)
    }
    private func remove() async {
        guard let original else { return }
        var value = NovaTrainingSessionDraft(); value.action = "delete"; value.id = original.id; value.expected_version = original.version
        await submit(value)
    }
    private func saveCatalog() async {
        guard let company = selected.keys.first, let minutes = Int(customMinutes), let months = Int(customMonths),
              (1...1440).contains(minutes), (0...120).contains(months), !customTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            error = "Başlık, süre ve geçerlilik ayını kontrol edin."; return
        }
        var value = NovaTrainingSessionDraft(); value.action = "catalog"; value.company_id = company
        value.title = customTitle; value.minutes = minutes; value.months = months
        busy = true
        do {
            let result = try await service.save(value)
            if let item = result.catalog { choices.append(item); selectedCatalog = item.id; custom = false }
            error = nil
        } catch { self.error = NovaTrainingSessionService.message(error); uncertain = (try? service.pending()) != nil }
        busy = false
    }
    private func submit(_ value: NovaTrainingSessionDraft) async {
        busy = true
        do { _ = try await service.save(value); dismiss(); celebrate(value.action == "delete" ? "Eğitim başarıyla kaldırıldı!" : NovaSuccessMessage.trainingSaved) }
        catch { self.error = NovaTrainingSessionService.message(error); uncertain = (try? service.pending()) != nil }
        busy = false
    }
    private func retry() async {
        busy = true
        do {
            let result = try await service.retry()
            if let item = result.catalog { choices.removeAll { $0.id == item.id }; choices.append(item); selectedCatalog = item.id; custom = false; uncertain = false }
            else { dismiss(); celebrate("İşlem başarıyla tamamlandı!") }
        } catch { self.error = NovaTrainingSessionService.message(error); uncertain = (try? service.pending()) != nil }
        busy = false
    }
}
