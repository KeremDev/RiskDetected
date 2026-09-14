import SwiftUI

/// Keeps historical records readable without silently manufacturing a curriculum.
struct NovaEducationEntry: View {
    let identity: NovaSessionIdentity
    let personnel: NovaPersonnelClient
    let companies: [NovaPilotCompanySummary]
    let initialCompany: UUID?
    let catalog: [NovaTrainingCatalog]
    let original: NovaTrainingSession?
    let canWrite: Bool
    let writableCompanies: Set<UUID>
    @State private var context: NovaEducationContext?
    @State private var error: String?
    @State private var migrate = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if context == nil && error == nil { ProgressView().padding(30) }
            else if let context, original?.education != nil || (context.catalog_enabled && (original == nil || migrate)) {
                NovaEducationEditor(identity: identity, companies: companies, initialCompany: initialCompany,
                    original: context.row ?? original, context: context, canWrite: canWrite && context.catalog_enabled, writableCompanies: writableCompanies)
            } else if original?.education == nil {
                VStack(spacing: 8) {
                    if let context, context.catalog_enabled, original != nil, canWrite {
                        Button("Yeni sertifika için müfredatı tamamla") { migrate = true }.padding(.top, 12)
                    }
                    if let error { Text(error).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk) }
                    NovaTrainingSessionEditor(identity: identity, personnel: personnel, companies: companies,
                        initialCompany: initialCompany, catalog: catalog, original: original, canWrite: canWrite, writableCompanies: writableCompanies)
                }
            } else {
                VStack(spacing: 16) {
                    if let error { Text(error); Button("Yeniden dene") { Task { await load() } } } else { ProgressView() }
                    Button("Kapat") { dismiss() }
                }.padding()
            }
        }.task { await load() }
    }
    private func load() async {
        do { context = try await NovaEducationService(identity: identity).context(id: original?.id); error = nil }
        catch { self.error = NovaEducationService.message(error) }
    }
}

struct NovaEducationEditor: View {
    let identity: NovaSessionIdentity
    let companies: [NovaPilotCompanySummary]
    let initialCompany: UUID?
    let original: NovaTrainingSession?
    let context: NovaEducationContext
    let canWrite: Bool
    let writableCompanies: Set<UUID>
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = NovaEducationDraft()
    @State private var saved: NovaTrainingSession?
    @State private var people: [UUID: [NovaEmployeeRow]] = [:]
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var pending = false
    @State private var selectedCertificate: Selection?
    @State private var certificatesKnown: [NovaEducationContext.Certificate] = []
    private struct Selection: Identifiable { let id = UUID(); let scope: UUID; let person: UUID; var document: UUID?; var revision: Int? }
    private var service: NovaEducationService { .init(identity: identity) }
    private var changed: Bool {
        guard let saved, let education = saved.education else { return true }
        return draft.title != saved.title || draft.notes != saved.notes || draft.provider_name != education.provider_name || draft.trainers != education.trainers || draft.scopes != education.scopes
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(original == nil ? "Eğitim Ekle" : "Eğitim Ayrıntısı", systemImage: "graduationcap").font(NovaFont.font(.cardTitle))
                Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").padding(10) }.tint(.primary)
            }.padding(18)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Gerçekleşen eğitim · Kişi bazlı belge").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                    if let error { Text(error).font(NovaFont.font(.body)).foregroundStyle(.red) }
                    if let notice { Text(notice).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk) }
                    if pending {
                        Button("Bekleyen kaydı aynı işlemle tamamla") { Task { await retry() } }.disabled(busy)
                    }
                    GroupBox {
                        TextField("Eğitim başlığı", text: $draft.title)
                        TextField("Düzenleyici kişi / kurum", text: $draft.provider_name)
                        TextField("Notlar", text: $draft.notes, axis: .vertical).lineLimit(2...5)
                    } label: { Label("Eğitim ve düzenleyici", systemImage: "text.book.closed") }
                    trainersForm.disabled(!canWrite)
                    scopesForm.disabled(!canWrite)
                    addScopeMenu.disabled(!canWrite)
                    Text("Aynı firmada farklı görev ve içerik için ayrı kapsam ekleyebilirsiniz. Personel yalnız bir kapsama atanır.").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                    certificates
                    Button { Task { await save() } } label: {
                        HStack { if busy { ProgressView() }; Text("Gerçekleşen eğitimi kaydet").bold() }.frame(maxWidth: .infinity).padding(12)
                    }.buttonStyle(.borderedProminent).tint(.green).disabled(!canWrite || busy || pending || draft.scopes.isEmpty || !ready)
                }.textFieldStyle(.roundedBorder).padding(18).disabled(busy).novaPopupContentSize()
            }
        }.task { await initialize() }
        .onChange(of: draft) { value in
            guard ready else { return }
            do { try service.preserve(value) } catch { self.error = NovaEducationService.message(error) }
        }
        .novaFullScreenCover(item: $selectedCertificate, onDismiss: { Task { await refreshRecord() } }) { selection in
            if let saved {
                NovaPopup { NovaEducationCertificateScreen(identity: identity, session: saved, scopeID: selection.scope, personID: selection.person, canIssue: context.certificate_enabled && canWrite, documentID: selection.document, documentRevision: selection.revision) }
            }
        }
    }
    private var scopesForm: some View {
ForEach($draft.scopes) { $scope in
                        NovaEducationScopeEditor(scope: $scope, context: context, trainers: draft.trainers,
                            people: people[scope.company_id] ?? [],
                            excluded: Set(draft.scopes.filter { $0.id != scope.id }.flatMap { $0.participants.map(\.id) }),
                            saveCurriculum: { Task { await saveCurriculum(scope) } },
                            remove: { draft.scopes.removeAll { $0.id == scope.id } })
                    }
    }
    private var trainersForm: some View {
GroupBox {
                        ForEach($draft.trainers) { $trainer in
                            VStack {
                                TextField("Eğitici adı soyadı", text: $trainer.name)
                                TextField("Unvan / belge bilgisi", text: $trainer.title)
                                if draft.trainers.count > 1 {
                                    Button("Eğiticiyi kaldır", role: .destructive) {
                                        draft.trainers.removeAll { $0.id == trainer.id }
                                        for s in draft.scopes.indices { for t in draft.scopes[s].topics.indices { draft.scopes[s].topics[t].trainer_ids.removeAll { $0 == trainer.id } } }
                                    }.font(NovaFont.font(.meta))
                                }
                            }.padding(.vertical, 5)
                        }
                        Button("Eğitici ekle", systemImage: "plus") { draft.trainers.append(.init()) }
                    } label: { Label("Eğiticiler", systemImage: "person.crop.rectangle") }
    }
    @ViewBuilder private var certificates: some View {
if let saved, !changed {
                        GroupBox {
                            ForEach(saved.education?.scopes ?? []) { scope in
                                ForEach(scope.participants) { person in
                                    Button {
                                        let known = certificatesKnown.first { $0.scope_id == scope.id && $0.person_id == person.id && $0.source_session_revision == saved.version }
                                        selectedCertificate = .init(scope: scope.id, person: person.id, document: known?.document_id, revision: known?.revision)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(person.name ?? "Personel")
                                                Text(scope.company_name ?? "").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                                            }
                                            Spacer(); Label(certificatesKnown.contains { $0.scope_id == scope.id && $0.person_id == person.id && $0.source_session_revision == saved.version } ? "Sertifikayı aç" : (scope.issues?.isEmpty == false || person.job_title.isEmpty) ? "Belge bilgileri eksik" : "Sertifika hazırla", systemImage: "doc.text")
                                                .font(NovaFont.font(.meta))
                                        }.padding(.vertical, 5)
                                    }.disabled(!canWrite && !certificatesKnown.contains { $0.scope_id == scope.id && $0.person_id == person.id && $0.source_session_revision == saved.version })
                                    if certificatesKnown.contains(where: { $0.scope_id == scope.id && $0.person_id == person.id }) {
                                        Menu("Belge sürümleri") {
                                            ForEach(certificatesKnown.filter { $0.scope_id == scope.id && $0.person_id == person.id }) { known in
                                                Button("Revizyon \(known.revision)") { selectedCertificate = .init(scope: scope.id, person: person.id, document: known.document_id, revision: known.revision) }
                                            }
                                        }.font(NovaFont.font(.meta))
                                    }
                                }
                            }
                        } label: { Label("Kişisel belgeler", systemImage: "doc.on.doc") }
                    } else if saved != nil { Text("Sertifika için değişiklikleri kaydedin.").font(NovaFont.font(.meta)) }
    }
    private var addScopeMenu: some View {
Menu {
                        ForEach(companies.filter { writableCompanies.contains($0.id) }) { company in
                            ForEach(context.workplaces.filter { $0.company_id == company.id }) { workplace in
                                Button("\(company.name) · \(workplace.name)") { add(company: company.id, workplace: workplace.id) }
                            }
                        }
                    } label: { Label("Firma / görev kapsamı ekle", systemImage: "plus.circle") }
    }
    private func refreshRecord() async {
        guard let saved else { return }
        do {
            let latest = try await service.context(id: saved.id)
            certificatesKnown = latest.certificates
            if let row = latest.row, let education = row.education {
                self.saved = row
                draft = .init(id: row.id, expected_version: row.version, title: row.title, provider_name: education.provider_name, notes: row.notes, trainers: education.trainers, scopes: education.scopes)
            }
        } catch { self.error = NovaEducationService.message(error) }
    }
    private func initialize() async {
        guard !ready else { return }
        do {
            saved = original; certificatesKnown = context.certificates
            if let pendingDraft = try service.pending() { draft = try service.draft(id: original?.id) ?? pendingDraft; pending = true }
            else if let preserved = try service.draft(id: original?.id) {
                draft = preserved
                if let original, preserved.expected_version != original.version { notice = "Korunan taslak eski bir sürüme ait. Güncel kaydı değiştirmeden önce içeriğini karşılaştırın." }
            } else if let original, let education = original.education {
                draft = .init(id: original.id, expected_version: original.version, title: original.title,
                    provider_name: education.provider_name, notes: original.notes, trainers: education.trainers, scopes: education.scopes)
            } else {
                draft.trainers = [.init(name: original?.trainer ?? app.profile?.fullName ?? "")]
                if let original {
                    draft.id = original.id; draft.expected_version = original.version; draft.title = original.title; draft.notes = original.notes
                    notice = "Eski kayıt için konuları ve gerçekleşen saatleri uzman bilgisiyle tamamlayın. Katalog geçmiş kaydı kendiliğinden değiştirmez."
                    for company in original.companies {
                        if let wp = context.workplaces.first(where: { $0.company_id == company.company_id }) {
                            add(company: company.company_id, workplace: wp.id, seed: false)
                            let i = draft.scopes.count - 1
                            draft.scopes[i].participants = company.participants.map { .init(id: $0.id, name: $0.name) }
                        }
                    }
                } else if let company = initialCompany, let wp = context.workplaces.first(where: { $0.company_id == company }) { add(company: company, workplace: wp.id) }
            }
            ready = true
            for company in Set(draft.scopes.map(\.company_id)) { await loadPeople(company) }
        } catch { self.error = NovaEducationService.message(error) }
    }
    private func add(company: UUID, workplace: UUID, seed: Bool = true) {
        guard let wp = context.workplaces.first(where: { $0.id == workplace }) else { return }
        var scope = NovaEducationScope(company_id: company, workplace_id: workplace,
            company_name: companies.first { $0.id == company }?.name, workplace_name: wp.name, hazard_class: wp.hazard_class)
        if seed {
            let curriculum = context.curricula.first { $0.company_id == company && $0.workplace_id == workplace && $0.education.cycle == "initial" && $0.education.group_name == "Genel" && $0.education.hazard_class == wp.hazard_class }
            scope.topics = curriculum?.education.topics ?? context.package.topics(cycle: scope.cycle, hazard: wp.hazard_class)
            scope.context_note = curriculum?.education.context_note ?? ""
            for i in scope.topics.indices { scope.topics[i].trainer_ids = [] }
        }
        draft.scopes.append(scope)
        Task { await loadPeople(company) }
    }
    private func loadPeople(_ company: UUID) async {
        guard people[company] == nil else { return }
        do { people[company] = try await NovaTrainingSessionService(identity: identity).employees(company: company) }
        catch { self.error = NovaEducationService.message(error) }
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do {
            let result = try await service.save(draft)
            guard let row = result.row, let education = row.education else { throw NovaPersonnelFailure.unavailable }
            saved = row; draft.id = row.id; draft.expected_version = row.version
            draft.scopes = education.scopes; draft.trainers = education.trainers
            notice = "Gerçekleşen eğitim kaydedildi. Kişisel belgeleri aşağıdan hazırlayabilirsiniz."
        } catch { self.error = NovaEducationService.message(error); pending = (try? service.pending()) != nil }
    }
    private func retry() async {
        do {
            if let pendingDraft = try service.pending() {
                if pendingDraft.action == "curriculum" {
                    busy = true; defer { busy = false }
                    _ = try await service.save(pendingDraft); pending = false; notice = "Firma müfredatı kaydedildi."
                } else { draft = pendingDraft; pending = false; await save() }
            }
        }
        catch { self.error = NovaEducationService.message(error) }
    }
    private func saveCurriculum(_ scope: NovaEducationScope) async {
        busy = true; defer { busy = false }
        do {
            var value = draft; value.action = "curriculum"; value.id = nil; value.expected_version = 0; value.scopes = [scope]
            _ = try await service.save(value); notice = "Yalnız bu firma, işyeri ve görev kapsamının müfredatı kaydedildi."
        } catch { self.error = NovaEducationService.message(error); pending = (try? service.pending()) != nil }
    }
}
