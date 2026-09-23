import SwiftUI

/// Keeps historical records readable without silently manufacturing a curriculum.
/// This is a page, not a popup: the caller presents it edge to edge, and every
/// branch below supplies its own back control rather than relying on outer chrome.
struct NovaEducationEntry: View {
    let identity: NovaSessionIdentity
    let companies: [NovaPilotCompanySummary]
    let initialCompany: UUID?
    let original: NovaTrainingSession?
    let canWrite: Bool
    let writableCompanies: Set<UUID>
    @State private var context: NovaEducationContext?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if context == nil && error == nil {
                NovaPageSurface { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else if let context {
                // Every expert context uses the same guided editor. The old
                // single-page v2 form used to appear here whenever the
                // catalogue rollout bit was false, which made normal experts
                // and OSGB experts see a different product from the OSGB
                // workspace. `catalog_enabled` now describes certificate /
                // catalogue capabilities returned by the server; it must not
                // choose a legacy UI. Legacy records are seeded into the same
                // guided editor and remain explicitly marked as migrated.
                NovaEducationEditor(identity: identity, companies: companies, initialCompany: initialCompany,
                    original: context.row ?? original, context: context, canWrite: canWrite, writableCompanies: writableCompanies)
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

/// One page with a single expanded section. Completed sections remain
/// available as compact summaries so corrections do not require backtracking.
///
/// One training record is one curriculum, shared by every company/workplace
/// attending it — `template` holds that shared curriculum, method, schedule
/// and location, and is mirrored into every entry of `draft.scopes`
/// (`onChange(of: template)` below) so save() keeps writing the same
/// per-scope shape the server already expects. Participants are the one
/// thing that is genuinely per company.
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
    @Environment(\.colorScheme) private var scheme
    @State private var draft = NovaEducationDraft()
    @State private var template = NovaEducationScope(company_id: UUID(), workplace_id: nil)
    @State private var scheduleDays: [NovaEducationDay] = []
    @State private var saved: NovaTrainingSession?
    @State private var people: [UUID: [NovaEmployeeRow]] = [:]
    @State private var ready = false
    @State private var busy = false
    @State private var preparingCertificates = false
    @State private var error: String?
    @State private var notice: String?
    @State private var saveProgress: String?
    @State private var validationStep: NovaEducationStep?
    @State private var validationMessage: String?
    @State private var certificateJump = UUID()
    @State private var pending = false
    /// True while `draft` came from a previously autosaved copy rather than
    /// a fresh start — surfaces the notice + discard option below.
    @State private var restoredDraft = false
    @State private var selectedCertificate: Selection?
    @State private var certificatesKnown: [NovaEducationContext.Certificate] = []
    @State private var currentStep: NovaEducationStep = .companies
    @State private var showingCompanies = false
    @State private var showingParticipants = false
    @State private var showingCycle = false
    @State private var expandedTopicGroup: String?
    @State private var showingRestoredBanner = false
    @State private var companySearch = ""
    @State private var participantCompany: UUID?
    @State private var participantSearch = ""
    @State private var participantDepartment = ""
    @State private var participantJob = ""
    @State private var selectedParticipantsOnly = false
    @State private var editingTrainerID: String?
    @State private var returningToReview = false
    @FocusState private var providerFocused: Bool
    @State private var selectedCycle = ""
    private struct Selection: Identifiable { let id = UUID(); let scope: UUID; let person: UUID; var document: UUID?; var revision: Int? }
    private struct ParticipantCandidate: Identifiable {
        let scopeIndex: Int
        let person: NovaEmployeeRow
        var id: String { "\(scopeIndex)-\(person.id.uuidString)" }
    }
    private var service: NovaEducationService { .init(identity: identity) }
    private var changed: Bool {
        guard let saved, let education = saved.education else { return true }
        return draft.title != saved.title || draft.notes != saved.notes || draft.provider_name != education.provider_name || draft.trainers != education.trainers || draft.scopes != education.scopes
    }
    var body: some View {
        NovaPageSurface {
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    if !ready {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
                    } else {
                        progress
                        ForEach(NovaEducationStep.allCases) { step in
                            sectionCard(step).id(step.rawValue)
                        }
                        if let error {
                            NovaCard(padding: 14) {
                                NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                            }
                        }
                        if let notice, !restoredDraft || original.map({ $0.version != draft.expected_version }) == true {
                            NovaCard(padding: 14) {
                                NovaText(text: notice, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                            }
                        }
                        if let saveProgress { NovaHelpHint(text: saveProgress) }
                        if pending {
                            NovaButton(label: RDLocalization.string("localizable.nova.education.retry.pending", table: .localizable,
                                fallback: "Bekleyen kaydı aynı işlemle tamamla"), symbol: "arrow.clockwise", variant: .surface) { Task { await retry() } }
                                .disabled(busy)
                        }
                        if currentStep == .review {
                            saveButton
                        } else {
                            stepNavigation
                        }
                        certificates.id("education.certificates")
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
                .onChange(of: currentStep) { step in
                    withAnimation(.easeInOut(duration: 0.22)) { scroll.scrollTo(step.rawValue, anchor: .top) }
                }
                .onChange(of: certificateJump) { _ in
                    withAnimation(.easeInOut(duration: 0.22)) { scroll.scrollTo("education.certificates", anchor: .top) }
                }
            }
            }
        }

        .task { await initialize() }
        .onChange(of: draft) { value in
            guard ready else { return }
            do { try service.preserve(value) } catch { self.error = NovaEducationService.message(error) }
        }
        // Every edit to the shared curriculum/method/schedule/location is
        // made on `template`; this is the one place it gets copied into
        // every real scope, so save() keeps seeing the shape it expects.
        .onChange(of: template) { value in
            guard ready else { return }
            for i in draft.scopes.indices {
                draft.scopes[i].cycle = value.cycle; draft.scopes[i].topics = value.topics; draft.scopes[i].context_note = value.context_note
                draft.scopes[i].lessons = value.lessons; draft.scopes[i].draft_days = value.draft_days; draft.scopes[i].location = value.location
            }
        }
        .onChange(of: scheduleDays) { value in
            guard ready else { return }
            recomputeLessons()
        }
        .onChange(of: template.topics) { _ in
            guard ready else { return }
            rebalanceScheduleDays()
        }
        // Trainer/method no longer vary per topic — every topic is credited
        // to whoever is currently listed as a trainer for the record.
        .onChange(of: draft.trainers) { value in
            guard ready else { return }
            let ids = value.map(\.id)
            for i in template.topics.indices { template.topics[i].trainer_ids = ids }
        }
        .novaFullScreenCover(item: $selectedCertificate, onDismiss: { Task { await refreshRecord() } }) { selection in
            if let saved {
                NovaPopup { NovaEducationCertificateScreen(identity: identity, session: saved, scopeID: selection.scope, personID: selection.person, canIssue: context.certificate_enabled && canWrite, documentID: selection.document, documentRevision: selection.revision) }
            }
        }
        .novaFullScreenCover(isPresented: $showingCompanies) {
            companyPicker
        }
        .novaFullScreenCover(isPresented: $showingParticipants) {
            participantsPicker
        }
        .novaFullScreenCover(isPresented: $showingCycle) {
            cycleSheet
        }
        .overlay(alignment: .top) {
            if showingRestoredBanner {
                HStack(spacing: 12) {
                    Text("Önceki taslağınız geri yüklendi").font(NovaFont.font(.meta))
                    Spacer(minLength: 0)
                    if !pending { Button("Baştan başla", action: discardDraft).font(NovaFont.font(.bodyStrong)) }
                }
                .padding(14).background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
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
            if restoredDraft && !pending {
                Menu {
                    Button("Baştan başla", role: .destructive, action: discardDraft)
                        .accessibilityIdentifier("education.draft.discard")
                } label: { Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 36, height: 36) }
                .accessibilityLabel("Eğitim seçenekleri")
            }
        }
    }

    private var progress: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: "Eğitim oluşturuluyor · \(draft.completedCount) / \(NovaEducationStep.allCases.count)", style: .label)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaColorToken.borderMuted.color(in: scheme))
                        Capsule().fill(NovaColorToken.accent.color(in: scheme))
                            .frame(width: max(0, proxy.size.width * draft.progress))
                    }
                }.frame(height: 6).animation(.easeInOut(duration: 0.22), value: draft.completedCount)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("education.progress")
    }

    private func sectionCard(_ step: NovaEducationStep) -> some View {
        let completed = draft.isComplete(step) && !(validationStep == step && firstMissingField()?.0 == step)
        return NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                Button { currentStep = step } label: {
                    HStack(spacing: 10) {
                        Image(systemName: completed ? "checkmark.circle.fill" : symbol(step))
                            .font(.system(size: 17, weight: .semibold)).frame(width: 24)
                            .foregroundStyle(completed ? NovaColorToken.accent.color(in: scheme) : NovaFont.secondaryInk)
                        NovaText(text: title(step), style: .cardTitle)
                        Spacer(minLength: 0)
                        NovaStatusPill(label: stepStatus(step), status: completed ? .success : .warning)
                    }
                }.buttonStyle(NovaRowPressStyle())
                if currentStep == step {
                    Divider()
                    if validationStep == step, let validationMessage { NovaHelpHint(text: validationMessage) }
                    activeStep
                } else if let summary = sectionSummary(step) {
                    NovaText(text: summary, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                        .lineLimit(2)
                }
            }
        }.accessibilityIdentifier("education.current-step.\(step.rawValue)")
    }

    private func stepStatus(_ step: NovaEducationStep) -> String {
        if validationStep == step && firstMissingField()?.0 == step { return "Eksik bilgi" }
        if step == .schedule && !scheduleEndsInPast { return "Kontrol gerekli" }
        if draft.isComplete(step) { return "Tamamlandı" }
        return step == .review ? "Kontrol gerekli" : "Eksik bilgi"
    }

    private func sectionSummary(_ step: NovaEducationStep) -> String? {
        switch step {
        case .companies:
            guard !draft.scopes.isEmpty else { return nil }
            return "\(draft.scopes.count) firma/işyeri seçimi · \(hazardLabel(draft.scopes.first?.hazard_class ?? "")) · " + draft.scopes.compactMap(\.company_name).joined(separator: ", ")
        case .info: return selectedCycle.isEmpty ? nil : "\(template.cycleName) · \(methodBinding.wrappedValue == "online" ? "Online" : "Yüz yüze")"
        case .topics: return template.net > 0 ? "Toplam öğretim: \(formatDuration(template.net))" : nil
        case .schedule: return template.lessons.isEmpty ? nil : "\(scheduleDays.count) gün · \(formatDuration(template.net + template.breakTotal)) (molalar dahil)"
        case .trainers: return draft.trainers.isEmpty ? nil : draft.trainers.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
        case .participants: return draft.scopes.isEmpty ? nil : "\(draft.scopes.reduce(0) { $0 + $1.participants.count }) kişi · \(Set(draft.scopes.map(\.company_id)).count) firma"
        case .review: return draft.isComplete(.review) ? "Kaydetmeye hazır" : nil
        }
    }

    @ViewBuilder private var activeStep: some View {
        switch currentStep {
        case .companies: companiesStep
        case .info: infoStep
        case .topics: topicsStep
        case .schedule: scheduleStep
        case .trainers: trainersStep
        case .participants: participantsStep
        case .review: reviewStep
        }
    }

    private var stepNavigation: some View {
        HStack(spacing: 10) {
            if let previous = previousStep {
                NovaButton(label: "Geri", symbol: "chevron.left", variant: .surface) {
                    currentStep = previous
                }
            }
            Spacer(minLength: 0)
            NovaButton(label: returningToReview ? "Kontrole dön" : "Devam", symbol: "chevron.right", variant: .primary,
                isEnabled: canAdvance) {
                if returningToReview { currentStep = .review; returningToReview = false }
                else if let next = nextStep { currentStep = next }
            }.accessibilityIdentifier("education.next.\(currentStep.rawValue)")
        }
        .padding(.top, 2)
    }

    private var previousStep: NovaEducationStep? {
        guard let index = NovaEducationStep.allCases.firstIndex(of: currentStep), index > 0 else { return nil }
        return NovaEducationStep.allCases[index - 1]
    }

    private var nextStep: NovaEducationStep? {
        guard let index = NovaEducationStep.allCases.firstIndex(of: currentStep), index + 1 < NovaEducationStep.allCases.count else { return nil }
        return NovaEducationStep.allCases[index + 1]
    }

    private var canAdvance: Bool {
        draft.isComplete(currentStep) && (currentStep != .schedule || scheduleEndsInPast) &&
            (validationStep != currentStep || firstMissingField()?.0 != currentStep)
    }

    private var scheduleEndsInPast: Bool {
        guard scheduleDistributionValid, !template.lessons.isEmpty else { return false }
        return template.lessons.allSatisfy { lesson in
            guard let start = NovaEducationClock.date(lesson.starts_at) else { return false }
            return start.addingTimeInterval(Double(lesson.instruction_minutes + lesson.break_minutes) * 60) <= Date()
        }
    }

    private func title(_ step: NovaEducationStep) -> String {
        switch step {
        case .companies: return "Firmalar ve işyerleri"
        case .info: return RDLocalization.string("localizable.nova.education.step.info", table: .localizable, fallback: "Eğitim ve düzenleyici")
        case .topics: return "Konular ve dakikalar"
        case .schedule: return RDLocalization.string("localizable.nova.education.step.schedule", table: .localizable, fallback: "Tarih, saat ve yer")
        case .trainers: return RDLocalization.string("localizable.nova.education.step.trainers", table: .localizable, fallback: "Eğiticiler")
        case .participants: return RDLocalization.string("localizable.nova.education.step.participants", table: .localizable, fallback: "Katılımcılar")
        case .review: return "Kontrol ve kaydet"
        }
    }
    private func symbol(_ step: NovaEducationStep) -> String {
        switch step {
        case .companies: return "building.2"
        case .info: return "text.book.closed"
        case .topics: return "list.bullet.clipboard"
        case .schedule: return "calendar.badge.clock"
        case .trainers: return "person.crop.rectangle"
        case .participants: return "person.3"
        case .review: return "checkmark.circle"
        }
    }
    /// A finished step offers the next unfinished one instead of leaving the
    /// expert to find it.
    // MARK: - Company selection comes before hazard-based curriculum and time.

    private var companiesStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: "Birden fazla firma seçebilirsiniz. İşyeri olmayan firma doğrudan eklenir; işyeri varsa ilgili işyerini seçin. Tehlike sınıfları aynı olmalıdır.",
                style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
            if let summary = sectionSummary(.companies) { NovaText(text: summary, style: .bodyStrong) }
            NovaButton(label: draft.scopes.isEmpty ? "Firma ekle" : "Başka firma veya işyeri ekle", symbol: "building.2", variant: .surface) {
                showingCompanies = true
            }
        }.disabled(!canWrite)
    }

    private var companyPicker: some View {
        let available = companies.filter { writableCompanies.contains($0.id) && !$0.is_archived }
        let filtered = companySearch.isEmpty ? available : available.filter { $0.name.localizedCaseInsensitiveContains(companySearch) }
        return NovaPageSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NovaText(text: "Firma ve işyerleri", style: .screenTitle)
                    Spacer()
                    Button("Bitti") { finishCompanySelection() }.font(NovaFont.font(.bodyStrong))
                }
                TextField("Firma ara", text: $companySearch).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("education.companies.search")
                NovaText(text: "\(draft.scopes.count) firma/işyeri seçimi" + (draft.scopes.first.map { " · \(hazardLabel($0.hazard_class ?? ""))" } ?? ""), style: .metaQuiet)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filtered) { company in companyChoice(company) }
                        if filtered.isEmpty { NovaText(text: "Eğitim eklenebilecek firma bulunamadı.", style: .metaQuiet) }
                    }
                }
                NovaButton(label: "\(draft.scopes.count) seçimi tamamla", symbol: "checkmark", variant: .primary, isEnabled: !draft.scopes.isEmpty) {
                    finishCompanySelection()
                }
            }.padding(20)
        }
    }

    private func companyChoice(_ company: NovaPilotCompanySummary) -> some View {
        let places = context.workplaces.filter { $0.company_id == company.id }
        return NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                NovaText(text: company.name, style: .cardTitle)
                if places.isEmpty {
                    let checked = draft.scopes.contains { $0.company_id == company.id && $0.workplace_id == nil }
                    Button {
                        if checked { draft.scopes.removeAll { $0.company_id == company.id && $0.workplace_id == nil } }
                        else { pick(company: company.id, workplace: nil) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? NovaColorToken.accent.color(in: scheme) : NovaFont.secondaryInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Firmayı ekle").font(NovaFont.font(.bodyStrong))
                                Text(hazardLabel(company.hazard_class))
                                    .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                            }
                            Spacer()
                        }.padding(.vertical, 4)
                    }.buttonStyle(NovaRowPressStyle())
                        .disabled(draft.scopes.contains { $0.hazard_class != company.hazard_class })
                }
                ForEach(places) { place in
                    let checked = draft.scopes.contains { $0.company_id == company.id && $0.workplace_id == place.id }
                    Button {
                        if checked { draft.scopes.removeAll { $0.company_id == company.id && $0.workplace_id == place.id } }
                        else { pick(company: company.id, workplace: place.id) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? NovaColorToken.accent.color(in: scheme) : NovaFont.secondaryInk)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).font(NovaFont.font(.bodyStrong))
                                Text(hazardLabel(place.hazard_class)).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                            }
                            Spacer()
                        }.padding(.vertical, 4)
                    }.buttonStyle(NovaRowPressStyle())
                        .disabled(draft.scopes.contains { $0.hazard_class != place.hazard_class })
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("education.companies.\(company.id)")
    }

    // MARK: - Education type and organizer

    private var infoStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            cyclePicker
            methodQuickToggle
            VStack(alignment: .leading, spacing: 4) {
                NovaText(text: "Düzenleyici kişi / kurum", style: .label)
                TextField("Düzenleyici adı", text: $draft.provider_name)
                    .textFieldStyle(.roundedBorder).submitLabel(.done).focused($providerFocused)
                    .onSubmit { advanceIfComplete(.info) }
                    .onChange(of: providerFocused) { focused in if !focused { advanceIfComplete(.info) } }
                    .accessibilityIdentifier("education.provider")
            }
            area("Notlar (isteğe bağlı)",
                $draft.notes, id: "education.notes")
        }.disabled(!canWrite)
    }

    /// "Eğitim başlığı" as a separately-typed name had no effect on
    /// anything — the topics, minutes and hazard-class rules all come from
    /// the cycle, not from a title. Removed; the cycle picker is the one
    /// choice that actually does something, so it is the only one asked
    /// for, and the record's title is just its cycle's own name.
    private var cyclePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.education.field.cycle", table: .localizable, fallback: "Eğitim:"), style: .label)
            Button { showingCycle = true } label: {
                HStack {
                    Text(selectedCycle.isEmpty ? "Eğitim türü seçin" : template.cycleName)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                }.padding(12).background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("education.cycle")
            NovaText(text: "Eğitim türü değişirse konular ve dakikalar seçilen tehlike sınıfına göre yeniden hazırlanır.", style: .metaQuiet)
        }
    }

    private var cycleSheet: some View {
        NovaPageSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    NovaText(text: "Eğitim türü", style: .screenTitle)
                    Spacer()
                    Button("Kapat") { showingCycle = false }.font(NovaFont.font(.bodyStrong))
                }
                NovaText(text: "Eğitimin amacına uygun türü seçin. Konular ve süreler bu seçime göre hazırlanır.",
                    style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(NovaEducationScope.cycles, id: \.0) { cycle in
                        Button {
                            selectedCycle = cycle.0
                            template.cycle = cycle.0
                            draft.title = template.cycleName
                            refreshTemplateDefaults()
                            showingCycle = false
                            advanceIfComplete(.info)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(cycle.1).font(NovaFont.font(.bodyStrong))
                                    Text(cycleDescription(cycle.0)).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                                Image(systemName: selectedCycle == cycle.0 ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedCycle == cycle.0 ? NovaColorToken.accent.color(in: scheme) : NovaFont.secondaryInk)
                            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(NovaRowPressStyle())
                    }
                }
            }
            }.padding(20)
        }
    }

    private func finishCompanySelection() {
        showingCompanies = false
        advanceIfComplete(.companies)
    }

    private func advanceIfComplete(_ step: NovaEducationStep) {
        guard currentStep == step, draft.isComplete(step), let next = nextStep else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            currentStep = returningToReview ? .review : next
            returningToReview = false
        }
    }

    private func cycleDescription(_ cycle: String) -> String {
        ["initial": "Temel İSG eğitimini ilk kez alan çalışanlar", "periodic_repeat": "Periyodik temel İSG eğitimi", "onboarding": "İşe başlamadan önce verilen eğitim", "knowledge_refresh": "Bilgileri güncelleme eğitimi", "additional": "Ek ihtiyaçlara yönelik eğitim", "workplace_specific": "Yeni işyerinin risklerine özel eğitim", "custom": "Özel içerikli eğitim"][cycle] ?? ""
    }

    /// A bulk shortcut over every topic's own method — the per-topic picker
    /// inside "Konuları ve Süre" still exists for the rare session that
    /// genuinely mixes the two.
    private var methodQuickToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.education.field.method", table: .localizable, fallback: "Eğitim yöntemi"), style: .label)
            Picker("", selection: methodBinding) {
                Text(RDLocalization.string("localizable.nova.education.method.inperson", table: .localizable, fallback: "Yüz yüze")).tag("face_to_face")
                Text(RDLocalization.string("localizable.nova.education.method.online", table: .localizable, fallback: "Online")).tag("online")
            }.pickerStyle(.segmented).labelsHidden().accessibilityIdentifier("education.method")
            if template.hazard_class != "low" && methodBinding.wrappedValue == "online" {
                NovaText(text: "İşyerine özgü konular yüz yüze olarak kalır.", style: .metaQuiet)
            }
        }
    }
    private var methodBinding: Binding<String> {
        Binding(get: { template.topics.first?.method ?? "face_to_face" },
            set: applyMethod)
    }
    private func applyMethod(_ value: String) {
        for i in template.topics.indices {
            let inPersonRequired = template.topics[i].group == "G4" && (template.hazard_class != "low" || template.cycle == "onboarding")
            template.topics[i].method = inPersonRequired ? "face_to_face" : value
        }
    }

    private var topicsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: "\(hazardLabel(template.hazard_class ?? "")) · \(template.cycleName)", style: .bodyStrong)
            NovaText(text: "Düzenlemek istediğiniz grubu açın. Süre değişince eğitim günleri ve bitiş saatleri yeniden hesaplanır.",
                style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
            ForEach(["G1", "G2", "G3", "G4"], id: \.self) { group in
                let items = template.topics.filter { $0.group == group }
                if !items.isEmpty || group == "G4" {
                    VStack(alignment: .leading, spacing: 6) {
                        Button { withAnimation(.easeInOut(duration: 0.22)) { expandedTopicGroup = expandedTopicGroup == group ? nil : group } } label: {
                            HStack {
                                Text("\(group) · \(topicGroupName(group))").font(NovaFont.font(.bodyStrong))
                                Spacer()
                                Text(formatDuration(items.reduce(0) { $0 + $1.instruction_minutes })).font(NovaFont.font(.meta))
                                Image(systemName: expandedTopicGroup == group ? "chevron.up" : "chevron.down").font(.system(size: 11))
                            }
                        }.buttonStyle(NovaRowPressStyle())
                        if expandedTopicGroup == group {
                            ForEach($template.topics) { binding in
                                if binding.wrappedValue.group == group {
                                    NovaEducationTopicEditor(topic: binding,
                                        removable: group == "G4" || !basicCycle || binding.wrappedValue.parent_code != nil,
                                        defaultMinutes: context.package.topics(cycle: template.cycle, hazard: template.hazard_class ?? "low")
                                            .first { $0.code == binding.wrappedValue.code }?.instruction_minutes ?? 30,
                                        remove: { template.topics.removeAll { $0.code == binding.wrappedValue.code }; recomputeLessons() })
                                }
                            }
                            if group == "G4" {
                                Button("Konu ekle", systemImage: "plus") {
                                    template.topics.append(.init(code: "G4-" + UUID().uuidString, group: "G4", title: "", instruction_minutes: 0))
                                }.font(NovaFont.font(.bodyStrong))
                            }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: "Toplam öğretim: \(formatDuration(template.net))", style: .bodyStrong)
                NovaText(text: "Planlanan eğitim: \(scheduleDays.count) gün · \(formatDuration(template.net + template.breakTotal)) (molalar dahil)", style: .metaQuiet)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            if let preset = context.package.preset(cycle: template.cycle, hazard: template.hazard_class ?? ""),
               template.net < preset.default_instruction_minutes {
                NovaText(text: "Bu eğitim profili için önerilen öğretim süresi \(formatDuration(preset.default_instruction_minutes)). Konu dakikalarını kontrol edin.",
                    style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
            if context.package.preset(cycle: template.cycle, hazard: template.hazard_class ?? "") != nil {
                area("İşyerine özgü eğitim açıklaması (isteğe bağlı)", $template.context_note, id: "education.context")
            }
        }.disabled(!canWrite)
    }

    private func topicGroupName(_ group: String) -> String {
        ["G1": "Genel", "G2": "Sağlık", "G3": "Teknik", "G4": "İşyerine özgü"][group] ?? group
    }

    private func refreshTemplateDefaults() {
        let method = methodBinding.wrappedValue
        let trainerIDs = draft.trainers.map(\.id)
        let curriculum = draft.scopes.first.flatMap { s in context.curricula.first {
            $0.company_id == s.company_id && $0.workplace_id == s.workplace_id && $0.education.cycle == template.cycle && $0.education.hazard_class == (template.hazard_class ?? "low")
        } }
        template.topics = curriculum?.education.topics ?? context.package.topics(cycle: template.cycle, hazard: template.hazard_class ?? "low")
        applyMethod(method)
        for i in template.topics.indices { template.topics[i].trainer_ids = trainerIDs }
        template.context_note = curriculum?.education.context_note ?? ""
        scheduleDays = NovaEducationClock.initialDays(minutes: template.net, basic: basicCycle)
        recomputeLessons()
    }
    private func formatDuration(_ minutes: Int) -> String {
        let hours = minutes / 60; let mins = minutes % 60
        if hours == 0 { return "\(mins) dk" }
        if mins == 0 { return "\(hours) sa" }
        return "\(hours) sa \(mins) dk"
    }

    // MARK: - Schedule step: realized days/hours and location

    private var basicCycle: Bool { ["initial","periodic_repeat"].contains(template.cycle) }

    /// Each 45+15-minute lesson unit belongs to one user-editable day.
    /// The standard 16-unit profile starts as two eight-hour days.
    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: "Önerilen plan: \(neededScheduleDays) gün. Gün, başlangıç saati ve günlük ders süresi değiştirilebilir.", style: .metaQuiet)
            if scheduleDays.count != neededScheduleDays {
                Button("Önerilen \(neededScheduleDays) güne dön") { resetRecommendedDays() }
                    .font(NovaFont.font(.bodyStrong))
            }
            ForEach($scheduleDays) { $day in
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Eğitim günü", selection: $day.starts, in: ...Date(), displayedComponents: .date)
                        .environment(\.timeZone, NovaEducationClock.calendar.timeZone)
                    DatePicker("Başlangıç saati", selection: $day.starts, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, NovaEducationClock.calendar.timeZone)
                    if basicCycle {
                        Stepper("Günlük eğitim: \(day.lessonCount) saat (molalar dahil)", value: $day.lessonCount, in: 1...8)
                            .font(NovaFont.font(.bodyStrong))
                    }
                    if let range = dayRange(day.id) {
                        NovaText(text: "Hesaplanan saat: \(range) (molalar dahil)", style: .bodyStrong)
                    }
                    if scheduleDays.count > neededScheduleDays {
                        Button("Bu günü kaldır", role: .destructive) {
                            scheduleDays.removeAll { $0.id == day.id }
                            rebalanceScheduleDays()
                        }
                            .font(NovaFont.font(.meta))
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            }
            if basicCycle && scheduleDays.count < requiredLessonUnits {
            Button(RDLocalization.string("localizable.nova.education.schedule.addday", table: .localizable, fallback: "Gün ekle"), systemImage: "calendar.badge.plus") {
                let last = scheduleDays.last?.starts ?? Date()
                scheduleDays.append(.init(starts: NovaEducationClock.calendar.date(byAdding: .day, value: 1, to: last) ?? last, lessonCount: 1))
                rebalanceScheduleDays()
            }
            }
            Text(String(format: RDLocalization.string("localizable.nova.education.schedule.total", table: .localizable, fallback: "Toplam: %@ (mola dahil)"), formatDuration(template.net + requiredLessonUnits * (basicCycle ? 15 : 0))))
                .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
            if !scheduleDistributionValid {
                NovaText(text: "Günlere dağıtılan toplam \(scheduleDays.reduce(0) { $0 + $1.lessonCount }) saat; bu eğitim için \(requiredLessonUnits) saat olmalı. Günlük süreleri veya tarihleri kontrol edin.",
                    style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
            if !scheduleEndsInPast {
                NovaText(text: "Eğitimin bitiş saati henüz gelmemiş görünüyor. Gerçekleşen eğitim kaydı için gün ve başlangıç saatini kontrol edin.",
                    style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
            }
            field("Eğitim yeri / online bağlantı (isteğe bağlı)", $template.location, id: "education.location")
        }.disabled(!canWrite)
    }
    /// The visible start–end range for one scheduled day, computed from the
    /// lessons `recomputeLessons()` already placed on it.
    private func dayRange(_ dayID: UUID) -> String? {
        guard let day = scheduleDays.first(where: { $0.id == dayID }) else { return nil }
        let key = NovaEducationClock.day(day.starts)
        let dayLessons = template.lessons.filter { NovaEducationClock.date($0.starts_at).map { NovaEducationClock.day($0) } == key }
            .sorted { $0.starts_at < $1.starts_at }
        guard let first = dayLessons.first, let last = dayLessons.last,
              let start = NovaEducationClock.date(first.starts_at), let lastStart = NovaEducationClock.date(last.starts_at) else { return nil }
        let end = lastStart.addingTimeInterval(Double(last.instruction_minutes + last.break_minutes) * 60)
        let f = DateFormatter(); f.calendar = NovaEducationClock.calendar; f.timeZone = NovaEducationClock.calendar.timeZone
        f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "HH:mm"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
    /// Splits the topic minutes evenly across whichever days are listed and
    /// lets NovaEducationClock place the actual 45+15 lesson/break blocks —
    /// the one place lessons/schedule get computed, called whenever the
    /// days, the topics, or the cycle change.
    /// A training that cannot fit in one working day (more than 8
    /// lesson-units, ~8 saat) needs at least this many days — a 16-hour
    /// training is two days no matter what the schedule step currently
    /// lists, not just once the expert notices it does not fit.
    private var neededScheduleDays: Int {
        guard template.net > 0 else { return 1 }
        return max(1, (requiredLessonUnits + 7) / 8)
    }
    private var requiredLessonUnits: Int {
        basicCycle ? max(1, Int((Double(template.net) / 45.0).rounded(.up))) : 1
    }
    private var scheduleDistributionValid: Bool {
        guard !scheduleDays.isEmpty,
              scheduleDays.reduce(0, { $0 + $1.lessonCount }) == requiredLessonUnits,
              scheduleDays.allSatisfy({ $0.lessonCount >= 1 && $0.lessonCount <= (basicCycle ? 8 : 1) }) else { return false }
        return Set(scheduleDays.map { NovaEducationClock.day($0.starts) }).count == scheduleDays.count
    }
    private func rebalanceScheduleDays() {
        guard !scheduleDays.isEmpty else { return }
        while scheduleDays.count < neededScheduleDays {
            let last = scheduleDays.last?.starts ?? Date()
            scheduleDays.append(.init(starts: NovaEducationClock.calendar.date(byAdding: .day, value: 1, to: last) ?? last, lessonCount: 1))
        }
        let units = requiredLessonUnits
        for i in scheduleDays.indices {
            scheduleDays[i].lessonCount = units / scheduleDays.count + (i < units % scheduleDays.count ? 1 : 0)
        }
        recomputeLessons()
    }
    private func resetRecommendedDays() {
        let first = scheduleDays.first?.starts ?? NovaEducationClock.initialDays(minutes: template.net, basic: basicCycle)[0].starts
        scheduleDays = (0..<neededScheduleDays).map { offset in
            .init(starts: NovaEducationClock.calendar.date(byAdding: .day, value: offset, to: first) ?? first, lessonCount: 1)
        }
        rebalanceScheduleDays()
    }
    private func recomputeLessons() {
        guard template.net > 0 else { template.lessons = []; return }
        if scheduleDays.isEmpty { scheduleDays = NovaEducationClock.initialDays(minutes: template.net, basic: basicCycle) }
        template.lessons = scheduleDistributionValid
            ? NovaEducationClock.distribute(topics: template.topics, days: scheduleDays, basic: basicCycle)
            : []
        template.draft_days = scheduleDays
    }

    // MARK: - Trainers step (unchanged)

    private var trainersStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let me = app.profile?.fullName, !me.isEmpty,
               !draft.trainers.contains(where: { $0.name == me }) {
                Button {
                    let details = [app.profile?.title, app.profile?.certificateNumber].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    draft.trainers.append(.init(name: me, title: details))
                    advanceIfComplete(.trainers)
                } label: {
                    Label("Ben eğiticiyim", systemImage: "person.crop.circle.badge.checkmark")
                }.font(NovaFont.font(.bodyStrong))
            }
            ForEach($draft.trainers) { $trainer in
                NovaCard(padding: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: trainer.name.isEmpty ? "Yeni eğitici" : trainer.name, style: .bodyStrong)
                                if !trainer.title.isEmpty { NovaText(text: trainer.title, style: .metaQuiet) }
                            }
                            Spacer()
                            Button(editingTrainerID == trainer.id ? "Bitti" : "Düzenle") {
                                editingTrainerID = editingTrainerID == trainer.id ? nil : trainer.id
                            }.font(NovaFont.font(.meta))
                        }
                        if editingTrainerID == trainer.id || trainer.name.isEmpty {
                            field(RDLocalization.string("localizable.nova.education.field.trainername", table: .localizable, fallback: "Eğitici adı soyadı"),
                                $trainer.name, id: "education.trainer.name.\(trainer.id)")
                            field(RDLocalization.string("localizable.nova.education.field.trainertitle", table: .localizable, fallback: "Unvan / belge bilgisi"),
                                $trainer.title, id: "education.trainer.title.\(trainer.id)")
                        }
                        if draft.trainers.count > 1 {
                            // onChange(of: draft.trainers) resyncs every
                            // topic's trainer_ids to match afterward.
                            Button(RDLocalization.string("localizable.nova.education.trainer.remove", table: .localizable, fallback: "Eğiticiyi kaldır"),
                                role: .destructive) { draft.trainers.removeAll { $0.id == trainer.id } }.font(NovaFont.font(.meta))
                        }
                    }
                }
            }
            HStack {
                NovaButton(label: RDLocalization.string("localizable.nova.education.trainer.add", table: .localizable, fallback: "Eğitici ekle"),
                    symbol: "plus", variant: .surface) {
                        let trainer = NovaEducationTrainer()
                        draft.trainers.append(trainer)
                        editingTrainerID = trainer.id
                    }
            }
        }.disabled(!canWrite)
    }

    // MARK: - Participants for the companies chosen in step one.

    private var participantsStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: "Her firma/işyeri seçiminden en az bir katılımcı seçin. Aynı kişi eğitimde bir kez yer alabilir.", style: .metaQuiet)
            if let summary = sectionSummary(.participants) { NovaText(text: summary, style: .bodyStrong) }
            NovaButton(label: "Katılımcıları düzenle", symbol: "person.3", variant: .surface) {
                participantCompany = nil
                participantDepartment = ""; participantJob = ""; selectedParticipantsOnly = false
                showingParticipants = true
            }
        }.disabled(!canWrite)
    }

    private var participantsPicker: some View {
        let scopeIndices = draft.scopes.indices.filter { participantCompany == nil || draft.scopes[$0].company_id == participantCompany }
        let companyIDs = Array(Set(draft.scopes.map(\.company_id))).sorted { a, b in
            (draft.scopes.first { $0.company_id == a }?.company_name ?? "") <
            (draft.scopes.first { $0.company_id == b }?.company_name ?? "")
        }
        let candidates = scopeIndices.flatMap { index in
            (people[draft.scopes[index].company_id] ?? []).map { ParticipantCandidate(scopeIndex: index, person: $0) }
        }
        let departments = Array(Set(candidates.compactMap { $0.person.departmentName })).sorted()
        let jobs = Array(Set(candidates.compactMap { $0.person.jobTitle })).sorted()
        let matches = candidates.filter { candidate in
            (participantSearch.isEmpty || candidate.person.name.localizedCaseInsensitiveContains(participantSearch)) &&
            (participantDepartment.isEmpty || candidate.person.departmentName == participantDepartment) &&
            (participantJob.isEmpty || candidate.person.jobTitle == participantJob) &&
            (!selectedParticipantsOnly || draft.scopes[candidate.scopeIndex].participants.contains { $0.id == candidate.person.id })
        }
        return NovaPageSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NovaText(text: "Katılımcılar", style: .screenTitle)
                    Spacer()
                    Button("Bitti") { showingParticipants = false; advanceIfComplete(.participants) }
                        .font(NovaFont.font(.bodyStrong))
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                }
                NovaText(text: "Eğitimdeki tüm firmaların personeli gösteriliyor. İsterseniz firmaya göre filtreleyin.", style: .metaQuiet)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        participantCompanyChip("Tüm firmalar", selected: participantCompany == nil) {
                            participantCompany = nil; participantDepartment = ""; participantJob = ""
                        }
                        ForEach(companyIDs, id: \.self) { company in
                            participantCompanyChip(draft.scopes.first { $0.company_id == company }?.company_name ?? "Firma",
                                selected: participantCompany == company) {
                                participantCompany = company; participantDepartment = ""; participantJob = ""
                            }
                        }
                    }
                }
                NovaCard(padding: 14) {
                    HStack(spacing: 10) {
                        NovaIcon(symbol: "magnifyingglass", size: 18)
                        TextField("Personel ara", text: $participantSearch)
                            .font(NovaFont.font(.body))
                            .accessibilityIdentifier("education.participants.search")
                        if !participantSearch.isEmpty {
                            Button { participantSearch = "" } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Aramayı temizle")
                        }
                    }
                }
                HStack(spacing: 8) {
                    participantFilter("Departman", value: participantDepartment, values: departments) { participantDepartment = $0 }
                    participantFilter("Görev", value: participantJob, values: jobs) { participantJob = $0 }
                }
                HStack {
                    Button {
                        selectedParticipantsOnly.toggle()
                    } label: {
                        Label("Yalnız seçilenler", systemImage: selectedParticipantsOnly ? "checkmark.circle.fill" : "circle")
                            .font(NovaFont.font(.meta))
                            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    }.buttonStyle(NovaRowPressStyle())
                    Spacer()
                    Button("Görünenlerin tümünü seç") {
                        for candidate in matches {
                            let person = candidate.person
                            if !draft.scopes.contains(where: { $0.participants.contains { $0.id == person.id } }) {
                                draft.scopes[candidate.scopeIndex].participants.append(.init(id: person.id, name: person.name,
                                    job_title: person.jobTitle ?? "", department: person.departmentName))
                            }
                        }
                    }.font(NovaFont.font(.meta))
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                }.padding(.horizontal, 4)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if matches.isEmpty { NovaText(text: "Eşleşen personel bulunamadı.", style: .metaQuiet) }
                        ForEach(matches) { candidate in
                            participantRow(candidate)
                        }
                    }
                }
                NovaButton(label: "\(draft.scopes.reduce(0) { $0 + $1.participants.count }) kişiyi ekle", symbol: "checkmark", variant: .primary) {
                    showingParticipants = false
                    advanceIfComplete(.participants)
                }
            }.padding(20)
        }
    }

    private func participantCompanyChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(NovaFont.font(.meta))
                .foregroundStyle(selected ? NovaColorToken.accentInk.color(in: scheme) : NovaFont.secondaryInk)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .background(selected ? NovaColorToken.accent.color(in: scheme).opacity(0.16) : NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
        }.buttonStyle(NovaRowPressStyle())
    }

    private func participantFilter(_ title: String, value: String, values: [String], select: @escaping (String) -> Void) -> some View {
        Menu {
            Button("Tümü") { select("") }
            ForEach(values, id: \.self) { item in Button(item) { select(item) } }
        } label: {
            HStack(spacing: 6) {
                Text(value.isEmpty ? title : value).lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(NovaFont.font(.meta))
            .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
            .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func participantRow(_ candidate: ParticipantCandidate) -> some View {
        let index = candidate.scopeIndex
        let person = candidate.person
        let selected = participantBinding(idx: index, person: person).wrappedValue
        let selectedElsewhere = draft.scopes.enumerated().contains { $0.offset != index && $0.element.participants.contains { $0.id == person.id } }
        let scope = draft.scopes[index]
        return Button { participantBinding(idx: index, person: person).wrappedValue.toggle() } label: {
            NovaCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 23))
                        .foregroundStyle(selected ? NovaColorToken.accent.color(in: scheme) : NovaFont.secondaryInk)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(NovaFont.font(.bodyStrong))
                        Text([scope.company_name, scope.workplace_name, person.departmentName, person.jobTitle]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }.buttonStyle(NovaRowPressStyle()).disabled(selectedElsewhere)
    }

    /// A compact final checkpoint makes the flow explicit. It
    /// mirrors the payload that will be sent and keeps the primary action in
    /// the same place for both new and edited records.
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: "Kaydetmeden önce kontrol edin", style: .sectionTitle)
            NovaCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    reviewRow("Eğitim", draft.title.isEmpty ? template.cycleName : draft.title, step: .info)
                    reviewRow("Toplam süre", formatDuration(template.net + template.breakTotal), step: .topics)
                    reviewRow("Gün sayısı", "\(scheduleDays.count) gün", step: .schedule)
                    reviewRow("Eğiticiler", "\(draft.trainers.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) kişi", step: .trainers)
                    reviewRow("Katılımcılar", "\(draft.scopes.reduce(0) { $0 + $1.participants.count }) kişi", step: .participants)
                    reviewRow("Firma / işyeri", draft.scopes.map { [$0.company_name, $0.workplace_name].compactMap { $0 }.joined(separator: " · ") }.joined(separator: ", "), step: .companies)
                }
            }
            NovaText(text: "Bu özet onaylandığında eğitim kaydı ve kişi bazlı katılım bilgisi oluşturulur.", style: .metaQuiet)
        }
    }

    private func reviewRow(_ label: String, _ value: String, step: NovaEducationStep) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                NovaText(text: label, style: .metaQuiet)
                Spacer(minLength: 8)
                Button("Düzenle") { returningToReview = true; currentStep = step }.font(NovaFont.font(.meta))
            }
            NovaText(text: value.isEmpty ? "Belirtilmedi" : value, style: .bodyStrong)
        }
    }
    private func participantBinding(idx: Int, person: NovaEmployeeRow) -> Binding<Bool> {
        Binding(get: { draft.scopes[idx].participants.contains { $0.id == person.id } },
            set: { on in
                if on && !draft.scopes.contains(where: { $0.participants.contains { $0.id == person.id } }) {
                    draft.scopes[idx].participants.append(.init(id: person.id, name: person.name, job_title: person.jobTitle ?? "", department: person.departmentName))
                }
                else { draft.scopes[idx].participants.removeAll { $0.id == person.id } }
            })
    }

    /// A scope targets a workplace when one exists, otherwise the company.
    private func pick(company: UUID, workplace: UUID?) {
        if let workplace {
            guard context.workplaces.contains(where: { $0.id == workplace && $0.company_id == company }) else { return }
        } else {
            guard !context.workplaces.contains(where: { $0.company_id == company }) else { return }
        }
        guard !draft.scopes.contains(where: { $0.company_id == company && $0.workplace_id == workplace }) else { return }
        add(company: company, workplace: workplace)
    }

    private var saveButton: some View {
        VStack(spacing: 8) {
            NovaButton(label: RDLocalization.string("localizable.nova.education.save", table: .localizable, fallback: "Gerçekleşen eğitimi kaydet"),
                symbol: "checkmark", variant: .primary, isLoading: busy) { submitEducation() }
                .disabled(!canWrite || busy || preparingCertificates || pending || !ready)
                .accessibilityIdentifier("education.save")
            // The draft is already autosaved on every edit — this button
            // just makes that explicit and lets the expert leave knowing
            // it, instead of only ever finding out on the next visit's
            // "taslağınız geri yüklendi" notice.
            NovaButton(label: RDLocalization.string("localizable.nova.education.savedraft", table: .localizable, fallback: "Taslak olarak kaydet"),
                symbol: "tray.and.arrow.down", variant: .surface) {
                try? service.preserve(draft); dismiss()
            }.disabled(!canWrite || busy).accessibilityIdentifier("education.savedraft")
        }
    }

    private func submitEducation() {
        error = nil
        fillContextFromSelectedTraining()
        if let missing = firstMissingField() {
            validationStep = missing.0
            validationMessage = missing.1
            if missing.0 == .topics {
                expandedTopicGroup = template.topics.first { $0.instruction_minutes <= 0 || $0.title.isEmpty }?.group ?? "G4"
            }
            returningToReview = true
            currentStep = missing.0
            return
        }
        validationStep = nil; validationMessage = nil
        Task { await save() }
    }

    /// A certificate needs a factual scope summary, not another form. Use
    /// only the companies, workplaces and G4 topics the expert already chose.
    private func fillContextFromSelectedTraining() {
        guard context.package.preset(cycle: template.cycle, hazard: template.hazard_class ?? "") != nil,
              template.context_note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let places = draft.scopes.map { $0.workplace_name ?? $0.company_name ?? "" }.filter { !$0.isEmpty }
        let topics = template.topics.filter { $0.group == "G4" }.map(\.title).filter { !$0.isEmpty }
        guard !places.isEmpty, !topics.isEmpty else { return }
        let summary = "Eğitim kapsamı: \(places.joined(separator: ", ")). İşlenen işyerine özgü konular: \(topics.joined(separator: ", "))."
        template.context_note = String(summary.prefix(4000))
        for index in draft.scopes.indices { draft.scopes[index].context_note = template.context_note }
    }

    /// The same inputs that the certificate needs are checked before writing
    /// the training record, so a missing field opens its own accordion card.
    private func firstMissingField() -> (NovaEducationStep, String)? {
        if !draft.isComplete(.companies) { return (.companies, "Eğitim için en az bir firma/işyeri seçin. Tehlike sınıfları aynı olmalı.") }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            draft.provider_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return (.info, "Eğitim türünü ve düzenleyici kişi veya kurumu tamamlayın.")
        }
        if template.topics.isEmpty || template.topics.contains(where: {
            $0.instruction_minutes <= 0 || $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            return (.topics, "Eğitim konularının dakikalarını tamamlayın.")
        }
        if let preset = context.package.preset(cycle: template.cycle, hazard: template.hazard_class ?? "") {
            let selectedCodes = Set(template.topics.filter { $0.instruction_minutes > 0 }.map { $0.parent_code ?? $0.code })
            if context.package.topics.contains(where: { !selectedCodes.contains($0.code) }) {
                return (.topics, "Zorunlu eğitim konularını tamamlayın.")
            }
            if template.net < preset.default_instruction_minutes || template.group4 < preset.group4.budget_instruction_minutes {
                return (.topics, "Eğitim süresi ve işyerine özgü konu dakikaları seçilen eğitim için yeterli olmalı.")
            }
        }
        if !draft.isComplete(.trainers) { return (.trainers, "En az bir eğitici adı girin.") }
        if template.topics.contains(where: { $0.trainer_ids.isEmpty }) {
            return (.topics, "Konulara en az bir eğitici atayın.")
        }
        if template.topics.contains(where: { topic in
            (template.cycle == "onboarding" || (topic.group == "G4" && template.hazard_class != "low")) && topic.method == "online"
        }) {
            return (.info, "Bu eğitimde işyerine özgü konular için yüz yüze yöntemi seçin.")
        }
        if !draft.isComplete(.schedule) || !scheduleEndsInPast {
            return (.schedule, "Eğitim gün ve saatlerini kontrol edin. Dersler çakışmamalı ve tamamı geçmişte olmalı.")
        }
        if !draft.isComplete(.participants) { return (.participants, "Her seçilen firma/işyeri için en az bir katılımcı seçin.") }
        return nil
    }

    @ViewBuilder private var certificates: some View {
        if let saved, !changed {
            NovaCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.education.certificates.title", table: .localizable, fallback: "Kişisel belgeler"), style: .cardTitle)
                    if preparingCertificates { NovaText(text: "Sertifikalar otomatik hazırlanıyor…", style: .metaQuiet) }
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
                                    NovaText(text: preparingCertificates && known == nil ? "Hazırlanıyor…" : "Sertifikayı aç",
                                        style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                                }.padding(.vertical, 5)
                            }.disabled(preparingCertificates || (!canWrite && known == nil))
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
                syncTemplateFromScopes()
                selectedCycle = draft.scopes.first?.cycle ?? ""
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
                showingRestoredBanner = true
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
            syncTemplateFromScopes()
            selectedCycle = (original != nil || restoredDraft || pending) ? (draft.scopes.first?.cycle ?? (draft.title.isEmpty ? "" : template.cycle)) : ""
            ready = true
            if original == nil, !restoredDraft, !pending, draft.scopes.isEmpty,
               let initialCompany, context.workplaces.contains(where: { $0.company_id == initialCompany }) {
                showingCompanies = true
            }
            if restoredDraft {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    withAnimation { showingRestoredBanner = false }
                }
            }
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
                let wp = context.workplaces.first(where: { $0.company_id == company.company_id })
                add(company: company.company_id, workplace: wp?.id, seed: false)
                if let i = draft.scopes.indices.last {
                    draft.scopes[i].participants = company.participants.map { .init(id: $0.id, name: $0.name) }
                }
            }
        } else {
            // A genuinely new record: trainers start empty. Silently
            // seeding the signed-in expert's own name here used to make
            // "Eğiticiler" read as finished before anyone had chosen
            // one — trainersStep offers the same name as a one-tap
            // "Kendimi ekle" instead, so it stays fast but deliberate.
            // The title is derived after the expert explicitly chooses a cycle.
            if let company = initialCompany, !context.workplaces.contains(where: { $0.company_id == company }) {
                add(company: company, workplace: nil)
            }
        }
    }
    /// `template` mirrors whichever real curriculum already exists (editing
    /// or migrating), or gets a first, editable preview (a brand-new
    /// record) so the info step's topics link has something to show right
    /// away instead of waiting for a company to be picked.
    private func syncTemplateFromScopes() {
        if let first = draft.scopes.first {
            template.cycle = first.cycle; template.topics = first.topics; template.context_note = first.context_note
            template.lessons = first.lessons; template.draft_days = first.draft_days; template.location = first.location
            template.hazard_class = first.hazard_class
        } else if template.topics.isEmpty {
            template.hazard_class = "low"
            template.topics = context.package.topics(cycle: template.cycle, hazard: "low")
        }
        scheduleDays = template.draft_days ?? NovaEducationClock.days(from: template.lessons)
        // A record with topics but nothing scheduled yet (a brand-new one,
        // or a legacy record migrated with no realized hours) gets one
        // default day so the duration/schedule shown is real from the
        // start rather than waiting for the expert to open this step.
        if scheduleDays.isEmpty { scheduleDays = NovaEducationClock.initialDays(minutes: template.net, basic: basicCycle) }
        if !scheduleDistributionValid {
            let lessonDays = NovaEducationClock.days(from: template.lessons)
            if lessonDays.count == scheduleDays.count {
                for i in scheduleDays.indices {
                    if let matched = lessonDays.first(where: { NovaEducationClock.day($0.starts) == NovaEducationClock.day(scheduleDays[i].starts) }) {
                        scheduleDays[i].lessonCount = matched.lessonCount
                    }
                }
            }
            if !scheduleDistributionValid { rebalanceScheduleDays() }
        }
        recomputeLessons()
    }
    private func discardDraft() {
        try? service.discardDraft(id: original?.id)
        draft = NovaEducationDraft(); template = NovaEducationScope(company_id: UUID(), workplace_id: nil)
        restoredDraft = false; showingRestoredBanner = false; notice = nil
        seedFreshDraft()
        syncTemplateFromScopes()
        selectedCycle = original == nil ? "" : (draft.scopes.first?.cycle ?? template.cycle)
        Task { for company in Set(draft.scopes.map(\.company_id)) { await loadPeople(company) } }
    }
    private func add(company: UUID, workplace: UUID?, seed: Bool = true) {
        guard let companyRow = companies.first(where: { $0.id == company }) else { return }
        let wp = workplace.flatMap { id in context.workplaces.first { $0.id == id && $0.company_id == company } }
        guard workplace == nil || wp != nil else { return }
        guard workplace != nil || !context.workplaces.contains(where: { $0.company_id == company }) else { return }
        let hazard = wp?.hazard_class ?? companyRow.hazard_class
        // One training session is one curriculum: a company at "az
        // tehlikeli" and one at "çok tehlikeli" cannot sit in the same
        // record, since the mandated topics/minutes genuinely differ.
        // (Not checked for `seed == false`, the legacy-record migration
        // path, which is replaying history rather than composing a new
        // record and must not lose companies over this.)
        if seed, !draft.scopes.isEmpty, template.hazard_class != hazard {
            error = "\(hazardLabel(template.hazard_class ?? "")) ve \(hazardLabel(hazard)) sınıfındaki firmalar aynı eğitim dosyasında yer alamaz. Ayrı bir eğitim kaydı açın."
            return
        }
        if seed, draft.scopes.isEmpty, template.hazard_class != hazard {
            // The first real company: the preview hazard class (a guess, or
            // whatever was picked in the topics popup before any company
            // existed) gives way to reality. Official cycles' topics refresh
            // to match; a custom cycle has no hazard dependency and is left
            // exactly as the expert defined it.
            let method = methodBinding.wrappedValue
            if template.cycle != "custom" { template.topics = context.package.topics(cycle: template.cycle, hazard: hazard) }
            template.hazard_class = hazard
            applyMethod(method)
            for i in template.topics.indices { template.topics[i].trainer_ids = draft.trainers.map(\.id) }
            scheduleDays = NovaEducationClock.initialDays(minutes: template.net, basic: basicCycle)
            recomputeLessons()
        }
        var scope = NovaEducationScope(company_id: company, workplace_id: workplace,
            company_name: companyRow.name, workplace_name: wp?.name, hazard_class: hazard)
        if seed {
            scope.cycle = template.cycle
            scope.topics = template.topics
            scope.context_note = template.context_note; scope.lessons = template.lessons; scope.draft_days = template.draft_days
            scope.location = template.location
            // İşyeri unvanı / işveren vekili are no longer asked for here —
            // they should already live on the company's own record, which
            // does not exist yet, so a real name (the workplace's own) and a
            // plain placeholder stand in; both are still editable later if
            // a real signer name is needed for a specific printout.
            scope.legal_name = wp?.name ?? companyRow.name
            scope.employer_name = ""
        }
        draft.scopes.append(scope)
        error = nil
        Task { await loadPeople(company) }
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
            let row: NovaTrainingSession
            if let saved, !changed { row = saved }
            else {
                saveProgress = "Eğitim kaydediliyor…"
                let result = try await service.save(draft)
                guard let committed = result.row, let education = committed.education else { throw NovaPersonnelFailure.unavailable }
                row = committed
                saved = committed; draft.id = committed.id; draft.expected_version = committed.version
                draft.scopes = education.scopes; draft.trainers = education.trainers
            }
            guard row.education != nil else { throw NovaPersonnelFailure.unavailable }
            notice = "Eğitim başarıyla kaydedildi. Sertifikalar hazırlanıyor…"
            saveProgress = nil
            certificateJump = UUID()
            preparingCertificates = true
            Task { await prepareCertificates(for: row) }
        } catch {
            saveProgress = nil
            self.error = NovaEducationService.message(error)
            pending = (try? service.pending()) != nil
        }
    }

    private func prepareCertificates(for row: NovaTrainingSession) async {
        defer { preparingCertificates = false; saveProgress = nil }
        guard let education = row.education else { return }
        let targets = education.scopes.flatMap { scope in scope.participants.map { (scope.id, $0.id) } }
        var completed = 0
        var blocked: [String] = []
        var failures = 0
        for (index, target) in targets.enumerated() {
            saveProgress = "Sertifikalar hazırlanıyor · \(index + 1)/\(targets.count)"
            do {
                let certificate = try await service.certificate(.init(action: "issue", session_id: row.id,
                    scope_id: target.0, person_id: target.1, expected_version: row.version,
                    issued_on: NovaEducationClock.day(Date())))
                if certificate.ready && certificate.document_id != nil { completed += 1 }
                else { blocked += certificate.issues }
            } catch { failures += 1 }
        }
        // Only refresh document links here. The expert may already be editing
        // the next change while certificates are issued in the background.
        if let latest = try? await service.context(id: row.id) { certificatesKnown = latest.certificates }
        if let issue = blocked.first {
            let step: NovaEducationStep = ["LESSON_TOPIC_MISMATCH", "LESSON_BREAK_INVALID"].contains(issue) ? .schedule : .topics
            validationStep = step
            validationMessage = NovaEducationService.issue(issue)
            currentStep = step
            notice = "Eğitim kaydedildi. Sertifikalar için işaretlenen eğitim içeriğini tamamlayın."
        } else if failures > 0 {
            notice = "Eğitim başarıyla kaydedildi. \(completed) sertifika hazır, \(failures) sertifika hazırlanamadı. Tekrar denemek için kaydet düğmesine basın."
        } else {
            notice = "Eğitim başarıyla kaydedildi. \(completed) sertifika hazır; eğitim içeriğinden veya personel kartından açabilirsiniz."
        }
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
}
