import SwiftUI

/// Keeps historical records readable without silently manufacturing a curriculum.
/// This is a page, not a popup: the caller presents it edge to edge, and every
/// branch below supplies its own back control rather than relying on outer chrome.
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
            if context == nil && error == nil {
                NovaPageSurface { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if let context, original?.education != nil || (context.catalog_enabled && (original == nil || migrate)) {
                NovaEducationEditor(identity: identity, companies: companies, initialCompany: initialCompany,
                    original: context.row ?? original, context: context, canWrite: canWrite && context.catalog_enabled, writableCompanies: writableCompanies,
                    catalog: catalog)
            } else if original?.education == nil {
                // The pre-catalogue path: a simpler, single-session record.
                // Kept in its own card rather than reworked here.
                NovaPopup {
                    VStack(spacing: 8) {
                        if let context, context.catalog_enabled, original != nil, canWrite {
                            NovaButton(label: RDLocalization.string("localizable.nova.education.entry.migrate", table: .localizable,
                                fallback: "Yeni sertifika için müfredatı tamamla"), symbol: "arrow.up.doc", variant: .surface) { migrate = true }
                                .padding(.top, 12)
                        }
                        if let error { NovaText(text: error, style: .meta, color: .red) }
                        NovaTrainingSessionEditor(identity: identity, personnel: personnel, companies: companies,
                            initialCompany: initialCompany, catalog: catalog, original: original, canWrite: canWrite, writableCompanies: writableCompanies)
                    }
                }
            } else {
                NovaPageSurface {
                    VStack(spacing: 16) {
                        NovaBackButton { dismiss() }
                        if let error {
                            NovaText(text: error, style: .body)
                            NovaButton(label: RDLocalization.string("localizable.nova.education.entry.retry", table: .localizable,
                                fallback: "Yeniden dene"), symbol: "arrow.clockwise", variant: .surface) { Task { await load() } }
                        } else { ProgressView() }
                        Spacer()
                    }.padding(20)
                }
            }
        }.task { await load() }
    }
    private func load() async {
        do { context = try await NovaEducationService(identity: identity).context(id: original?.id); error = nil }
        catch { self.error = NovaEducationService.message(error) }
    }
}

/// The accordion form: one step at a time, a progress bar that counts only
/// finished steps, and heavy per-scope editing pushed into its own popup
/// instead of unrolled inline. The reference is the manual nonconformity
/// screen's own accordion.
struct NovaEducationEditor: View {
    let identity: NovaSessionIdentity
    let companies: [NovaPilotCompanySummary]
    let initialCompany: UUID?
    let original: NovaTrainingSession?
    let context: NovaEducationContext
    let canWrite: Bool
    let writableCompanies: Set<UUID>
    /// Official + the expert's own previously-defined training names, already
    /// fetched by the caller for the legacy editor — reused here read-only as
    /// the title picker's source instead of free typing every time.
    let catalog: [NovaTrainingCatalog]
    @EnvironmentObject private var app: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var draft = NovaEducationDraft()
    @State private var saved: NovaTrainingSession?
    @State private var people: [UUID: [NovaEmployeeRow]] = [:]
    @State private var ready = false
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var pending = false
    /// True while `draft` came from a previously autosaved copy rather than
    /// a fresh start — surfaces the notice + discard option below.
    @State private var restoredDraft = false
    @State private var selectedCertificate: Selection?
    @State private var certificatesKnown: [NovaEducationContext.Certificate] = []
    // The picture in the manual form starts open because that is what the
    // expert has in hand; here the title is what the expert types first.
    @State private var open: NovaEducationStep? = .info
    /// One scope expanded inline at a time — everything but topics/minutes
    /// happens right there, no second popup in the way.
    @State private var expandedScope: UUID?
    /// Topics and their minutes, and the realized days/hours, are the one
    /// part heavy enough to still deserve their own popup.
    @State private var topicsScope: ScopeEdit?
    private struct Selection: Identifiable { let id = UUID(); let scope: UUID; let person: UUID; var document: UUID?; var revision: Int? }
    private struct ScopeEdit: Identifiable { let id: UUID }
    private var service: NovaEducationService { .init(identity: identity) }
    private var changed: Bool {
        guard let saved, let education = saved.education else { return true }
        return draft.title != saved.title || draft.notes != saved.notes || draft.provider_name != education.provider_name || draft.trainers != education.trainers || draft.scopes != education.scopes
    }
    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if !ready {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        progress
                        ForEach(NovaEducationStep.allCases) { step in accordion(step) }
                        if let error {
                            NovaCard(padding: 14) {
                                NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                            }
                        }
                        if let notice {
                            NovaCard(padding: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    NovaText(text: notice, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                                    // Only a plain autosave is safe to drop here — a
                                    // `pending` draft is a mutation that may already be
                                    // in flight server-side, and keeps its own retry
                                    // control instead.
                                    if restoredDraft && !pending {
                                        NovaButton(label: RDLocalization.string("localizable.nova.education.discarddraft", table: .localizable,
                                            fallback: "Taslağı temizle, baştan başla"), symbol: "arrow.counterclockwise", variant: .surface, action: discardDraft)
                                            .accessibilityIdentifier("education.draft.discard")
                                    }
                                }
                            }
                        }
                        if pending {
                            NovaButton(label: RDLocalization.string("localizable.nova.education.retry.pending", table: .localizable,
                                fallback: "Bekleyen kaydı aynı işlemle tamamla"), symbol: "arrow.clockwise", variant: .surface) { Task { await retry() } }
                                .disabled(busy)
                        }
                        saveButton
                        certificates
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }
        .background(NovaKeyboardDismissArea())
        .task { await initialize() }
        .onChange(of: draft) { value in
            guard ready else { return }
            do { try service.preserve(value) } catch { self.error = NovaEducationService.message(error) }
        }
        .novaFullScreenCover(item: $selectedCertificate, onDismiss: { Task { await refreshRecord() } }) { selection in
            if let saved {
                NovaPopup { NovaEducationCertificateScreen(identity: identity, session: saved, scopeID: selection.scope, personID: selection.person, canIssue: context.certificate_enabled && canWrite, documentID: selection.document, documentRevision: selection.revision) }
            }
        }
        // Only the heavy half — topics, minutes, realized days — opens as its
        // own popup. Everything else about a scope is inline in the step.
        .novaFullScreenCover(item: $topicsScope, onDismiss: { topicsScope = nil }) { edit in
            if let index = draft.scopes.firstIndex(where: { $0.id == edit.id }) {
                NovaEducationTopicsPopup(scope: $draft.scopes[index], context: context, trainers: draft.trainers,
                    saveCurriculum: { Task { await saveCurriculum(draft.scopes[index]) } },
                    onClose: { topicsScope = nil })
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton(isEnabled: !busy) { dismiss() }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: original == nil
                    ? RDLocalization.string("localizable.nova.education.title.new", table: .localizable, fallback: "Eğitim Ekle")
                    : RDLocalization.string("localizable.nova.education.title.edit", table: .localizable, fallback: "Eğitim Ayrıntısı"),
                    style: .screenTitle)
                NovaText(text: RDLocalization.string("localizable.nova.education.subtitle", table: .localizable,
                    fallback: "Gerçekleşen eğitim · kişi bazlı belge"), style: .metaQuiet)
            }
            Spacer(minLength: 0)
        }
    }

    private var progress: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.education.progress", table: .localizable,
                        fallback: "%1$d/%2$d başlık tamamlandı"), draft.completedCount, NovaEducationStep.allCases.count), style: .label)
                    Spacer(minLength: 0)
                    if !draft.scopes.isEmpty {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.education.ready", table: .localizable, fallback: "Kaydedilebilir"), status: .success)
                    } else {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.education.pending", table: .localizable, fallback: "Kapsam eksik"), status: .warning)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaColorToken.borderMuted.color(in: scheme))
                        Capsule().fill(NovaColorToken.accent.color(in: scheme))
                            .frame(width: max(0, proxy.size.width * draft.progress))
                    }
                }.frame(height: 6)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("education.progress")
    }

    @ViewBuilder private func accordion(_ step: NovaEducationStep) -> some View {
        NovaCompanyAccordion(title: title(step), symbol: symbol(step),
            state: draft.isComplete(step) ? .complete : .missing,
            identifier: "education.step.\(step.rawValue)",
            expanded: Binding(get: { open == step }, set: { open = $0 ? step : nil })) {
            VStack(alignment: .leading, spacing: 10) {
                switch step {
                case .info: infoStep
                case .trainers: trainersStep
                case .scopes: scopesStep
                }
                advance(step)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func title(_ step: NovaEducationStep) -> String {
        switch step {
        case .info: return RDLocalization.string("localizable.nova.education.step.info", table: .localizable, fallback: "Eğitim ve düzenleyici")
        case .trainers: return RDLocalization.string("localizable.nova.education.step.trainers", table: .localizable, fallback: "Eğiticiler")
        case .scopes: return RDLocalization.string("localizable.nova.education.step.scopes", table: .localizable, fallback: "Firma, katılımcı ve konular")
        }
    }
    private func symbol(_ step: NovaEducationStep) -> String {
        switch step {
        case .info: return "text.book.closed"
        case .trainers: return "person.crop.rectangle"
        case .scopes: return "building.2"
        }
    }
    /// A finished step offers the next unfinished one instead of leaving the
    /// expert to find it.
    @ViewBuilder private func advance(_ step: NovaEducationStep) -> some View {
        if draft.isComplete(step), let next = draft.nextIncomplete(after: step) {
            NovaButton(label: String(format: RDLocalization.string("localizable.nova.education.next", table: .localizable,
                fallback: "Sıradaki: %@"), title(next)), symbol: "chevron.down", variant: .surface) { open = next }
                .accessibilityIdentifier("education.next.\(step.rawValue)")
        }
    }

    private var infoStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.education.field.title.hint", table: .localizable,
                fallback: "Konu başlıkları, süre ve katılımcılar bir sonraki 'Firma, katılımcı ve konular' adımında, firma eklendikten sonra düzenlenir."),
                style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
            titlePicker
            field(RDLocalization.string("localizable.nova.education.field.provider", table: .localizable, fallback: "Düzenleyici kişi / kurum"),
                $draft.provider_name, id: "education.provider")
            area(RDLocalization.string("localizable.nova.education.field.notes", table: .localizable, fallback: "Notlar"),
                $draft.notes, id: "education.notes")
        }.disabled(!canWrite)
    }

    /// True once `draft.title` is not one of the catalog's known names — a
    /// new record starts here (empty title matches nothing), and choosing a
    /// catalog entry below always sets `draft.title` to that entry's exact
    /// title, so this flips back to false the moment one is picked.
    private var titleIsCustom: Bool { !catalog.contains { $0.title == draft.title } }
    private var officialCatalog: [NovaTrainingCatalog] { catalog.filter { $0.owner_id == nil } }
    private var customCatalog: [NovaTrainingCatalog] { catalog.filter { $0.owner_id != nil } }
    /// The expert picks a name instead of typing one, the same way the
    /// pre-catalogue training screen already offered a "Kayıtlı eğitim
    /// seçimi" — official names plus anything they have named before. Typing
    /// a genuinely new name is still one tap away, for training that has no
    /// match yet; it is not written back into the shared catalog from here.
    private var titlePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.education.field.title", table: .localizable, fallback: "Eğitim başlığı"), style: .label)
            Menu {
                if !officialCatalog.isEmpty {
                    Section(RDLocalization.string("localizable.nova.education.catalog.official", table: .localizable, fallback: "Kayıtlı eğitimler")) {
                        ForEach(officialCatalog) { entry in Button(entry.title) { draft.title = entry.title } }
                    }
                }
                if !customCatalog.isEmpty {
                    Section(RDLocalization.string("localizable.nova.education.catalog.custom", table: .localizable, fallback: "Daha önce tanımladıklarım")) {
                        ForEach(customCatalog) { entry in Button(entry.title) { draft.title = entry.title } }
                    }
                }
                Button(RDLocalization.string("localizable.nova.education.catalog.new", table: .localizable, fallback: "Yeni eğitim adı tanımla…")) { draft.title = "" }
            } label: {
                HStack {
                    Text(draft.title.isEmpty ? RDLocalization.string("localizable.nova.education.catalog.pick", table: .localizable, fallback: "Eğitim seçin")
                        : draft.title).foregroundStyle(draft.title.isEmpty ? NovaFont.secondaryInk : .primary)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).accessibilityIdentifier("education.title.picker")
            if titleIsCustom {
                TextField(RDLocalization.string("localizable.nova.education.field.title", table: .localizable, fallback: "Eğitim başlığı"), text: $draft.title)
                    .textFieldStyle(.roundedBorder).accessibilityIdentifier("education.title")
                if !draft.title.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.education.catalog.newhint", table: .localizable,
                        fallback: "Bu ad henüz kayıtlı eğitim listesinde yok; şimdilik yalnız bu kayıt için kullanılır."),
                        style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
        }
    }

    private var trainersStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($draft.trainers) { $trainer in
                NovaCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        field(RDLocalization.string("localizable.nova.education.field.trainername", table: .localizable, fallback: "Eğitici adı soyadı"),
                            $trainer.name, id: "education.trainer.name.\(trainer.id)")
                        field(RDLocalization.string("localizable.nova.education.field.trainertitle", table: .localizable, fallback: "Unvan / belge bilgisi"),
                            $trainer.title, id: "education.trainer.title.\(trainer.id)")
                        if draft.trainers.count > 1 {
                            Button(RDLocalization.string("localizable.nova.education.trainer.remove", table: .localizable, fallback: "Eğiticiyi kaldır"),
                                role: .destructive) {
                                draft.trainers.removeAll { $0.id == trainer.id }
                                for s in draft.scopes.indices { for t in draft.scopes[s].topics.indices { draft.scopes[s].topics[t].trainer_ids.removeAll { $0 == trainer.id } } }
                            }.font(NovaFont.font(.meta))
                        }
                    }
                }
            }
            HStack {
                NovaButton(label: RDLocalization.string("localizable.nova.education.trainer.add", table: .localizable, fallback: "Eğitici ekle"),
                    symbol: "plus", variant: .surface) { draft.trainers.append(.init()) }
                if let me = app.profile?.fullName, !me.isEmpty, !draft.trainers.contains(where: { $0.name == me }) {
                    NovaButton(label: RDLocalization.string("localizable.nova.education.trainer.addme", table: .localizable, fallback: "Kendimi ekle"),
                        symbol: "person.fill.checkmark", variant: .surface) { draft.trainers.append(.init(name: me)) }
                }
            }
        }.disabled(!canWrite)
    }

    /// One scope expands inline at a time — company/workplace summary as the
    /// header, everything but topics/minutes right there underneath.
    private var scopesStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.education.scope.explainer", table: .localizable,
                fallback: "Eğitimi hangi firma ve işyerleri için verdiğinizi burada seçersiniz. Hepsi aynı eğitimin konu başlıklarını ve süresini paylaşır; yalnız katılımcı listesi kapsama göre değişir."),
                style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
            ForEach($draft.scopes) { $scope in
                let isOpen = expandedScope == scope.id
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: isOpen ? 14 : 0) {
                        Button {
                            expandedScope = isOpen ? nil : scope.id
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    NovaText(text: scope.company_name ?? RDLocalization.string("localizable.nova.education.scope.company",
                                        table: .localizable, fallback: "Firma"), style: .cardTitle)
                                    NovaText(text: "\(scope.workplace_name ?? "") · \(scope.group_name) · \(scope.participants.count) kişi · \(scope.net) dk",
                                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                                }
                                Spacer(minLength: 0)
                                Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("education.scope.edit.\(scope.id)")
                        if isOpen {
                            NovaEducationScopeEditor(scope: $scope, context: context,
                                people: people[scope.company_id] ?? [],
                                excluded: Set(draft.scopes.filter { $0.id != scope.id }.flatMap { $0.participants.map(\.id) }),
                                openTopics: { topicsScope = .init(id: scope.id) },
                                remove: {
                                    draft.scopes.removeAll { $0.id == scope.id }
                                    if expandedScope == scope.id { expandedScope = nil }
                                })
                        }
                    }
                }
            }
            addScopeMenu.disabled(!canWrite)
            NovaText(text: RDLocalization.string("localizable.nova.education.scope.hint", table: .localizable,
                fallback: "Personel yalnız bir kapsama atanır. Aynı eğitime yalnız aynı tehlike sınıfındaki işyerlerini ekleyebilirsiniz; farklı bir tehlike sınıfı için ayrı bir eğitim kaydı açın."),
                style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    /// Once the record already has a hazard class (from its first scope),
    /// only same-class workplaces are offered — matching add()'s own guard,
    /// so the mismatch error is a rare fallback rather than the everyday path.
    private var addScopeMenu: some View {
        let lockedHazard = draft.scopes.first?.hazard_class
        return Menu {
            ForEach(companies.filter { writableCompanies.contains($0.id) }) { company in
                ForEach(context.workplaces.filter { $0.company_id == company.id && (lockedHazard == nil || $0.hazard_class == lockedHazard) }) { workplace in
                    Button("\(company.name) · \(workplace.name)") { add(company: company.id, workplace: workplace.id) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle").font(.system(size: 14, weight: .semibold))
                NovaText(text: RDLocalization.string("localizable.nova.education.scope.add", table: .localizable,
                    fallback: "Firma / görev kapsamı ekle"), style: .button)
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(.horizontal, 14).frame(minHeight: 44)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }
        .accessibilityIdentifier("education.scope.add")
    }

    private var saveButton: some View {
        NovaButton(label: RDLocalization.string("localizable.nova.education.save", table: .localizable, fallback: "Gerçekleşen eğitimi kaydet"),
            symbol: "checkmark", variant: .primary) { Task { await save() } }
            .disabled(!canWrite || busy || pending || draft.scopes.isEmpty || !ready)
            .accessibilityIdentifier("education.save")
    }

    @ViewBuilder private var certificates: some View {
        if let saved, !changed {
            NovaCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.education.certificates.title", table: .localizable, fallback: "Kişisel belgeler"), style: .cardTitle)
                    ForEach(saved.education?.scopes ?? []) { scope in
                        ForEach(scope.participants) { person in
                            let known = certificatesKnown.first { $0.scope_id == scope.id && $0.person_id == person.id && $0.source_session_revision == saved.version }
                            Button {
                                selectedCertificate = .init(scope: scope.id, person: person.id, document: known?.document_id, revision: known?.revision)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        NovaText(text: person.name ?? RDLocalization.string("localizable.nova.education.certificates.person",
                                            table: .localizable, fallback: "Personel"), style: .body)
                                        NovaText(text: scope.company_name ?? "", style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                                    }
                                    Spacer()
                                    NovaText(text: known != nil
                                        ? RDLocalization.string("localizable.nova.education.certificates.open", table: .localizable, fallback: "Sertifikayı aç")
                                        : (scope.issues?.isEmpty == false || person.job_title.isEmpty)
                                            ? RDLocalization.string("localizable.nova.education.certificates.incomplete", table: .localizable, fallback: "Belge bilgileri eksik")
                                            : RDLocalization.string("localizable.nova.education.certificates.prepare", table: .localizable, fallback: "Sertifika hazırla"),
                                        style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                                }.padding(.vertical, 5)
                            }.disabled(!canWrite && known == nil)
                            let versions = certificatesKnown.filter { $0.scope_id == scope.id && $0.person_id == person.id }
                            if !versions.isEmpty {
                                Menu(RDLocalization.string("localizable.nova.education.certificates.versions", table: .localizable, fallback: "Belge sürümleri")) {
                                    ForEach(versions) { known in
                                        Button(String(format: RDLocalization.string("localizable.nova.education.certificates.revision", table: .localizable, fallback: "Revizyon %d"), known.revision)) {
                                            selectedCertificate = .init(scope: scope.id, person: person.id, document: known.document_id, revision: known.revision)
                                        }
                                    }
                                }.font(NovaFont.font(.meta))
                            }
                        }
                    }
                }
            }
        } else if saved != nil {
            NovaText(text: RDLocalization.string("localizable.nova.education.certificates.savefirst", table: .localizable,
                fallback: "Sertifika için değişiklikleri kaydedin."), style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    private func field(_ label: String, _ value: Binding<String>, id: String, placeholder: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: label, style: .label)
            TextField(placeholder, text: value).textFieldStyle(.roundedBorder).accessibilityIdentifier(id)
        }
    }
    private func area(_ label: String, _ value: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: label, style: .label)
            TextField("", text: value, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder).accessibilityIdentifier(id)
        }
    }

    // MARK: unchanged business logic

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
                draft = preserved; restoredDraft = true
                if let original, preserved.expected_version != original.version {
                    notice = RDLocalization.string("localizable.nova.education.notice.staledraft", table: .localizable,
                        fallback: "Korunan taslak eski bir sürüme ait. Güncel kaydı değiştirmeden önce içeriğini karşılaştırın.")
                } else {
                    // A preserved draft restores silently otherwise — including
                    // for a brand-new record, where it can look exactly like a
                    // blank form that happens to already be filled in. Naming
                    // it, with a way to drop it, matters here specifically:
                    // it also catches a draft saved under an older build,
                    // before what counted as "empty" for this form changed.
                    notice = RDLocalization.string("localizable.nova.education.notice.restoreddraft", table: .localizable,
                        fallback: "Önceki taslağınız geri yüklendi. Baştan başlamak isterseniz aşağıdan taslağı temizleyebilirsiniz.")
                }
            } else {
                seedFreshDraft()
            }
            ready = true
            for company in Set(draft.scopes.map(\.company_id)) { await loadPeople(company) }
        } catch { self.error = NovaEducationService.message(error) }
    }
    /// The "no autosave to restore" branch of initialize(), split out so
    /// discardDraft() can re-derive the same fresh state after clearing one.
    private func seedFreshDraft() {
        if let original, let education = original.education {
            draft = .init(id: original.id, expected_version: original.version, title: original.title,
                provider_name: education.provider_name, notes: original.notes, trainers: education.trainers, scopes: education.scopes)
        } else if let original {
            // Migrating a real legacy record: its own trainer field is
            // actual historical data, not a guess, so it is fair to
            // carry it straight over.
            draft.trainers = [.init(name: original.trainer)]
            draft.id = original.id; draft.expected_version = original.version; draft.title = original.title; draft.notes = original.notes
            notice = RDLocalization.string("localizable.nova.education.notice.legacy", table: .localizable,
                fallback: "Eski kayıt için konuları ve gerçekleşen saatleri uzman bilgisiyle tamamlayın. Katalog geçmiş kaydı kendiliğinden değiştirmez.")
            for company in original.companies {
                if let wp = context.workplaces.first(where: { $0.company_id == company.company_id }) {
                    add(company: company.company_id, workplace: wp.id, seed: false)
                    let i = draft.scopes.count - 1
                    draft.scopes[i].participants = company.participants.map { .init(id: $0.id, name: $0.name) }
                }
            }
        } else {
            // A genuinely new record: trainers start empty. Silently
            // seeding the signed-in expert's own name here used to make
            // "Eğiticiler" read as finished before anyone had chosen
            // one — trainersStep offers the same name as a one-tap
            // "Kendimi ekle" instead, so it stays fast but deliberate.
            if let company = initialCompany, let wp = context.workplaces.first(where: { $0.company_id == company }) { add(company: company, workplace: wp.id) }
        }
    }
    private func discardDraft() {
        try? service.discardDraft(id: original?.id)
        draft = NovaEducationDraft(); restoredDraft = false; notice = nil
        seedFreshDraft()
        Task { for company in Set(draft.scopes.map(\.company_id)) { await loadPeople(company) } }
    }
    private func add(company: UUID, workplace: UUID, seed: Bool = true) {
        guard let wp = context.workplaces.first(where: { $0.id == workplace }) else { return }
        // One training session is one curriculum: a company at "az
        // tehlikeli" and one at "çok tehlikeli" cannot sit in the same
        // record, since the mandated topics/minutes genuinely differ.
        // (Not checked for `seed == false`, the legacy-record migration
        // path, which is replaying history rather than composing a new
        // record and must not lose companies over this.)
        if seed, let first = draft.scopes.first, first.hazard_class != wp.hazard_class {
            error = String(format: RDLocalization.string("localizable.nova.education.scope.hazardmismatch", table: .localizable,
                fallback: "Bu eğitimin diğer kapsamları %1$@ sınıfında; %2$@ sınıfındaki bir işyeri aynı eğitime eklenemez — tek eğitimde tek tehlike sınıfı olur. Ayrı bir eğitim kaydı açın."),
                hazardLabel(first.hazard_class ?? ""), hazardLabel(wp.hazard_class))
            return
        }
        var scope = NovaEducationScope(company_id: company, workplace_id: workplace,
            company_name: companies.first { $0.id == company }?.name, workplace_name: wp.name, hazard_class: wp.hazard_class)
        if seed {
            if let first = draft.scopes.first {
                // A second (or third, or fourth) company added to the same
                // training: share the curriculum already established for
                // this record instead of deriving an independent one from
                // this workplace alone.
                scope.cycle = first.cycle
                scope.topics = first.topics.map { var t = $0; t.trainer_ids = []; return t }
                scope.context_note = first.context_note
            } else {
                let curriculum = context.curricula.first { $0.company_id == company && $0.workplace_id == workplace && $0.education.cycle == "initial" && $0.education.group_name == "Genel" && $0.education.hazard_class == wp.hazard_class }
                scope.topics = curriculum?.education.topics ?? context.package.topics(cycle: scope.cycle, hazard: wp.hazard_class)
                scope.context_note = curriculum?.education.context_note ?? ""
                for i in scope.topics.indices { scope.topics[i].trainer_ids = [] }
            }
        }
        draft.scopes.append(scope)
        Task { await loadPeople(company) }
        // A newly added scope has nothing to show yet; expand it straight
        // away instead of leaving the expert to find it in the list.
        if seed { expandedScope = scope.id }
    }
    private func hazardLabel(_ value: String) -> String {
        ["low": RDLocalization.string("localizable.nova.education.hazard.low", table: .localizable, fallback: "az tehlikeli"),
         "medium": RDLocalization.string("localizable.nova.education.hazard.medium", table: .localizable, fallback: "tehlikeli"),
         "high": RDLocalization.string("localizable.nova.education.hazard.high", table: .localizable, fallback: "çok tehlikeli")][value] ?? value
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
            notice = RDLocalization.string("localizable.nova.education.notice.saved", table: .localizable,
                fallback: "Gerçekleşen eğitim kaydedildi. Kişisel belgeleri aşağıdan hazırlayabilirsiniz.")
        } catch { self.error = NovaEducationService.message(error); pending = (try? service.pending()) != nil }
    }
    private func retry() async {
        do {
            if let pendingDraft = try service.pending() {
                if pendingDraft.action == "curriculum" {
                    busy = true; defer { busy = false }
                    _ = try await service.save(pendingDraft); pending = false
                    notice = RDLocalization.string("localizable.nova.education.notice.curriculumsaved", table: .localizable, fallback: "Firma müfredatı kaydedildi.")
                } else { draft = pendingDraft; pending = false; await save() }
            }
        }
        catch { self.error = NovaEducationService.message(error) }
    }
    private func saveCurriculum(_ scope: NovaEducationScope) async {
        busy = true; defer { busy = false }
        do {
            var value = draft; value.action = "curriculum"; value.id = nil; value.expected_version = 0; value.scopes = [scope]
            _ = try await service.save(value)
            notice = RDLocalization.string("localizable.nova.education.notice.scopecurriculumsaved", table: .localizable,
                fallback: "Yalnız bu firma, işyeri ve görev kapsamının müfredatı kaydedildi.")
        } catch { self.error = NovaEducationService.message(error); pending = (try? service.pending()) != nil }
    }
}
