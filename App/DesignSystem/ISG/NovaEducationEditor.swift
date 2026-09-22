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
                // five-step editor and remain explicitly marked as migrated.
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

/// The guided five-step form. Only the current step is mounted at a time so
/// the expert never has to scan a long accordion to find the next action.
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
    @State private var template = NovaEducationScope(company_id: UUID(), workplace_id: UUID())
    @State private var scheduleDays: [NovaEducationDay] = []
    @State private var cycleChangePending: String?
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
    @State private var currentStep: NovaEducationStep = .info
    @State private var showingTopics = false
    /// One company expanded at a time in the participants step, with its own
    /// personnel search reset whenever a different company opens.
    @State private var expandedCompany: UUID?
    @State private var personSearch = ""
    @State private var companySearch = ""
    private struct Selection: Identifiable { let id = UUID(); let scope: UUID; let person: UUID; var document: UUID?; var revision: Int? }
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
                        stepCard
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
                        if currentStep == .review {
                            saveButton
                        } else {
                            stepNavigation
                        }
                        certificates
                    }
                }.padding(20).padding(.bottom, novaTabBarInset)
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
        // Topics/minutes open as their own popup from the info step; the rest
        // stay inside the guided flow.
        .novaFullScreenCover(isPresented: $showingTopics, onDismiss: { showingTopics = false; recomputeLessons() }) {
            NovaEducationTopicsPopup(scope: $template, context: context,
                hazardLocked: !draft.scopes.isEmpty,
                saveCurriculum: draft.scopes.isEmpty ? nil : { Task { await saveCurriculum(draft.scopes[0]) } })
        }
        .confirmationDialog(RDLocalization.string("localizable.nova.education.cycle.changed.title", table: .localizable, fallback: "Eğitim türü değişti"),
            isPresented: Binding(get: { cycleChangePending != nil }, set: { if !$0 { cycleChangePending = nil } })) {
            Button(RDLocalization.string("localizable.nova.education.cycle.changed.refresh", table: .localizable, fallback: "Yeni türün varsayılan konularını getir")) { refreshTemplateDefaults(); cycleChangePending = nil }
            Button(RDLocalization.string("localizable.nova.education.cycle.changed.keep", table: .localizable, fallback: "Mevcut konuları koru")) { cycleChangePending = nil }
            Button(RDLocalization.string("localizable.nova.education.cycle.changed.cancel", table: .localizable, fallback: "Vazgeç"), role: .cancel) { if let old = cycleChangePending { template.cycle = old }; cycleChangePending = nil }
        } message: { Text(RDLocalization.string("localizable.nova.education.cycle.changed.message", table: .localizable, fallback: "Mevcut dakikaları değiştirmek isteğe bağlıdır; saatleri değişiklikten sonra yeniden dağıtın.")) }
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

    private var stepCard: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: symbol(currentStep))
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 24)
                    NovaText(text: title(currentStep), style: .cardTitle)
                    Spacer(minLength: 0)
                    NovaStatusPill(label: "\((NovaEducationStep.allCases.firstIndex(of: currentStep) ?? 0) + 1)/\(NovaEducationStep.allCases.count)",
                        status: draft.isComplete(currentStep) ? .success : .warning)
                }
                Divider()
                activeStep
            }
        }.accessibilityIdentifier("education.current-step.\(currentStep.rawValue)")
    }

    @ViewBuilder private var activeStep: some View {
        switch currentStep {
        case .info: infoStep
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
            NovaButton(label: "Devam", symbol: "chevron.right", variant: .primary,
                isEnabled: draft.isComplete(currentStep)) {
                if let next = nextStep { currentStep = next }
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

    private func title(_ step: NovaEducationStep) -> String {
        switch step {
        case .info: return RDLocalization.string("localizable.nova.education.step.info", table: .localizable, fallback: "Eğitim ve düzenleyici")
        case .schedule: return RDLocalization.string("localizable.nova.education.step.schedule", table: .localizable, fallback: "Tarih, saat ve yer")
        case .trainers: return RDLocalization.string("localizable.nova.education.step.trainers", table: .localizable, fallback: "Eğiticiler")
        case .participants: return RDLocalization.string("localizable.nova.education.step.participants", table: .localizable, fallback: "Katılımcılar")
        case .review: return "Kontrol ve kaydet"
        }
    }
    private func symbol(_ step: NovaEducationStep) -> String {
        switch step {
        case .info: return "text.book.closed"
        case .schedule: return "calendar.badge.clock"
        case .trainers: return "person.crop.rectangle"
        case .participants: return "person.3"
        case .review: return "checkmark.circle"
        }
    }
    /// A finished step offers the next unfinished one instead of leaving the
    /// expert to find it.
    @ViewBuilder private func advance(_ step: NovaEducationStep) -> some View {
        if draft.isComplete(step), let next = draft.nextIncomplete(after: step) {
            NovaButton(label: String(format: RDLocalization.string("localizable.nova.education.next", table: .localizable,
                fallback: "Sıradaki: %@"), title(next)), symbol: "chevron.down", variant: .surface) { currentStep = next }
                .accessibilityIdentifier("education.next.\(step.rawValue)")
        }
    }

    // MARK: - Info step: title, curriculum type, method, topics link

    private var infoStep: some View {
        VStack(alignment: .leading, spacing: 8) {
            cyclePicker
            methodQuickToggle
            topicsLink
            field(RDLocalization.string("localizable.nova.education.field.provider", table: .localizable, fallback: "Düzenleyici kişi / kurum"),
                $draft.provider_name, id: "education.provider")
            area(RDLocalization.string("localizable.nova.education.field.notes", table: .localizable, fallback: "Notlar"),
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
            Picker("", selection: $template.cycle) {
                ForEach(NovaEducationScope.cycles, id: \.0) { Text($0.1).tag($0.0) }
            }.pickerStyle(.menu).labelsHidden().accessibilityIdentifier("education.cycle")
                .onChange(of: template.cycle) { [old = template.cycle] _ in
                    cycleChangePending = old
                    draft.title = template.cycleName
                }
        }
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
        }
    }
    private var methodBinding: Binding<String> {
        Binding(get: { template.topics.first?.method ?? "face_to_face" },
            set: { value in for i in template.topics.indices { template.topics[i].method = value } })
    }

    private var topicsLink: some View {
        Button { showingTopics = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard").font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(RDLocalization.string("localizable.nova.education.topics.title", table: .localizable, fallback: "Konuları ve Süre")).font(NovaFont.font(.bodyStrong))
                    // Molalar dahil toplam süre — yalnız ders dakikası
                    // gösterildiğinde "8 saat" gereken bir eğitim "6 saat"
                    // gibi görünüyordu (mola dakikaları hesaba katılmadan).
                    Text("\(template.cycleName) · \(formatDuration(template.net + template.breakTotal))").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
            }
            .padding(12).frame(maxWidth: .infinity)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(NovaRowPressStyle()).foregroundStyle(.primary).accessibilityIdentifier("education.topics.link")
    }

    private func refreshTemplateDefaults() {
        let curriculum = draft.scopes.first.flatMap { s in context.curricula.first {
            $0.company_id == s.company_id && $0.workplace_id == s.workplace_id && $0.education.cycle == template.cycle && $0.education.hazard_class == (template.hazard_class ?? "low")
        } }
        template.topics = curriculum?.education.topics ?? context.package.topics(cycle: template.cycle, hazard: template.hazard_class ?? "low")
        template.context_note = curriculum?.education.context_note ?? ""
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

    /// Just a date+start time per day; the end time, break placement and
    /// lesson blocks are computed automatically from the topic minutes
    /// (NovaEducationClock already implements the government's 45 min
    /// instruction + 15 min break unit) — nothing here is configured by
    /// hand. Multiple days split the total evenly.
    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            field(RDLocalization.string("localizable.nova.education.field.location", table: .localizable, fallback: "Eğitim yeri / online bağlantı açıklaması"),
                $template.location, id: "education.location")
            ForEach($scheduleDays) { $day in
                HStack(spacing: 10) {
                    DatePicker("", selection: $day.starts, in: ...Date()).labelsHidden()
                        .environment(\.timeZone, NovaEducationClock.calendar.timeZone)
                    if let range = dayRange(day.id) {
                        NovaText(text: range, style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    if scheduleDays.count > neededScheduleDays {
                        Button { scheduleDays.removeAll { $0.id == day.id } } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(NovaFont.secondaryInk)
                    }
                }
            }
            Button(RDLocalization.string("localizable.nova.education.schedule.addday", table: .localizable, fallback: "Gün ekle"), systemImage: "calendar.badge.plus") {
                let last = scheduleDays.last?.starts ?? Date()
                scheduleDays.append(.init(starts: NovaEducationClock.calendar.date(byAdding: .day, value: 1, to: last) ?? last, lessonCount: 1))
            }
            Text(String(format: RDLocalization.string("localizable.nova.education.schedule.total", table: .localizable, fallback: "Toplam: %@ (mola dahil)"), formatDuration(template.net + template.breakTotal)))
                .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
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
        let end = lastStart.addingTimeInterval(Double(last.instruction_minutes) * 60)
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
        let units = basicCycle ? max(1, Int((Double(template.net) / 45.0).rounded(.up))) : 1
        return max(1, (units + 7) / 8)
    }
    private func recomputeLessons() {
        guard template.net > 0 else { template.lessons = []; return }
        let units = basicCycle ? max(1, Int((Double(template.net) / 45.0).rounded(.up))) : 1
        if scheduleDays.isEmpty { scheduleDays = [.init(starts: Date(), lessonCount: 1)] }
        while scheduleDays.count < neededScheduleDays {
            let last = scheduleDays.last?.starts ?? Date()
            scheduleDays.append(.init(starts: NovaEducationClock.calendar.date(byAdding: .day, value: 1, to: last) ?? last, lessonCount: 1))
        }
        var days = scheduleDays
        for i in days.indices {
            let share = units / days.count + (i < units % days.count ? 1 : 0)
            days[i].lessonCount = max(1, share)
        }
        template.lessons = NovaEducationClock.distribute(topics: template.topics, days: days, basic: basicCycle)
        template.draft_days = scheduleDays
    }

    // MARK: - Trainers step (unchanged)

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
                    symbol: "plus", variant: .surface) { draft.trainers.append(.init()) }
                if let me = app.profile?.fullName, !me.isEmpty, !draft.trainers.contains(where: { $0.name == me }) {
                    NovaButton(label: RDLocalization.string("localizable.nova.education.trainer.addme", table: .localizable, fallback: "Kendimi ekle"),
                        symbol: "person.fill.checkmark", variant: .surface) { draft.trainers.append(.init(name: me)) }
                }
            }
        }.disabled(!canWrite)
    }

    // MARK: - Participants step: company → workplace → tick people

    /// A hesap can have a hundred companies on it — listing all of them
    /// unconditionally does not scale. Search adds a company; only added
    /// companies (i.e. companies that already have a scope) stay listed
    /// below, so the visible list only ever grows as large as the training
    /// actually needs.
    private var participantsStep: some View {
        let added = companies.filter { writableCompanies.contains($0.id) && scope(for: $0.id) != nil }
        let matches = companySearch.isEmpty ? [] : companies.filter {
            writableCompanies.contains($0.id) && scope(for: $0.id) == nil && $0.name.localizedCaseInsensitiveContains(companySearch)
        }
        return VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.education.participants.explainer", table: .localizable,
                fallback: "Firma arayıp ekleyin; her firmanın altında personelini arayıp tikleyerek katılımcı olarak ekleyebilirsiniz. Aynı eğitime yalnız aynı tehlike sınıfındaki firmaları ekleyebilirsiniz."),
                style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
            HStack {
                Image(systemName: "magnifyingglass")
                TextField(RDLocalization.string("localizable.nova.education.participants.companysearch", table: .localizable, fallback: "Firma ara ve ekle"), text: $companySearch)
            }.padding(10).background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("education.participants.companysearch")
            if !companySearch.isEmpty {
                if matches.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.education.participants.companynomatch", table: .localizable,
                        fallback: "Eşleşen firma yok."), style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                } else {
                    ForEach(matches) { company in
                        Button { addCompany(company) } label: {
                            HStack {
                                NovaText(text: company.name, style: .body)
                                Spacer(minLength: 8)
                                Image(systemName: "plus.circle").font(.system(size: 16))
                            }.padding(10).frame(maxWidth: .infinity)
                                .novaControlBackground(cornerRadius: 10)
                        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("education.participants.add.\(company.id)")
                    }
                }
            }
            ForEach(added) { company in companySection(company) }
        }.disabled(!canWrite)
    }

    /// A compact final checkpoint makes the five-step flow explicit. It
    /// mirrors the payload that will be sent and keeps the primary action in
    /// the same place for both new and edited records.
    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: "Kaydetmeden önce kontrol edin", style: .sectionTitle)
            NovaCard(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    reviewRow("Eğitim", draft.title.isEmpty ? template.cycleName : draft.title)
                    reviewRow("Toplam süre", formatDuration(template.net + template.breakTotal))
                    reviewRow("Gün sayısı", "\(scheduleDays.count) gün")
                    reviewRow("Eğiticiler", "\(draft.trainers.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count) kişi")
                    reviewRow("Katılımcılar", "\(draft.scopes.reduce(0) { $0 + $1.participants.count }) kişi")
                    reviewRow("Firma / işyeri", draft.scopes.map { [$0.company_name, $0.workplace_name].compactMap { $0 }.joined(separator: " · ") }.joined(separator: ", "))
                }
            }
            NovaText(text: "Bu özet onaylandığında eğitim kaydı ve kişi bazlı katılım bilgisi oluşturulur.", style: .metaQuiet)
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            NovaText(text: label, style: .metaQuiet)
            Spacer(minLength: 8)
            NovaText(text: value.isEmpty ? "Belirtilmedi" : value, style: .bodyStrong)
                .multilineTextAlignment(.trailing)
        }
    }
    /// Adds a company straight from the search results: with one eligible
    /// workplace it is picked automatically (still changeable afterward via
    /// the workplace menu below); with more than one, the company opens
    /// expanded so the expert chooses there instead of a second prompt here.
    private func addCompany(_ company: NovaPilotCompanySummary) {
        companySearch = ""
        let places = eligibleWorkplaces(company.id)
        expandedCompany = company.id
        if people[company.id] == nil { Task { await loadPeople(company.id) } }
        if let first = places.first { pick(company: company.id, workplace: first.id) }
    }

    private func scope(for company: UUID) -> NovaEducationScope? { draft.scopes.first { $0.company_id == company } }
    private func scopeIndex(for company: UUID) -> Int? { draft.scopes.firstIndex { $0.company_id == company } }
    /// Once the record already has a hazard class (from its first scope, or
    /// the topics popup's preview picker), only same-class workplaces are
    /// offered here — matching add()'s own guard, so the mismatch error is a
    /// rare fallback rather than the everyday path.
    private func eligibleWorkplaces(_ companyID: UUID) -> [NovaEducationContext.Workplace] {
        let locked = !draft.scopes.isEmpty
        return context.workplaces.filter { $0.company_id == companyID && (!locked || $0.hazard_class == template.hazard_class) }
    }

    @ViewBuilder private func companySection(_ company: NovaPilotCompanySummary) -> some View {
        let isOpen = expandedCompany == company.id
        let currentScope = scope(for: company.id)
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: isOpen ? 10 : 0) {
                Button {
                    expandedCompany = isOpen ? nil : company.id
                    personSearch = ""
                    if !isOpen, people[company.id] == nil { Task { await loadPeople(company.id) } }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: company.name, style: .cardTitle)
                            NovaText(text: String(format: RDLocalization.string("localizable.nova.education.participants.count", table: .localizable, fallback: "%d katılımcı"),
                                currentScope?.participants.count ?? 0), style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("education.company.\(company.id)")
                if isOpen { companyDetail(company, currentScope: currentScope) }
            }
        }
    }

    @ViewBuilder private func companyDetail(_ company: NovaPilotCompanySummary, currentScope: NovaEducationScope?) -> some View {
        let places = eligibleWorkplaces(company.id)
        if places.isEmpty {
            NovaText(text: RDLocalization.string("localizable.nova.education.participants.noworkplace", table: .localizable,
                fallback: "Bu firmada bu eğitimin tehlike sınıfına uygun işyeri yok."), style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
        } else {
            if places.count > 1 || currentScope == nil {
                Menu {
                    ForEach(places) { wp in Button(wp.name) { pick(company: company.id, workplace: wp.id) } }
                } label: {
                    HStack(spacing: 6) {
                        Text(String(format: RDLocalization.string("localizable.nova.education.participants.workplace", table: .localizable, fallback: "İşyeri: %@"),
                            currentScope?.workplace_name ?? places.first!.name))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    }.font(NovaFont.font(.meta))
                }.accessibilityIdentifier("education.company.\(company.id).workplace")
            }
            if let idx = scopeIndex(for: company.id) {
                TextField(RDLocalization.string("localizable.nova.education.participants.search", table: .localizable, fallback: "Personel ara"), text: $personSearch)
                    .textFieldStyle(.roundedBorder)
                let list = people[company.id] ?? []
                let matches = list.filter { personSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(personSearch) }
                if list.isEmpty {
                    NovaText(text: RDLocalization.string("localizable.nova.education.participants.noone", table: .localizable,
                        fallback: "Bu firmada aktif personel yok."), style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                } else {
                    ForEach(matches) { person in
                        Toggle(person.name, isOn: participantBinding(idx: idx, person: person))
                    }
                }
                Button(RDLocalization.string("localizable.nova.education.participants.removecompany", table: .localizable, fallback: "Firmayı kaldır"), role: .destructive) {
                    draft.scopes.removeAll { $0.company_id == company.id }
                    if expandedCompany == company.id { expandedCompany = nil }
                }.font(NovaFont.font(.meta))
            } else {
                // Auto-pick when there is only one eligible workplace, so the
                // expert never has to make a choice that has only one answer.
                if places.count == 1 {
                    Color.clear.frame(height: 0).onAppear { pick(company: company.id, workplace: places[0].id) }
                } else {
                    NovaText(text: RDLocalization.string("localizable.nova.education.participants.pickworkplace", table: .localizable,
                        fallback: "İşyeri seçince personel listesi burada görünür."), style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
        }
    }

    private func participantBinding(idx: Int, person: NovaEmployeeRow) -> Binding<Bool> {
        Binding(get: { draft.scopes[idx].participants.contains { $0.id == person.id } },
            set: { on in
                if on { draft.scopes[idx].participants.append(.init(id: person.id, name: person.name)) }
                else { draft.scopes[idx].participants.removeAll { $0.id == person.id } }
            })
    }

    /// Assigns a workplace to a company already in the record, or adds the
    /// company as a new scope if it has none yet.
    private func pick(company: UUID, workplace: UUID) {
        guard let wp = context.workplaces.first(where: { $0.id == workplace }) else { return }
        if let idx = scopeIndex(for: company) {
            draft.scopes[idx].workplace_id = workplace; draft.scopes[idx].workplace_name = wp.name
            draft.scopes[idx].hazard_class = wp.hazard_class; draft.scopes[idx].legal_name = wp.name
        } else {
            add(company: company, workplace: workplace)
        }
    }

    private var saveButton: some View {
        VStack(spacing: 8) {
            NovaButton(label: RDLocalization.string("localizable.nova.education.save", table: .localizable, fallback: "Gerçekleşen eğitimi kaydet"),
                symbol: "checkmark", variant: .primary) { Task { await save() } }
                .disabled(!canWrite || busy || pending || draft.scopes.isEmpty || !ready)
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
                syncTemplateFromScopes()
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
            syncTemplateFromScopes()
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
            // The title is not asked for anymore; it just names the cycle.
            draft.title = template.cycleName
            if let company = initialCompany, let wp = context.workplaces.first(where: { $0.company_id == company }) { add(company: company, workplace: wp.id) }
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
        if scheduleDays.isEmpty { scheduleDays = [.init(starts: Date(), lessonCount: 1)] }
        recomputeLessons()
    }
    private func discardDraft() {
        try? service.discardDraft(id: original?.id)
        draft = NovaEducationDraft(); template = NovaEducationScope(company_id: UUID(), workplace_id: UUID())
        restoredDraft = false; notice = nil
        seedFreshDraft()
        syncTemplateFromScopes()
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
        if seed, !draft.scopes.isEmpty, template.hazard_class != wp.hazard_class {
            error = String(format: RDLocalization.string("localizable.nova.education.scope.hazardmismatch", table: .localizable,
                fallback: "Bu eğitimin diğer kapsamları %1$@ sınıfında; %2$@ sınıfındaki bir işyeri aynı eğitime eklenemez — tek eğitimde tek tehlike sınıfı olur. Ayrı bir eğitim kaydı açın."),
                hazardLabel(template.hazard_class ?? ""), hazardLabel(wp.hazard_class))
            return
        }
        if seed, draft.scopes.isEmpty, template.hazard_class != wp.hazard_class {
            // The first real company: the preview hazard class (a guess, or
            // whatever was picked in the topics popup before any company
            // existed) gives way to reality. Official cycles' topics refresh
            // to match; a custom cycle has no hazard dependency and is left
            // exactly as the expert defined it.
            if template.cycle != "custom" { template.topics = context.package.topics(cycle: template.cycle, hazard: wp.hazard_class) }
            template.hazard_class = wp.hazard_class
            for i in template.topics.indices { template.topics[i].trainer_ids = draft.trainers.map(\.id) }
            recomputeLessons()
        }
        var scope = NovaEducationScope(company_id: company, workplace_id: workplace,
            company_name: companies.first { $0.id == company }?.name, workplace_name: wp.name, hazard_class: wp.hazard_class)
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
            scope.legal_name = wp.name
            scope.employer_name = RDLocalization.string("localizable.nova.education.scope.employerplaceholder", table: .localizable, fallback: "İşveren vekili")
        }
        draft.scopes.append(scope)
        Task { await loadPeople(company) }
        if seed { expandedCompany = company }
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
