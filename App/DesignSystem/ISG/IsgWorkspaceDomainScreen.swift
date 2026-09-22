import SwiftUI

extension IsgWorkspaceDomain {
    var title: String {
        switch self {
        case .personnel:
            return RDLocalization.string("localizable.nova.workspace.domain.personnel", table: .localizable,
                                         fallback: "Personel")
        case .training: return NovaDestination.training.title
        case .risk: return NovaDestination.riskAssessments.title
        case .nonconformity: return NovaDestination.findings.title
        case .checklist: return NovaDestination.checklists.title
        case .emergencyPlan: return NovaDestination.emergencyPlans.title
        case .drill: return NovaDestination.drills.title
        case .appointment: return NovaDestination.appointments.title
        case .ppe: return NovaDestination.ppeHandovers.title
        case .equipment: return NovaDestination.periodicChecks.title
        case .katip: return NovaDestination.katipContracts.title
        case .annualPlan: return NovaDestination.annualWorkPlans.title
        case .board: return NovaDestination.boardMeetings.title
        case .workPermit: return NovaDestination.workPermits.title
        case .visit: return NovaDestination.visits.title
        case .files: return NovaDestination.documents.title
        }
    }

    var symbol: String {
        switch self {
        case .personnel: return "person.2"
        case .training: return NovaDestination.training.symbol
        case .risk: return NovaDestination.riskAssessments.symbol
        case .nonconformity: return NovaDestination.findings.symbol
        case .checklist: return NovaDestination.checklists.symbol
        case .emergencyPlan: return NovaDestination.emergencyPlans.symbol
        case .drill: return NovaDestination.drills.symbol
        case .appointment: return NovaDestination.appointments.symbol
        case .ppe: return NovaDestination.ppeHandovers.symbol
        case .equipment: return NovaDestination.periodicChecks.symbol
        case .katip: return NovaDestination.katipContracts.symbol
        case .annualPlan: return NovaDestination.annualWorkPlans.symbol
        case .board: return NovaDestination.boardMeetings.symbol
        case .workPermit: return NovaDestination.workPermits.symbol
        case .visit: return NovaDestination.visits.symbol
        case .files: return NovaDestination.documents.symbol
        }
    }
}

/// A workspace-only operational browser. It is intentionally independent of
/// every personal service so an OSGB route cannot accidentally read data via
/// the legacy account owner boundary.
struct IsgWorkspaceDomainScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let companyName: String
    let companyHazardClass: String
    let canOperate: Bool
    var startInAddMode = false
    let onBack: () -> Void
    @State private var snapshot: IsgWorkspaceDomainSnapshot?
    @State private var selected: IsgWorkspaceDomainRecord?
    @State private var query = ""
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()
    @State private var showingCreate = false
    @State private var workplaces: [UUID: String] = [:]
    @State private var employees: [UUID: String] = [:]
    @State private var detailLoadingID: UUID?
    @State private var didPresentInitialCreate = false

    private var rows: [IsgWorkspaceDomainRecord] {
        let source = snapshot?.rows ?? []
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = needle.isEmpty ? source : source.filter { row in
            ([row.title, row.subtitle, row.status].compactMap { $0 } + row.facts.map(\.1))
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
        return filtered.sorted {
            let left = actionPriority($0)
            let right = actionPriority($1)
            if left != right { return left < right }
            return recordTitle($0).localizedStandardCompare(recordTitle($1)) == .orderedAscending
        }
    }

    private var addTitle: String {
        switch domain {
        case .emergencyPlan: return "Plan Ekle"
        case .appointment: return "Atama Ekle"
        case .board: return "Toplantı Ekle"
        case .risk: return "Kayıt Ekle"
        case .training: return "Eğitim Ekle"
        case .equipment: return "Ekipman Ekle"
        default: return "Ekle"
        }
    }

    private var helpText: String {
        switch domain {
        case .emergencyPlan:
            return "Firmanın yürürlükteki acil durum planını, ekibini ve geçerlilik tarihini kaydedin; yenileme zamanını takip edin."
        case .appointment:
            return "Firma personeline çalışan temsilcisi, destek elemanı ve acil durum ekip görevlerini verin; görev süresini takip edin."
        case .board:
            return "Gerçekleşen kurul toplantısının gündemini, katılımcılarını ve kararlarını firma kapsamında kaydedin."
        case .risk:
            return "Firmanın risk değerlendirmesini ve revizyonlarını işyeri bazında kaydedin; geçerlilik durumunu takip edin."
        case .training:
            return "Gerçekleşen eğitimi, katılımcıları ve süreyi kaydedin. Eğitim planlama ve müfredat bu akışın parçası değildir."
        case .equipment:
            return "Firmaya ekipman ekleyin; kontrol sonucu, tarih ve rapor geçmişini tek yerden takip edin."
        default:
            return "\(companyName) firmasına ait yetkili OSGB kayıtları gösteriliyor."
        }
    }

    private var emptyTitle: String {
        switch domain {
        case .emergencyPlan: return "Henüz acil durum planı yok"
        case .appointment: return "Henüz atama kaydı yok"
        case .board: return "Henüz kurul toplantısı kaydı yok"
        case .risk: return "Henüz risk değerlendirmesi yok"
        case .training: return "Henüz gerçekleşen eğitim kaydı yok"
        case .equipment: return "Henüz ekipman kaydı yok"
        default: return "Henüz \(domain.title.lowercased()) kaydı yok"
        }
    }

    private var emptyMessage: String {
        switch domain {
        case .emergencyPlan:
            return "Planı ve görevli ekibi ekleyerek geçerlilik süresini dijital ortamda takip edebilirsiniz."
        case .appointment:
            return "Firma personeline görev vererek çalışan temsilcisi ve destek elemanı kayıtlarını tek yerden izleyebilirsiniz."
        case .board:
            return "Toplantıyı ekleyerek gündemi, katılımcıları ve alınan kararları birlikte takip edebilirsiniz."
        case .risk:
            return "İlk değerlendirmeyi ekleyerek geçerlilik süresini ve sonraki revizyonları takip edebilirsiniz."
        case .training:
            return "Gerçekleşen eğitimi ve katılımcıları ekleyerek eğitim saatlerini ve eksik personeli takip edebilirsiniz."
        case .equipment:
            return "Periyodik kontrole giren ekipmanları ekleyerek kontrol tarihlerini ve raporlarını takip edebilirsiniz."
        default:
            return "Yeni kayıtlar bu firmaya ve yetkili çalışma alanına bağlı olarak burada görünür."
        }
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaListHeading(title: domain.title, onBack: onBack) {
                        if canOperate {
                            NovaButton(label: addTitle, symbol: "plus", compact: true) {
                                showingCreate = true
                            }
                        }
                    }
                    search
                    if let snapshot, !displayMetrics(snapshot.metrics).isEmpty { metrics(snapshot.metrics) }
                    if loading {
                        NovaLoadingView(message: RDLocalization.string(
                            "localizable.nova.workspace.domain.loading", table: .localizable,
                            fallback: "Kayıtlar yükleniyor…"))
                    } else if let error {
                        NovaEmptyState(title: RDLocalization.string(
                                "localizable.nova.workspace.domain.failed", table: .localizable,
                                fallback: "Kayıtlar yüklenemedi"), message: error)
                        NovaCompactActionButton(title: RDLocalization.string(
                                "localizable.nova.workspace.domain.retry", table: .localizable,
                                fallback: "Tekrar dene"), symbol: "arrow.clockwise") { revision = UUID() }
                    } else if rows.isEmpty {
                        NovaEmptyState(title: emptyTitle, message: emptyMessage)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            record(row).novaRowEntrance(index)
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
                    .novaAsyncContent(isLoading: loading)
                    .novaListEntrance(hasRecords: !rows.isEmpty)
            }
        }
        .task(id: revision) { await load() }
        .task {
            guard startInAddMode, canOperate, !didPresentInitialCreate else { return }
            didPresentInitialCreate = true
            showingCreate = true
        }
        .novaPopup(item: $selected) { row in
            IsgWorkspaceDomainDetail(store: store, domain: domain, row: row,
                                     canOperate: canOperate, workplaces: workplaces,
                                     employees: employees, companyHazardClass: companyHazardClass) {
                selected = nil
                revision = UUID()
            }
        }
        .novaFullScreenCover(isPresented: Binding(get: { showingCreate && usesFullScreenCreate },
            set: { if !$0 { showingCreate = false } }), onDismiss: { revision = UUID() }) {
            createEditor
        }
        .novaPopup(isPresented: Binding(get: { showingCreate && !usesFullScreenCreate },
            set: { if !$0 { showingCreate = false } }), onDismiss: { revision = UUID() }) { createEditor }
    }

    private var usesFullScreenCreate: Bool {
        // Consequential records are tasks, not quick decisions. Keep their
        // company/workplace context and progress in a full-screen flow.
        domain != .files && domain != .personnel
    }

    @ViewBuilder private var createEditor: some View {
        if domain == .files {
            IsgWorkspaceFileCreateEditor(store: store) { showingCreate = false }
        } else if domain == .training {
            IsgWorkspaceTrainingCreateEditor(store: store,
                companyHazardClass: companyHazardClass) { showingCreate = false }
        } else if domain == .nonconformity {
            IsgWorkspaceManualNonconformityEditor(store: store) { showingCreate = false }
        } else if domain == .risk {
            IsgWorkspaceRiskCreateEditor(store: store) { showingCreate = false }
        } else if domain == .emergencyPlan {
            IsgWorkspaceEmergencyPlanCreateFlow(store: store, companyName: companyName) {
                showingCreate = false
            }
        } else if domain == .equipment {
            IsgWorkspaceEquipmentCreateEditor(store: store) { showingCreate = false }
        } else {
            IsgWorkspaceDomainCreateEditor(store: store, domain: domain) { showingCreate = false }
        }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField(RDLocalization.string("localizable.nova.workspace.domain.search", table: .localizable,
                fallback: "Kayıtlarda ara"), text: $query)
                .font(NovaFont.font(.body)).submitLabel(.done)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle").frame(width: 36, height: 36) }
                    .buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(RDLocalization.string(
                        "localizable.nova.nonconformity.search.clear", table: .localizable,
                        fallback: "Aramayı temizle"))
            }
        }.padding(.horizontal, 12).frame(minHeight: 48).novaControlBackground(cornerRadius: 16)
    }

    private func metrics(_ values: [IsgWorkspaceDomainMetric]) -> some View {
        NovaMetricStrip(items: displayMetrics(values).map { metric in
            .init(id: metric.id,
                  value: IsgWorkspaceDisplayText.metricValue(id: metric.id, value: metric.value),
                  label: metricTitle(metric.id), symbol: metricSymbol(metric.id),
                  status: metricStatus(metric.id))
        })
    }

    private func displayMetrics(_ values: [IsgWorkspaceDomainMetric]) -> [IsgWorkspaceDomainMetric] {
        if domain == .emergencyPlan {
            return domainMetrics(values, keys: ["plans.expired", "plans.untracked", "plans.due_soon", "plans.valid"],
                                 fallback: emergencyMetrics)
        }
        if domain == .appointment {
            return domainMetrics(values, keys: ["appointments.active", "appointments.upcoming",
                                                 "appointments.ended", "appointments.total"],
                                 fallback: appointmentMetrics)
        }
        if domain == .risk {
            return domainMetrics(values, keys: ["risk.expired", "risk.untracked", "risk.valid", "risk.due_soon"],
                                 fallback: riskMetrics)
        }
        if domain == .board {
            return domainMetrics(values, keys: ["board.planned", "board.held", "board.open_decisions", "board.cancelled"],
                                 fallback: boardMetrics)
        }
        let preferred: [String]
        switch domain {
        case .training:
            preferred = ["completed_minutes", "trained_people", "person_minutes", "people_without_completed_training"]
        case .equipment:
            preferred = ["overdue", "failed", "untracked", "due_soon", "current"]
        case .nonconformity:
            preferred = ["open", "assigned", "pending_verification", "closed"]
        default:
            preferred = ["total", "active", "planned", "completed", "open", "overdue", "archived"]
        }
        let sorted = values.sorted { lhs, rhs in
            let left = preferred.firstIndex(where: { lhs.id == $0 || lhs.id.hasSuffix(".\($0)") }) ?? Int.max
            let right = preferred.firstIndex(where: { rhs.id == $0 || rhs.id.hasSuffix(".\($0)") }) ?? Int.max
            return left == right ? lhs.id < rhs.id : left < right
        }
        return Array(sorted.prefix(domain == .equipment ? 5 : 4))
    }

    private func domainMetrics(_ values: [IsgWorkspaceDomainMetric], keys: [String],
                               fallback: [IsgWorkspaceDomainMetric]) -> [IsgWorkspaceDomainMetric] {
        let fallbacks = Dictionary(uniqueKeysWithValues: fallback.map { ($0.id, $0.value) })
        return keys.map { key in
            let value = values.first(where: { $0.id == key })?.value ?? fallbacks[key] ?? 0
            return .init(id: key, value: value)
        }
    }

    private var emergencyMetrics: [IsgWorkspaceDomainMetric] {
        let today = Self.day(Date())
        let due = Self.day(Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date())
        let dates = (snapshot?.rows ?? []).map { fact("valid_until", in: $0) }
        return [
            .init(id: "plans.expired", value: Int64(dates.filter { ($0 ?? today) < today }.count)),
            .init(id: "plans.untracked", value: Int64(dates.filter { $0 == nil }.count)),
            .init(id: "plans.due_soon", value: Int64(dates.compactMap { $0 }.filter { $0 >= today && $0 <= due }.count)),
            .init(id: "plans.valid", value: Int64(dates.compactMap { $0 }.filter { $0 > due }.count))
        ]
    }

    private var appointmentMetrics: [IsgWorkspaceDomainMetric] {
        let today = Self.day(Date())
        var active = 0, upcoming = 0, ended = 0
        for row in snapshot?.rows ?? [] {
            let starts = fact("starts_on", in: row) ?? today
            let ends = fact("ends_before", in: row)
            if starts > today { upcoming += 1 }
            else if let ends, ends <= today { ended += 1 }
            else { active += 1 }
        }
        return [.init(id: "appointments.active", value: Int64(active)),
                .init(id: "appointments.upcoming", value: Int64(upcoming)),
                .init(id: "appointments.ended", value: Int64(ended)),
                .init(id: "appointments.total", value: Int64(snapshot?.rows.count ?? 0))]
    }

    private var riskMetrics: [IsgWorkspaceDomainMetric] {
        let today = Self.day(Date())
        let due = Self.day(Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date())
        let source = snapshot?.rows ?? []
        let expired = source.filter { (fact("valid_until", in: $0) ?? today) < today }.count
        let untracked = source.filter { (Int(fact("current_version", in: $0) ?? "0") ?? 0) == 0 }.count
        let dueSoon = source.filter { row in
            guard let date = fact("valid_until", in: row) else { return false }
            return date >= today && date <= due
        }.count
        return [.init(id: "risk.expired", value: Int64(expired)),
                .init(id: "risk.untracked", value: Int64(untracked)),
                .init(id: "risk.valid", value: Int64(max(0, source.count - expired - untracked - dueSoon))),
                .init(id: "risk.due_soon", value: Int64(dueSoon))]
    }

    private var boardMetrics: [IsgWorkspaceDomainMetric] {
        let source = snapshot?.rows ?? []
        return [.init(id: "board.planned", value: Int64(source.filter { $0.status == "planned" }.count)),
                .init(id: "board.held", value: Int64(source.filter { $0.status == "held" }.count)),
                .init(id: "board.open_decisions", value: Int64(source.reduce(0) {
                    $0 + (Int(fact("open_decision_count", in: $1) ?? "0") ?? 0)
                })),
                .init(id: "board.cancelled", value: Int64(source.filter { $0.status == "cancelled" }.count))]
    }

    private func record(_ row: IsgWorkspaceDomainRecord) -> some View {
        Button { open(row) } label: {
            NovaCard(padding: 14) {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: domain.symbol, size: 19)
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: recordTitle(row), style: .bodyStrong)
                        if let subtitle = recordSubtitle(row) { NovaText(text: subtitle, style: .metaQuiet) }
                        if let status = recordStatus(row) {
                            NovaStatusPill(label: statusLabel(status), status: statusTone(status))
                        }
                        let highlights = recordHighlights(row)
                        if !highlights.isEmpty {
                            NovaText(text: highlights.joined(separator: " · "), style: .metaQuiet)
                        }
                    }
                    Spacer(minLength: 0)
                    if detailLoadingID == row.id { ProgressView().controlSize(.small) }
                    else { Image(systemName: "chevron.right") }
                }.contentShape(Rectangle())
            }
        }.buttonStyle(NovaRowPressStyle()).disabled(detailLoadingID != nil)
    }

    private func open(_ row: IsgWorkspaceDomainRecord) {
        guard detailLoadingID == nil else { return }
        detailLoadingID = row.id
        Task { @MainActor in
            do { selected = try await store.domainDetail(domain, id: row.id) }
            catch {
                selected = row
                self.error = "Kayıt geçmişinin tamamı yüklenemedi. Özet bilgiler gösteriliyor."
            }
            detailLoadingID = nil
        }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        do {
            snapshot = try await store.domain(domain)
            if [.emergencyPlan, .appointment, .risk, .board].contains(domain) {
                let places = (try? await store.directory(.workplace)) ?? []
                workplaces = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0.name) })
            }
            if [.emergencyPlan, .appointment, .board].contains(domain) {
                let people = (try? await store.employees()) ?? []
                employees = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.name) })
            }
        }
        catch {
            snapshot = nil
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                               fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }

    private func metricTitle(_ key: String) -> String {
        IsgWorkspaceDisplayText.metric(key)
    }

    private func metricSymbol(_ key: String) -> String {
        if key.contains("overdue") || key.contains("expired") { return "exclamationmark.triangle" }
        if key.contains("completed") || key.contains("valid") { return "checkmark.circle" }
        if key.contains("people") || key.contains("employee") { return "person.2" }
        if key.contains("minute") { return "clock" }
        if key.contains("untracked") { return "questionmark.circle" }
        if key.contains("upcoming") || key.contains("due_soon") { return "clock" }
        if key.contains("held") { return "person.3" }
        if key.contains("decision") { return "checklist" }
        return domain.symbol
    }

    private func metricStatus(_ key: String) -> NovaStatus {
        if key.contains("overdue") || key.contains("expired") || key.contains("failed") { return .danger }
        if key.contains("untracked") || key.contains("due_soon") || key.contains("upcoming") || key.contains("open") { return .warning }
        if key.contains("valid") || key.contains("completed") || key.contains("active") || key.contains("held") { return .success }
        return .neutral
    }

    private func actionPriority(_ row: IsgWorkspaceDomainRecord) -> Int {
        let status = recordStatus(row) ?? ""
        switch status {
        case "overdue", "expired", "failed", "critical": return 0
        case "open", "in_progress", "pending_verification", "untracked", "never_inspected", "period_unknown": return 1
        case "due_soon", "upcoming", "draft", "planned": return 2
        case "valid", "active", "completed", "closed", "held", "performed": return 4
        default: return 3
        }
    }

    private func recordTitle(_ row: IsgWorkspaceDomainRecord) -> String {
        if domain == .appointment, let id = uuidFact("employee_id", in: row), let name = employees[id] { return name }
        if domain == .risk, let id = uuidFact("workplace_id", in: row), let name = workplaces[id] { return name }
        if domain == .board, let date = fact("held_on", in: row) ?? fact("planned_on", in: row) {
            return "Kurul toplantısı · \(date)"
        }
        return row.title
    }

    private func recordSubtitle(_ row: IsgWorkspaceDomainRecord) -> String? {
        var values: [String] = []
        if domain == .appointment { values.append(IsgWorkspaceDisplayText.value(row.title)) }
        if let id = uuidFact("workplace_id", in: row), let place = workplaces[id] { values.append(place) }
        if domain == .board, let agenda = fact("agenda_summary", in: row) { values.append(agenda) }
        if values.isEmpty, let subtitle = row.subtitle { values.append(subtitle) }
        return values.isEmpty ? nil : values.joined(separator: " · ")
    }

    private func recordStatus(_ row: IsgWorkspaceDomainRecord) -> String? {
        let today = Self.day(Date())
        if domain == .appointment {
            if let starts = fact("starts_on", in: row), starts > today { return "upcoming" }
            if let ends = fact("ends_before", in: row), ends <= today { return "ended" }
            return "active"
        }
        if domain == .emergencyPlan {
            guard let valid = fact("valid_until", in: row) else { return "untracked" }
            let due = Self.day(Calendar.current.date(byAdding: .day, value: 60, to: Date()) ?? Date())
            if valid < today { return "expired" }
            if valid <= due { return "due_soon" }
            return "valid"
        }
        return row.status
    }

    private func recordHighlights(_ row: IsgWorkspaceDomainRecord) -> [String] {
        switch domain {
        case .emergencyPlan:
            return [fact("prepared_on", in: row).map { "Hazırlanma: \($0)" },
                    fact("valid_until", in: row).map { "Geçerlilik: \($0)" },
                    fact("team_size", in: row).map { "\($0) kişilik ekip" }].compactMap { $0 }
        case .appointment:
            return [fact("starts_on", in: row).map { "Başlangıç: \($0)" },
                    fact("ends_before", in: row).map { "Bitiş: \($0)" }].compactMap { $0 }
        case .risk:
            return [fact("base_assessment_on", in: row).map { "Değerlendirme: \($0)" },
                    fact("valid_until", in: row).map { "Geçerlilik: \($0)" },
                    fact("current_version", in: row).map { "Sürüm: \($0)" }].compactMap { $0 }
        case .training:
            return [fact("duration_minutes", in: row).map { "\($0) dk" },
                    fact("participant_count", in: row).map { "\($0) katılımcı" },
                    fact("method", in: row).map(IsgWorkspaceDisplayText.value)].compactMap { $0 }
        case .equipment:
            return [fact("serial_tag", in: row).map { "Kod: \($0)" },
                    fact("last_performed_on", in: row).map { "Son kontrol: \($0)" },
                    fact("next_due_on", in: row).map { "Sonraki: \($0)" }].compactMap { $0 }
        case .board:
            return [fact("attendance_count", in: row).map { "\($0) katılımcı" },
                    fact("decision_count", in: row).map { "\($0) karar" },
                    fact("open_decision_count", in: row).map { "\($0) açık" }].compactMap { $0 }
        default: return []
        }
    }

    private func fact(_ key: String, in row: IsgWorkspaceDomainRecord) -> String? {
        row.facts.first(where: { $0.0 == key })?.1
    }

    private func uuidFact(_ key: String, in row: IsgWorkspaceDomainRecord) -> UUID? {
        fact(key, in: row).flatMap(UUID.init(uuidString:))
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private func statusLabel(_ value: String) -> String {
        IsgWorkspaceDisplayText.value(value)
    }

    private func statusTone(_ value: String) -> NovaStatus {
        switch value {
        case "closed", "completed", "performed", "valid", "active", "held": return .success
        case "overdue", "expired", "failed", "critical": return .danger
        case "due_soon", "planned", "draft", "open", "upcoming", "untracked",
             "never_inspected", "period_unknown": return .warning
        default: return .neutral
        }
    }
}

private struct IsgWorkspaceDomainDetail: View {
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let row: IsgWorkspaceDomainRecord
    let canOperate: Bool
    let workplaces: [UUID: String]
    let employees: [UUID: String]
    let companyHazardClass: String
    let onChanged: () -> Void
    @State private var busy = false
    @State private var error: String?
    @State private var preview: IsgWorkspaceDownloadedFile?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @State private var selectedAction: IsgWorkspaceDomainAction?
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: domain.symbol, size: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: detailTitle, style: .sectionTitle)
                        if let subtitle = row.subtitle { NovaText(text: subtitle, style: .metaQuiet) }
                    }
                }
                if let status = row.status { NovaStatusPill(label: IsgWorkspaceDisplayText.value(status), status: .neutral) }
                NovaCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(row.facts.enumerated()), id: \.offset) { _, fact in
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: IsgWorkspaceDisplayText.field(fact.0),
                                         style: .metaQuiet)
                                NovaText(text: factValue(fact), style: .bodyStrong)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if domain == .risk { riskHistory }
                if domain == .equipment { equipmentHistory }
                if domain == .training, !row.trainingParticipants.isEmpty {
                    NovaCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            NovaText(text: "Katılımcılar", style: .bodyStrong)
                            ForEach(row.trainingParticipants) { participant in
                                HStack(spacing: 10) {
                                    Image(systemName: participant.attended ? "checkmark.circle.fill" : "circle")
                                    NovaText(text: participant.name, style: .body)
                                    Spacer(minLength: 0)
                                    NovaText(text: participant.attended ? "Katıldı" :
                                             row.status == "planned" ? "Tamamlanmayı bekliyor" : "Katılmadı",
                                             style: .metaQuiet)
                                }
                            }
                        }
                    }
                }
                if domain == .checklist, !row.checklistItems.isEmpty {
                    NovaCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            NovaText(text: label("localizable.nova.workspace.checklist.items", "Kontrol maddeleri"),
                                     style: .bodyStrong)
                            ForEach(row.checklistItems) { item in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: item.result == nil ? "circle" :
                                            item.result == "conform" ? "checkmark.circle" :
                                            item.result == "nonconform" ? "exclamationmark.triangle" : "minus.circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        NovaText(text: item.prompt, style: .body)
                                        NovaText(text: checklistResult(item.result), style: .metaQuiet)
                                        if let note = item.note, !note.isEmpty { NovaText(text: note, style: .metaQuiet) }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                if domain == .board, !row.boardDecisions.isEmpty {
                    NovaCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            NovaText(text: "Kararlar ve takip", style: .bodyStrong)
                            ForEach(row.boardDecisions.sorted { $0.number < $1.number }) { decision in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .top, spacing: 8) {
                                        NovaText(text: "\(decision.number). \(decision.text)", style: .bodyStrong)
                                        Spacer(minLength: 0)
                                        NovaStatusPill(label: IsgWorkspaceDisplayText.value(decision.state),
                                                       status: decision.state == "done" ? .success :
                                                               decision.state == "cancelled" ? .neutral : .warning)
                                    }
                                    if let responsible = decision.responsibleContact, !responsible.isEmpty {
                                        NovaText(text: "Sorumlu: \(responsible)", style: .metaQuiet)
                                    }
                                    if let due = decision.dueOn { NovaText(text: "Termin: \(due)", style: .metaQuiet) }
                                    if canOperate && decision.state == "open" {
                                        HStack(spacing: 8) {
                                            NovaButton(label: "Tamamla", symbol: "checkmark", compact: true) {
                                                settle(decision, as: "done")
                                            }
                                            NovaButton(label: "İptal", symbol: "xmark", compact: true) {
                                                settle(decision, as: "cancelled")
                                            }
                                        }
                                    }
                                }
                                if decision.id != row.boardDecisions.last?.id { Divider() }
                            }
                        }
                    }
                }
                if domain == .files {
                    NovaCompactActionButton(title: busy ? RDLocalization.string(
                        "localizable.nova.workspace.file.downloading", table: .localizable,
                        fallback: "Dosya hazırlanıyor…") : RDLocalization.string(
                            "localizable.nova.workspace.file.open", table: .localizable,
                            fallback: "Dosyayı aç"), symbol: "arrow.down.doc", prominent: true,
                        enabled: !busy && row.assetID != nil) { openFile() }
                    if canOperate {
                        NovaCompactActionButton(title: RDLocalization.string(
                            "localizable.nova.workspace.file.archive", table: .localizable,
                            fallback: "Arşivle"), symbol: "archivebox", enabled: !busy) { archive() }
                    }
                }
                if canOperate && !availableActions.isEmpty {
                    NovaCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: label("localizable.nova.workspace.domain.actions", "Kayıt işlemleri"),
                                     style: .bodyStrong)
                            ForEach(availableActions) { action in
                                NovaCompactActionButton(title: action.title, symbol: action.symbol,
                                                        prominent: action.isPrimary, enabled: !busy) {
                                    selectedAction = action
                                }
                            }
                        }
                    }
                }
                if let error { NovaHelpHint(text: error) }
            }.padding(18).novaPopupContentSize()
        }
        .fullScreenCover(item: $preview) { DocumentPreview(url: $0.url) }
        .novaPopup(item: $selectedAction) { action in
            IsgWorkspaceDomainActionEditor(store: store, domain: domain, row: row, action: action,
                                           workplaces: workplaces,
                                           companyHazardClass: companyHazardClass) {
                selectedAction = nil
                onChanged()
            }
        }
    }

    private var availableActions: [IsgWorkspaceDomainAction] {
        let state = row.status ?? ""
        switch domain {
        case .training where state == "planned": return [.trainingComplete, .trainingCancel]
        case .risk where state == "draft": return [.riskEditDraft, .riskFinalize, .riskCancelDraft]
        case .nonconformity:
            var values: [IsgWorkspaceDomainAction] = []
            switch state {
            case "draft": values = [.nonconformityTransition("open"), .nonconformityTransition("cancelled")]
            case "open": values = [.nonconformityTransition("assigned"), .nonconformityTransition("cancelled")]
            case "assigned": values = [.nonconformityTransition("in_progress"), .nonconformityTransition("open"), .nonconformityTransition("cancelled")]
            case "in_progress": values = [.nonconformityTransition("pending_verification"), .nonconformityTransition("assigned"), .nonconformityTransition("cancelled")]
            case "pending_verification":
                if row.facts.first(where: { $0.0 == "verification_outcome" })?.1 == "accepted" {
                    values = [.nonconformityTransition("closed"), .nonconformityTransition("in_progress")]
                } else if row.facts.first(where: { $0.0 == "verification_outcome" })?.1 == "rejected" {
                    values = [.nonconformityTransition("in_progress")]
                } else {
                    values = [.nonconformityVerify, .nonconformityTransition("in_progress")]
                }
            case "closed": values = [.nonconformityTransition("reopened")]
            case "reopened": values = [.nonconformityTransition("assigned"), .nonconformityTransition("in_progress"), .nonconformityTransition("cancelled")]
            default: break
            }
            if !["closed", "cancelled"].contains(state) { values.append(.nonconformityAddAction) }
            return values
        case .checklist where state == "open":
            var actions: [IsgWorkspaceDomainAction] = row.checklistItems.isEmpty ? [] : [.checklistAnswer]
            if !row.checklistItems.isEmpty && row.checklistItems.allSatisfy({ $0.result != nil }) {
                actions.append(.checklistSubmit)
            }
            actions.append(.checklistCancel)
            return actions
        case .drill where state == "planned": return [.drillPerform, .drillCancel]
        case .appointment: return appointmentEnded ? [] : [.appointmentEnd]
        case .ppe: return remainingPPE > 0 ? [.ppeReturn] : []
        case .equipment where state != "archived":
            return [.equipmentInspect, .equipmentEdit, .equipmentRule, .equipmentArchive]
        case .katip where state != "archived": return [.katipArchive]
        case .annualPlan where state == "active": return [.annualAddItem, .annualClose]
        case .board where state == "planned": return [.boardHold, .boardCancel]
        case .board where state == "held": return [.boardAddDecision]
        case .workPermit where state != "archived": return [.permitArchive]
        case .visit: return [.visitAddObservation]
        default: return []
        }
    }

    private func label(_ key: String, _ fallback: String) -> String {
        RDLocalization.string(key, table: .localizable, fallback: fallback)
    }

    private var riskHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: "Sürüm geçmişi", style: .cardTitle)
            if row.riskVersions.isEmpty {
                NovaEmptyState(title: "Henüz sürüm yok",
                               message: "İlk değerlendirme taslağı eklendiğinde sürüm geçmişi burada oluşur.")
            } else {
                ForEach(row.riskVersions.sorted { $0.number > $1.number }) { version in
                    NovaCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                NovaText(text: "v\(version.number) · \(IsgWorkspaceDisplayText.value(version.kind))",
                                         style: .bodyStrong)
                                Spacer(minLength: 0)
                                NovaStatusPill(label: IsgWorkspaceDisplayText.value(version.state),
                                    status: version.state == "final" ? .success :
                                            version.state == "draft" ? .warning : .neutral)
                            }
                            HStack(spacing: 10) {
                                NovaText(text: "Değerlendirme: \(version.assessmentOn)", style: .metaQuiet)
                                if let revisionOn = version.revisionOn {
                                    NovaText(text: "Revizyon: \(revisionOn)", style: .metaQuiet)
                                }
                            }
                            if let until = version.validUntil {
                                NovaText(text: "Geçerlilik: \(until)", style: .metaQuiet)
                            }
                            if let period = version.periodYears {
                                NovaText(text: "Süre: \(period) yıl" +
                                    (version.periodSource.map { " · \(IsgWorkspaceDisplayText.value($0))" } ?? ""),
                                    style: .metaQuiet)
                            }
                            if let scope = version.scopeSummary, !scope.isEmpty {
                                NovaText(text: "Kapsam: \(scope)", style: .meta)
                            }
                            if let reason = version.reason, !reason.isEmpty {
                                NovaText(text: "Gerekçe: \(reason)", style: .meta)
                            }
                            if let cancellation = version.cancellationNote, !cancellation.isEmpty {
                                NovaText(text: "İptal gerekçesi: \(cancellation)", style: .meta)
                            }
                            if version.periodNeedsReview {
                                NovaHelpHint(text: "Süre uzman tarafından belirlenmiştir; kaynak ve geçerlilik bilgisi gözden geçirilmelidir.")
                            }
                            if version.sourceDrift {
                                NovaHelpHint(text: "Kaynak analiz bu sürümden sonra değişmiştir; kayıt otomatik değiştirilmedi.")
                            }
                        }
                    }
                }
            }
        }
    }

    private var equipmentHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: "Kontrol ve rapor geçmişi", style: .cardTitle)
            if row.equipmentInspections.isEmpty {
                NovaEmptyState(title: "Henüz kontrol kaydı yok",
                               message: "İlk periyodik kontrolü eklediğinizde tarih, sonuç ve rapor bilgileri burada görünür.")
            } else {
                ForEach(row.equipmentInspections) { inspection in
                    NovaCard(padding: 12) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                NovaText(text: inspection.performedOn, style: .bodyStrong)
                                Spacer(minLength: 0)
                                NovaStatusPill(label: IsgWorkspaceDisplayText.value(inspection.result),
                                    status: inspection.result == "pass" ? .success :
                                            inspection.result == "fail" ? .danger : .warning)
                            }
                            if let next = inspection.nextDueOn {
                                NovaText(text: "Sonraki kontrol: \(next)", style: .metaQuiet)
                            }
                            if let inspector = inspection.inspector, !inspector.isEmpty {
                                NovaText(text: "Kontrolü yapan: \(inspector)", style: .meta)
                            }
                            if let reference = inspection.externalRef, !reference.isEmpty {
                                NovaText(text: "Rapor no: \(reference)", style: .meta)
                            }
                            if let note = inspection.note, !note.isEmpty { NovaText(text: note, style: .meta) }
                            HStack(spacing: 8) {
                                if inspection.assetID != nil {
                                    NovaStatusPill(label: "Rapor arşivde", status: .success)
                                }
                                if inspection.katipDeclared {
                                    NovaStatusPill(label: "İSG-KATİP beyanı", status: .neutral)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var detailTitle: String {
        if domain == .appointment, let raw = fact("employee_id"), let id = UUID(uuidString: raw),
           let name = employees[id] { return name }
        if domain == .risk, let raw = fact("workplace_id"), let id = UUID(uuidString: raw),
           let name = workplaces[id] { return name }
        if domain == .board, let date = fact("held_on") ?? fact("planned_on") {
            return "Kurul toplantısı · \(date)"
        }
        return row.title
    }

    private func factValue(_ value: (String, String)) -> String {
        if value.0 == "employee_id", let id = UUID(uuidString: value.1), let name = employees[id] { return name }
        if value.0 == "workplace_id", let id = UUID(uuidString: value.1), let name = workplaces[id] { return name }
        return IsgWorkspaceDisplayText.value(value.1)
    }

    private func fact(_ key: String) -> String? {
        row.facts.first(where: { $0.0 == key })?.1
    }

    private var remainingPPE: Int {
        let quantity = Int(row.facts.first(where: { $0.0 == "quantity" })?.1 ?? "0") ?? 0
        let returned = Int(row.facts.first(where: { $0.0 == "returned_quantity" })?.1 ?? "0") ?? 0
        return max(0, quantity - returned)
    }

    private var appointmentEnded: Bool {
        guard let end = row.facts.first(where: { $0.0 == "ends_before" })?.1 else { return false }
        return end <= Date().formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }

    private func checklistResult(_ result: String?) -> String {
        switch result {
        case "conform": return label("localizable.nova.workspace.checklist.result.conform", "Uygun")
        case "nonconform": return label("localizable.nova.workspace.checklist.result.nonconform", "Uygunsuz")
        case "not_applicable": return label("localizable.nova.workspace.checklist.result.na", "Uygulanamaz")
        default: return label("localizable.nova.workspace.checklist.result.pending", "Yanıt bekliyor")
        }
    }

    private func openFile() {
        guard !busy else { return }
        busy = true; error = nil
        Task { @MainActor in
            do {
                let download = try await store.downloadFile(row)
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("workspace-files-" + UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: download.filename).lastPathComponent
                let url = folder.appendingPathComponent(safeName.isEmpty ? "belge" : safeName)
                try download.data.write(to: url, options: .atomic)
                preview = .init(url: url)
            } catch {
                self.error = RDLocalization.string(
                    "localizable.nova.workspace.file.download.failed", table: .localizable,
                    fallback: "Dosya açılamadı. Yetkinizi ve bağlantınızı kontrol edip yeniden deneyin.")
            }
            busy = false
        }
    }

    private func archive() {
        guard !busy else { return }
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "files.archive", components: [
            row.id.uuidString, String(row.version ?? 0)
        ])
        mutationAttempt = attempt
        busy = true; error = nil
        Task { @MainActor in
            do {
                try await store.archiveFile(row, mutationID: mutationID)
                onChanged()
            } catch {
                self.error = RDLocalization.string(
                    "localizable.nova.workspace.file.archive.failed", table: .localizable,
                    fallback: "Dosya arşivlenemedi. Sayfayı yenileyip yeniden deneyin.")
            }
            busy = false
        }
    }

    private func settle(_ decision: IsgWorkspaceBoardDecision, as state: String) {
        guard !busy else { return }
        let command: [String: IsgWorkspaceRPCValue] = [
            "kind": .string("board_decision"), "action": .string("settle"),
            "id": .id(decision.id), "expected_version": .number(Int(decision.version)),
            "state": .string(state)
        ]
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "board.decision.settle", payload: command)
        mutationAttempt = attempt
        busy = true; error = nil
        Task { @MainActor in
            do {
                _ = try await store.mutateDomain(mutationID: mutationID, domain: .board, payload: command)
                celebrate(NovaSuccessMessage.recordSaved("Kurul kararı"))
                onChanged()
            } catch {
                self.error = "Karar durumu güncellenemedi. Kaydı yenileyip yeniden deneyin."
            }
            busy = false
        }
    }
}

private enum IsgWorkspaceDomainAction: Identifiable, Equatable {
    case trainingComplete, trainingCancel, riskEditDraft, riskFinalize, riskCancelDraft
    case nonconformityTransition(String), nonconformityAddAction, nonconformityVerify
    case checklistAnswer, checklistSubmit, checklistCancel, drillPerform, drillCancel, appointmentEnd, ppeReturn
    case equipmentInspect, equipmentEdit, equipmentRule, equipmentArchive, katipArchive, annualAddItem, annualClose
    case boardHold, boardAddDecision, boardCancel, permitArchive, visitAddObservation

    var id: String {
        switch self {
        case .nonconformityTransition(let state): return "finding.transition.\(state)"
        default: return String(describing: self)
        }
    }
    var title: String {
        switch self {
        case .trainingComplete: return "Eğitimi tamamla"
        case .trainingCancel: return "Eğitimi iptal et"
        case .riskEditDraft: return "Taslağı düzenle"
        case .riskFinalize: return "Risk analizini kesinleştir"
        case .riskCancelDraft: return "Taslağı iptal et"
        case .nonconformityTransition(let state):
            return ["open": "Kaydı aç", "assigned": "Sorumlu ata", "in_progress": "İşleme al",
                    "pending_verification": "Doğrulamaya gönder", "closed": "Kaydı kapat",
                    "reopened": "Yeniden aç", "cancelled": "Kaydı iptal et"][state] ?? "Durumu güncelle"
        case .nonconformityAddAction: return "Düzeltici faaliyet ekle"
        case .nonconformityVerify: return "Doğrulama kaydet"
        case .checklistAnswer: return "Kontrol maddesini yanıtla"
        case .checklistSubmit: return "Kontrol listesini gönder"
        case .checklistCancel: return "Kontrol listesini iptal et"
        case .drillPerform: return "Tatbikatı tamamla"
        case .drillCancel: return "Tatbikatı iptal et"
        case .appointmentEnd: return "Atamayı sonlandır"
        case .ppeReturn: return "KKD iadesi kaydet"
        case .equipmentInspect: return "Periyodik kontrol ekle"
        case .equipmentEdit: return "Ekipmanı düzenle"
        case .equipmentRule: return "Kontrol süresini düzenle"
        case .equipmentArchive: return "Ekipmanı arşivle"
        case .katipArchive: return "Sözleşmeyi arşivle"
        case .annualAddItem: return "Plan faaliyeti ekle"
        case .annualClose: return "Yıllık planı kapat"
        case .boardHold: return "Toplantıyı gerçekleştir"
        case .boardAddDecision: return "Karar ekle"
        case .boardCancel: return "Toplantıyı iptal et"
        case .permitArchive: return "İzin formunu arşivle"
        case .visitAddObservation: return "Ziyaret gözlemi ekle"
        }
    }
    var symbol: String {
        switch self {
        case .trainingComplete, .checklistSubmit, .drillPerform, .boardHold: return "checkmark.circle"
        case .checklistAnswer: return "checklist"
        case .riskFinalize, .nonconformityVerify: return "checkmark.seal"
        case .riskEditDraft: return "pencil"
        case .riskCancelDraft: return "xmark.circle"
        case .nonconformityAddAction, .annualAddItem, .boardAddDecision, .visitAddObservation: return "plus"
        case .appointmentEnd: return "calendar.badge.minus"
        case .ppeReturn: return "arrow.uturn.backward"
        case .equipmentInspect: return "calendar.badge.checkmark"
        case .equipmentEdit: return "pencil"
        case .equipmentRule: return "hourglass"
        case .nonconformityTransition: return "arrow.triangle.2.circlepath"
        case .trainingCancel, .checklistCancel, .drillCancel, .equipmentArchive, .katipArchive,
             .annualClose, .boardCancel, .permitArchive: return "archivebox"
        }
    }
    var isPrimary: Bool {
        switch self {
        case .trainingComplete, .riskFinalize, .checklistSubmit, .drillPerform, .equipmentInspect,
             .boardHold, .nonconformityVerify: return true
        default: return false
        }
    }
    var acceptsAttachment: Bool {
        switch self {
        case .trainingComplete, .riskFinalize, .nonconformityAddAction, .nonconformityVerify,
             .checklistAnswer, .drillPerform, .ppeReturn, .equipmentInspect,
             .annualAddItem, .boardHold, .boardAddDecision, .visitAddObservation:
            return true
        default:
            return false
        }
    }
}

private struct IsgWorkspaceDomainActionEditor: View {
    private enum EquipmentStep: String { case control, details, report }
    @ObservedObject var store: IsgWorkspaceStore
    let domain: IsgWorkspaceDomain
    let row: IsgWorkspaceDomainRecord
    let action: IsgWorkspaceDomainAction
    let workplaces: [UUID: String]
    let companyHazardClass: String
    let onDone: () -> Void
    @State private var note = ""
    @State private var contact = ""
    @State private var option = "accepted"
    @State private var checklistItemCode = ""
    @State private var checklistSeverity = "medium"
    @State private var createChecklistNonconformity = false
    @State private var number = 1
    @State private var date = Date()
    @State private var secondDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var selectedEmployees = Set<UUID>()
    @State private var equipmentOpen: EquipmentStep? = .control
    @State private var hasNextDue = true
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var attachmentOpen = false
    @State private var externalRef = ""
    @State private var katipDeclared = false
    @State private var katipNote = ""
    @State private var workplaceID: UUID?
    @State private var serialTag = ""
    @State private var locationNote = ""
    @State private var loading = false
    @State private var saving = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: action.title, style: .sectionTitle)
                NovaHelpHint(text: "İşlem \(row.title) kaydına uygulanır ve değişiklik geçmişine yazılır.")
                fields
                if let error { NovaHelpHint(text: error) }
                NovaCompactActionButton(title: saving ? "Kaydediliyor…" : action.title,
                                        symbol: action.symbol, prominent: true,
                                        enabled: canSubmit && !saving && !loading) { save() }
            }.padding(18).novaPopupContentSize()
        }
        .task { await prepare() }
        .onChange(of: date) { _ in recalculateEquipmentDueDate() }
        .onChange(of: option) { _ in recalculateEquipmentDueDate() }
    }

    @ViewBuilder private var fields: some View {
        switch action {
        case .trainingComplete:
            NovaHelpHint(text: "Eğitime katılan personeli seçin. Sınavlı müfredatta seçilen herkesin başarılı sınav kaydı bulunmalıdır.")
            employeePicker
        case .riskEditDraft:
            if let draft = riskDraft {
                NovaFormValueRow(label: "Sürüm türü", symbol: "square.stack.3d.up") {
                    NovaText(text: IsgWorkspaceDisplayText.value(draft.kind), style: .bodyStrong)
                }
                compactDate(draft.kind == "full" ? "Değerlendirme tarihi" : "Revizyon tarihi",
                            selection: $date, limitToToday: true)
                if draft.kind == "partial" { textField("Kapsam özeti", text: $contact) }
                if ["partial", "metadata"].contains(draft.kind) {
                    textField("Değişiklik gerekçesi · en az 10 karakter", text: $note)
                }
                NovaHelpHint(text: "Sürüm türü taslak açıldıktan sonra değiştirilemez. Tamamlanmış sürümler düzenlenmez.")
            }
        case .riskFinalize:
            if fact("draft_kind") == "full" {
                Stepper("Geçerlilik süresi: \(number) yıl", value: $number, in: 1...20)
                    .padding(12).novaControlBackground(cornerRadius: 14)
                NovaHelpHint(text: "\(IsgWorkspaceDisplayText.value(companyHazardClass)) tehlike sınıfı için önerilen süre \(suggestedRiskPeriod) yıldır; gerektiğinde değiştirebilirsiniz.")
            } else {
                NovaHelpHint(text: "Kısmi revizyon ve bilgi düzeltmesi ilk değerlendirmenin geçerlilik tarihini değiştirmez.")
            }
        case .riskCancelDraft:
            textField("İptal gerekçesi · en az 5 karakter", text: $note)
            NovaHelpHint(text: "Taslak iptal edilir; yürürlükteki risk değerlendirmesi değişmez.")
        case .nonconformityTransition(let state):
            if ["assigned"].contains(state) { textField("Sorumlu / iletişim", text: $contact) }
            if ["cancelled", "open", "in_progress", "reopened"].contains(state) {
                textField("İşlem gerekçesi", text: $note)
            }
        case .nonconformityAddAction:
            textField("Düzeltici faaliyet", text: $note)
            textField("Sorumlu / iletişim", text: $contact)
            DatePicker("Termin", selection: $secondDate, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
        case .nonconformityVerify:
            picker("Sonuç", values: ["accepted", "rejected"])
            DatePicker("Doğrulama tarihi", selection: $date, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
            textField("Doğrulama notu", text: $note)
        case .checklistAnswer:
            Picker("Kontrol maddesi", selection: $checklistItemCode) {
                ForEach(row.checklistItems) { item in Text(item.prompt).tag(item.code) }
            }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                .onChange(of: checklistItemCode) { code in
                    let item = row.checklistItems.first { $0.code == code }
                    let current = item?.result ?? "conform"
                    option = (item?.allowsNotApplicable == false && current == "not_applicable") ? "conform" : current
                    note = item?.note ?? ""
                    createChecklistNonconformity = false
                }
            picker("Sonuç", values: checklistResultOptions)
            if option == "nonconform" {
                if selectedChecklistItem?.nonconformityID != nil {
                    NovaHelpHint(text: "Bu maddeye bağlı uygunsuzluk kaydı daha önce oluşturuldu.")
                } else {
                    Toggle("Bu madde için uygunsuzluk kaydı aç", isOn: $createChecklistNonconformity)
                        .padding(12).novaControlBackground(cornerRadius: 14)
                }
                if createChecklistNonconformity && selectedChecklistItem?.nonconformityID == nil {
                    Picker("Önem", selection: $checklistSeverity) {
                        ForEach(["low", "medium", "high", "critical"], id: \.self) { value in
                            Text(IsgWorkspaceDisplayText.value(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                    DatePicker("Düzeltme termini", selection: $secondDate,
                               in: checklistMinimumDate..., displayedComponents: .date)
                        .padding(12).novaControlBackground(cornerRadius: 14)
                }
            }
            textField("Madde notu", text: $note)
        case .drillPerform, .boardHold:
            DatePicker(action == .drillPerform ? "Gerçekleşme tarihi" : "Toplantı tarihi",
                       selection: $date, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
            employeePicker
            if action == .drillPerform {
                textField("Gözlem", text: $note)
                textField("İyileştirme", text: $contact)
            }
        case .drillCancel, .boardCancel:
            textField("İptal gerekçesi", text: $note)
        case .appointmentEnd:
            DatePicker("Bitiş tarihi", selection: $secondDate,
                       in: appointmentMinimumDate..., displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
        case .ppeReturn:
            Stepper("İade adedi: \(number)", value: $number, in: 1...max(1, remainingPPE))
                .padding(12).novaControlBackground(cornerRadius: 14)
            DatePicker("İade tarihi", selection: $date, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
            picker("Durum", values: ["reusable", "worn", "damaged", "lost"])
            textField("Not", text: $note)
        case .equipmentEdit:
            Picker("İşyeri", selection: $workplaceID) {
                Text("İşyeri seçin").tag(Optional<UUID>.none)
                ForEach(workplaces.keys.sorted { (workplaces[$0] ?? "") < (workplaces[$1] ?? "") }, id: \.self) { id in
                    Text(workplaces[id] ?? id.uuidString).tag(Optional(id))
                }
            }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
            textField("Seri / kod", text: $serialTag)
            textField("Konum (isteğe bağlı)", text: $locationNote)
            compactDate("Edinme tarihi", selection: $date, limitToToday: true)
        case .equipmentRule:
            NovaFormValueRow(label: "Ekipman türü", symbol: "shippingbox") {
                NovaText(text: row.title, style: .bodyStrong)
            }
            Stepper("Kontrol süresi: \(number) ay", value: $number, in: 1...240)
                .padding(12).novaControlBackground(cornerRadius: 14)
            Picker("Süre kaynağı", selection: $option) {
                Text("Üretici kılavuzu").tag("manufacturer")
                Text("Yayımlanmış kural / standart").tag("rule_version")
                Text("Uzman tarafından belirlenen").tag("unapproved_fixture")
            }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
            if option == "unapproved_fixture" {
                textField("İstisna ve dayanak notu · en az 10 karakter", text: $note)
            }
            NovaHelpHint(text: "Bu süre aynı firmadaki aynı ekipman türünün sonraki kontrollerinde kullanılır; geçmiş raporların tarihleri değişmez.")
        case .equipmentInspect:
            equipmentAccordion(.control, title: "Kontrol ve sonuç", symbol: "calendar.badge.checkmark") {
                HStack(alignment: .top, spacing: 8) {
                    compactDate("Kontrol tarihi", selection: $date, limitToToday: true)
                    compactDate("Sonraki kontrol", selection: $secondDate,
                                enabled: hasNextDue && option != "fail")
                }
                picker("Sonuç", values: ["pass", "conditional", "fail"])
                NovaHelpHint(text: option == "fail"
                    ? "Olumsuz kontrolde sonraki tarih oluşturulmaz. Düzeltme sonrası yeni kontrol kaydı girin."
                    : "Sonraki tarih \(periodMonths) aylık süreden hesaplandı; uzman gerekirse değiştirebilir.")
            }
            equipmentAccordion(.details, title: "Kontrol bilgileri", symbol: "person.text.rectangle") {
                textField("Kontrolü yapan", text: $contact)
                textField("Rapor no / harici referans", text: $externalRef)
                Toggle("İSG-KATİP ataması yapıldı", isOn: $katipDeclared)
                    .padding(12).novaControlBackground(cornerRadius: 14)
                if katipDeclared { textField("İSG-KATİP beyan notu", text: $katipNote) }
                textField("Kontrol notu", text: $note)
            }
            equipmentAccordion(.report, title: "Kontrol raporu", symbol: "doc.badge.plus") {
                IsgWorkspaceInlineAttachmentField(
                    title: "Kontrol raporunu bu işlemde ekle (isteğe bağlı)",
                    attachment: $attachment)
                NovaHelpHint(text: "Rapor seçilirse kontrol kaydıyla birlikte yüklenir ve ekipman geçmişine bağlanır.")
            }
        case .annualAddItem:
            textField("Faaliyet", text: $note)
            textField("Sorumlu / iletişim", text: $contact)
            DatePicker("Planlanan tarih", selection: $date,
                       in: annualPlanDateRange, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
        case .boardAddDecision:
            Stepper("Karar no: \(number)", value: $number, in: 1...10_000)
                .padding(12).novaControlBackground(cornerRadius: 14)
            textField("Karar", text: $note)
            textField("Sorumlu / iletişim", text: $contact)
            DatePicker("Termin", selection: $secondDate, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
        case .visitAddObservation:
            textField("Gözlem", text: $note)
            textField("Harici referans", text: $contact)
        default:
            NovaHelpHint(text: "Bu işlem mevcut kayıt sürümü doğrulandıktan sonra uygulanır.")
        }
        if action.acceptsAttachment && action != .equipmentInspect {
            NovaCompanyAccordion(title: "Dosya ve kanıt", symbol: "doc.badge.plus",
                identifier: "workspace.domain.action.attachment",
                expanded: $attachmentOpen) {
                IsgWorkspaceInlineAttachmentField(
                    title: "Bu işleme dosya ekle (isteğe bağlı)",
                    attachment: $attachment)
            }
        }
    }

    private var employeePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: "Katılımcılar", style: .bodyStrong)
            if loading { ProgressView() }
            ForEach(selectableEmployees) { employee in
                Button {
                    if selectedEmployees.contains(employee.id) { selectedEmployees.remove(employee.id) }
                    else { selectedEmployees.insert(employee.id) }
                } label: {
                    HStack {
                        Image(systemName: selectedEmployees.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                        NovaText(text: employee.name, style: .body)
                        Spacer()
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle())
            }
        }.padding(12).novaControlBackground(cornerRadius: 14)
    }

    private func equipmentAccordion<Content: View>(_ step: EquipmentStep, title: String, symbol: String,
                                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        NovaCompanyAccordion(title: title, symbol: symbol, state: equipmentStepComplete(step) ? .complete : .missing,
            identifier: "workspace.equipment.inspection.\(step.rawValue)",
            expanded: Binding(get: { equipmentOpen == step }, set: { equipmentOpen = $0 ? step : nil })) {
            content()
        }
    }

    private func equipmentStepComplete(_ step: EquipmentStep) -> Bool {
        switch step {
        case .control: return option == "fail" || (!hasNextDue || secondDate > date)
        case .details: return !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .report: return true
        }
    }

    private func compactDate(_ title: String, selection: Binding<Date>, enabled: Bool = true,
                             limitToToday: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: title, style: .metaQuiet)
            if enabled {
                if limitToToday {
                    DatePicker(title, selection: selection, in: ...Date(), displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                } else {
                    DatePicker(title, selection: selection, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact)
                }
            } else {
                NovaText(text: "Tarih yok", style: .bodyStrong)
            }
        }.padding(10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .novaControlBackground(cornerRadius: 14)
    }

    private var selectableEmployees: [IsgWorkspaceEmployeeEntry] {
        guard action == .trainingComplete else { return employees }
        let enrolled = Set(row.trainingParticipants.map(\.id))
        return employees.filter { enrolled.contains($0.id) }
    }

    private func textField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text, axis: .vertical).lineLimit(1...4)
            .font(NovaFont.font(.body)).padding(14).novaControlBackground(cornerRadius: 14)
    }
    private func picker(_ title: String, values: [String]) -> some View {
        Picker(title, selection: $option) {
            ForEach(values, id: \.self) { value in
                Text(IsgWorkspaceDisplayText.value(value)).tag(value)
            }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }

    private var canSubmit: Bool {
        switch action {
        case .trainingComplete: return !selectedEmployees.isEmpty && !row.trainingParticipants.isEmpty
        case .riskEditDraft:
            guard let draft = riskDraft else { return false }
            return date <= Date() && (draft.kind != "partial" || !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
                (!["partial", "metadata"].contains(draft.kind) || note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10)
        case .riskCancelDraft: return note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
        case .nonconformityTransition(let state):
            if state == "assigned" { return !contact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if ["cancelled", "open", "in_progress", "reopened"].contains(state) {
                return note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 5
            }
            return true
        case .nonconformityAddAction, .annualAddItem, .boardAddDecision, .visitAddObservation:
            return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .drillPerform, .boardHold: return !selectedEmployees.isEmpty
        case .drillCancel, .boardCancel: return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .ppeReturn: return remainingPPE > 0 && number <= remainingPPE
        case .checklistAnswer: return !checklistItemCode.isEmpty
        case .equipmentInspect:
            return row.version != nil && equipmentStepComplete(.control) && equipmentStepComplete(.details)
        case .equipmentEdit:
            return row.version != nil && workplaceID != nil && !serialTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && date <= Date()
        case .equipmentRule:
            return !fact("equipment_type", default: "").isEmpty && (1...240).contains(number) &&
                (option != "unapproved_fixture" || note.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10)
        default: return row.version != nil
        }
    }

    private var remainingPPE: Int {
        max(0, (Int(fact("quantity") ?? "0") ?? 0) - (Int(fact("returned_quantity") ?? "0") ?? 0))
    }

    private var suggestedRiskPeriod: Int {
        switch companyHazardClass.lowercased() {
        case "high", "very_dangerous", "cok_tehlikeli", "çok tehlikeli": return 2
        case "medium", "dangerous", "tehlikeli": return 4
        default: return 6
        }
    }

    private var periodMonths: Int { max(1, Int(fact("period_months") ?? "12") ?? 12) }

    private var riskDraft: IsgWorkspaceRiskVersion? {
        row.riskVersions.first(where: { $0.state == "draft" })
    }

    private func recalculateEquipmentDueDate() {
        guard action == .equipmentInspect else { return }
        if option == "fail" {
            hasNextDue = false
            return
        }
        hasNextDue = true
        secondDate = Calendar(identifier: .gregorian).date(byAdding: .month, value: periodMonths, to: date)
            ?? Calendar.current.date(byAdding: .year, value: 1, to: date) ?? date
    }

    private var checklistResultOptions: [String] {
        guard let item = row.checklistItems.first(where: { $0.code == checklistItemCode }) else {
            return ["conform", "nonconform"]
        }
        return item.allowsNotApplicable ? ["conform", "nonconform", "not_applicable"] : ["conform", "nonconform"]
    }

    private var selectedChecklistItem: IsgWorkspaceChecklistItem? {
        row.checklistItems.first(where: { $0.code == checklistItemCode })
    }

    private var checklistMinimumDate: Date {
        guard let value = fact("started_on"), let date = Self.date(value) else { return Date() }
        return date
    }

    private var appointmentMinimumDate: Date {
        guard let value = fact("starts_on"), let starts = Self.date(value) else { return Date() }
        return Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: starts) ?? Date()
    }

    private var annualPlanDateRange: ClosedRange<Date> {
        let calendar = Calendar(identifier: .gregorian)
        let fallbackYear = calendar.component(.year, from: Date())
        let year = Int(fact("plan_year") ?? "") ?? fallbackYear
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = calendar.date(from: DateComponents(year: year, month: 12, day: 31)) ?? start
        return start...end
    }

    @MainActor private func prepare() async {
        option = action == .equipmentInspect ? "pass" : action == .ppeReturn ? "reusable" : "accepted"
        if action == .riskFinalize {
            number = Int(fact("period_years") ?? "") ?? suggestedRiskPeriod
        }
        if action == .riskEditDraft, let draft = riskDraft {
            date = Self.date(draft.kind == "full" ? draft.assessmentOn : (draft.revisionOn ?? draft.assessmentOn)) ?? Date()
            contact = draft.scopeSummary ?? ""
            note = draft.reason ?? ""
            return
        }
        if action == .equipmentInspect {
            recalculateEquipmentDueDate()
            return
        }
        if action == .equipmentEdit {
            workplaceID = fact("workplace_id").flatMap(UUID.init(uuidString:))
            serialTag = fact("serial_tag") ?? row.subtitle ?? ""
            locationNote = fact("location_note") ?? ""
            date = fact("acquired_on").flatMap(Self.date) ?? Date()
            return
        }
        if action == .equipmentRule {
            number = max(1, Int(fact("period_months") ?? "12") ?? 12)
            let currentSource = fact("period_source") ?? "manufacturer"
            option = ["manufacturer", "rule_version", "unapproved_fixture"].contains(currentSource)
                ? currentSource : "manufacturer"
            note = fact("period_exception_note") ?? ""
            return
        }
        if action == .checklistAnswer, let item = row.checklistItems.first {
            checklistItemCode = item.code
            option = item.result ?? "conform"
            note = item.note ?? ""
            createChecklistNonconformity = false
            secondDate = max(secondDate, checklistMinimumDate)
        }
        if action == .appointmentEnd { secondDate = max(secondDate, appointmentMinimumDate) }
        if action == .annualAddItem, !annualPlanDateRange.contains(date) { date = annualPlanDateRange.lowerBound }
        guard action == .drillPerform || action == .boardHold || action == .trainingComplete else { return }
        loading = true
        do {
            employees = try await store.employees()
            if action == .trainingComplete {
                selectedEmployees = Set(row.trainingParticipants.filter(\.attended).map(\.id))
            }
        }
        catch { self.error = "Personel listesi yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }

    private func save() {
        guard canSubmit else { return }
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                guard let command = payload(assetID: uploaded?.assetID) else {
                    throw IsgWorkspaceAPIFailure.invalidRequest
                }
                var attempt = mutationAttempt
                let mutationID = attempt.id(
                    namespace: "domain.action.\(domain.rawValue).\(action.id)", payload: command)
                mutationAttempt = attempt
                _ = try await store.mutateDomain(mutationID: mutationID, domain: domain, payload: command)
                try await attach(uploaded)
                celebrate(NovaSuccessMessage.recordSaved(action.title))
                onDone()
            } catch {
                self.error = "İşlem tamamlanamadı. Kayıt sürümünü ve girdiğiniz bilgileri kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }

    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard action.acceptsAttachment, let attachment else { return nil }
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "domain.action.\(action.id).file.upload", components: [
            attachment.filename, IsgWorkspaceMutationAttempt.digest(attachment.data)
        ])
        mutationAttempt = attempt
        return try await store.uploadFile(
            mutationID: mutationID, title: attachment.title,
            filename: attachment.filename, category: attachmentCategory,
            data: attachment.data)
    }

    private func attach(_ uploaded: IsgWorkspaceFileUploadResult?) async throws {
        guard let uploaded, let parentKind = attachmentParentKind else { return }
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "domain.action.\(action.id).file.attach", components: [
            uploaded.entryID.uuidString, row.id.uuidString, parentKind
        ])
        mutationAttempt = attempt
        _ = try await store.attachFile(
            mutationID: mutationID, entryID: uploaded.entryID,
            parentKind: parentKind, parentID: row.id,
            fieldName: attachmentFieldName)
    }

    private var attachmentCategory: String {
        switch domain {
        case .training: return "training_material"
        case .risk: return "risk_assessment"
        case .drill: return "emergency_plan"
        case .ppe: return "handover_form"
        case .equipment: return "inspection_report"
        case .board: return "board_document"
        case .visit: return "visit_evidence"
        default: return "other"
        }
    }

    private var attachmentParentKind: String? {
        switch domain {
        case .training: return "training"
        case .risk: return "risk_assessment"
        case .nonconformity: return "nonconformity"
        case .checklist: return "checklist"
        case .drill: return "drill"
        case .ppe: return "ppe"
        case .equipment: return "equipment"
        case .annualPlan: return "annual_plan"
        case .board: return "board"
        case .visit: return "site_visit"
        default: return nil
        }
    }

    private var attachmentFieldName: String {
        switch action {
        case .equipmentInspect: return "inspection_report"
        case .boardHold: return "minutes"
        case .visitAddObservation: return "evidence"
        case .ppeReturn: return "return_evidence"
        case .nonconformityVerify: return "verification"
        default: return "attachment"
        }
    }

    private func payload(assetID: UUID? = nil) -> [String: IsgWorkspaceRPCValue]? {
        guard let version = row.version else { return nil }
        let base: [String: IsgWorkspaceRPCValue] = ["id": .id(row.id), "expected_version": .number(Int(version))]
        func merged(_ extra: [String: IsgWorkspaceRPCValue]) -> [String: IsgWorkspaceRPCValue] {
            base.merging(extra) { _, new in new }
        }
        switch action {
        case .trainingComplete:
            return merged(["action": .string("complete"),
                "participants": .array(row.trainingParticipants.map { participant in
                    .object(["id": .id(participant.id),
                             "attended": .bool(selectedEmployees.contains(participant.id))])
                })])
        case .trainingCancel: return merged(["action": .string("cancel")])
        case .riskEditDraft:
            guard let current = Int(fact("current_version") ?? ""), let draft = riskDraft else { return nil }
            return ["action": .string("edit_draft"), "assessment_id": .id(row.id),
                    "expected_current": .number(current), "version": .number(draft.number),
                    "expected_edit_revision": .number(draft.editRevision),
                    "assessment_on": .string(draft.kind == "full" ? Self.day(date) : draft.assessmentOn),
                    "revision_on": draft.kind == "full" ? .null : .string(Self.day(date)),
                    "scope": .object(draft.kind == "partial" ? ["summary": .string(contact.trimmingCharacters(in: .whitespacesAndNewlines))] : [:]),
                    "reason": ["partial", "metadata"].contains(draft.kind)
                        ? .string(note.trimmingCharacters(in: .whitespacesAndNewlines)) : .null]
        case .riskFinalize:
            guard let current = Int(fact("current_version") ?? ""),
                  let draft = Int(fact("draft_version") ?? "") else { return nil }
            return ["action": .string("finalize"), "assessment_id": .id(row.id),
                    "expected_current": .number(current), "version": .number(draft),
                    "expected_edit_revision": .number(riskDraft?.editRevision ?? 0),
                    "period_years": fact("draft_kind") == "full" ? .number(number) : .null]
        case .riskCancelDraft:
            guard let current = Int(fact("current_version") ?? ""), let draft = riskDraft else { return nil }
            return ["action": .string("cancel_draft"), "assessment_id": .id(row.id),
                    "expected_current": .number(current), "version": .number(draft.number),
                    "expected_edit_revision": .number(draft.editRevision),
                    "cancellation_note": .string(note.trimmingCharacters(in: .whitespacesAndNewlines))]
        case .nonconformityTransition(let state):
            return merged(["action": .string("transition"), "to_state": .string(state),
                           "reason": note.isEmpty ? .null : .string(note),
                           "assignee_contact": contact.isEmpty ? .null : .string(contact)])
        case .nonconformityAddAction:
            return merged(["action": .string("add_action"), "description": .string(note),
                           "assignee_contact": contact.isEmpty ? .null : .string(contact),
                           "due_on": .string(Self.day(secondDate))])
        case .nonconformityVerify:
            return merged(["action": .string("verify"), "verified_on": .string(Self.day(date)),
                           "outcome": .string(option), "note": note.isEmpty ? .null : .string(note)])
        case .checklistAnswer:
            var values: [String: IsgWorkspaceRPCValue] = [
                "action": .string("answer"), "item_code": .string(checklistItemCode),
                "result": .string(option), "note": note.isEmpty ? .null : .string(note),
                "create_nonconformity": .bool(option == "nonconform" && createChecklistNonconformity &&
                                                selectedChecklistItem?.nonconformityID == nil)
            ]
            if option == "nonconform" && createChecklistNonconformity &&
                selectedChecklistItem?.nonconformityID == nil {
                values["severity"] = .string(checklistSeverity)
                values["due_on"] = .string(Self.day(secondDate))
            }
            return merged(values)
        case .checklistSubmit: return merged(["action": .string("submit")])
        case .checklistCancel: return merged(["action": .string("cancel")])
        case .drillPerform:
            return merged(["entity": .string("drill"), "action": .string("perform"),
                           "performed_on": .string(Self.day(date)),
                           "participants": .array(selectedEmployees.sorted { $0.uuidString < $1.uuidString }.map { .id($0) }),
                           "observation": note.isEmpty ? .null : .string(note),
                           "improvement": contact.isEmpty ? .null : .string(contact)])
        case .drillCancel:
            return merged(["entity": .string("drill"), "action": .string("cancel"), "reason": .string(note)])
        case .appointmentEnd:
            return merged(["entity": .string("appointment"), "action": .string("end"),
                           "ends_before": .string(Self.day(secondDate))])
        case .ppeReturn:
            return merged(["entity": .string("ppe"), "action": .string("return"),
                           "quantity": .number(number), "returned_on": .string(Self.day(date)),
                           "condition": .string(option), "note": note.isEmpty ? .null : .string(note)])
        case .equipmentInspect:
            return merged(["action": .string("record_inspection"), "performed_on": .string(Self.day(date)),
                           "result": .string(option),
                           "next_due_on": option == "fail" || !hasNextDue ? .null : .string(Self.day(secondDate)),
                           "inspector": contact.isEmpty ? .null : .string(contact),
                           "external_ref": externalRef.isEmpty ? .null : .string(externalRef),
                           "note": note.isEmpty ? .null : .string(note),
                           "workspace_asset_id": assetID.map(IsgWorkspaceRPCValue.id) ?? .null,
                           "katip_declared": .bool(katipDeclared),
                           "katip_note": katipDeclared && !katipNote.isEmpty ? .string(katipNote) : .null])
        case .equipmentEdit:
            guard let workplaceID else { return nil }
            return merged(["action": .string("update"), "workplace_id": .id(workplaceID),
                           "serial_tag": .string(serialTag.trimmingCharacters(in: .whitespacesAndNewlines)),
                           "acquired_on": .string(Self.day(date)),
                           "location_note": locationNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? .null : .string(locationNote.trimmingCharacters(in: .whitespacesAndNewlines))])
        case .equipmentRule:
            guard let type = fact("equipment_type"), !type.isEmpty else { return nil }
            return ["action": .string("set_rule"), "equipment_type": .string(type),
                    "period_months": .number(number), "period_source": .string(option),
                    "exception_note": note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? .null : .string(note.trimmingCharacters(in: .whitespacesAndNewlines))]
        case .equipmentArchive: return merged(["action": .string("archive")])
        case .katipArchive:
            return merged(["kind": .string("katip_contract"), "action": .string("archive")])
        case .annualAddItem:
            return ["kind": .string("annual_item"), "action": .string("create"), "plan_id": .id(row.id),
                    "activity": .string(note), "responsible_contact": contact.isEmpty ? .null : .string(contact),
                    "planned_on": .string(Self.day(date))]
        case .annualClose:
            return merged(["kind": .string("annual_plan"), "action": .string("close")])
        case .boardHold:
            return merged(["kind": .string("board"), "action": .string("hold"),
                           "held_on": .string(Self.day(date)),
                           "attendance": .array(selectedEmployees.sorted { $0.uuidString < $1.uuidString }.map { .id($0) }),
                           "workspace_asset_id": assetID.map(IsgWorkspaceRPCValue.id) ?? .null])
        case .boardAddDecision:
            return ["kind": .string("board_decision"), "action": .string("create"),
                    "meeting_id": .id(row.id), "decision_no": .number(number), "decision_text": .string(note),
                    "responsible_contact": contact.isEmpty ? .null : .string(contact),
                    "due_on": .string(Self.day(secondDate))]
        case .boardCancel:
            return merged(["kind": .string("board"), "action": .string("cancel"), "reason": .string(note)])
        case .permitArchive:
            return merged(["kind": .string("work_permit"), "action": .string("archive")])
        case .visitAddObservation:
            return ["kind": .string("site_observation"), "action": .string("create"),
                    "visit_id": .id(row.id), "note": .string(note),
                    "workspace_asset_id": assetID.map(IsgWorkspaceRPCValue.id) ?? .null,
                    "nonconformity_id": .null, "external_ref": contact.isEmpty ? .null : .string(contact)]
        }
    }

    private func fact(_ key: String) -> String? { row.facts.first(where: { $0.0 == key })?.1 }
    private func fact(_ key: String, default value: String) -> String { fact(key) ?? value }
    private static func day(_ value: Date) -> String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.string(from: value)
    }
    private static func date(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: value)
    }
}

private struct IsgWorkspaceDownloadedFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct IsgWorkspaceChangeScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let companyName: String?
    let onBack: () -> Void
    @State private var rows: [IsgWorkspaceChange]?
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    NovaPageHeading(title: NovaDestination.notifications.title, onBack: onBack)
                    if let companyName {
                        NovaHelpHint(text: String(format: RDLocalization.string(
                            "localizable.nova.workspace.change.scope", table: .localizable,
                            fallback: "%@ firmasındaki yetkili değişiklikler gösteriliyor."), companyName))
                    }
                    if loading {
                        NovaLoadingView(message: RDLocalization.string(
                            "localizable.nova.workspace.change.loading", table: .localizable,
                            fallback: "Değişiklikler yükleniyor…"))
                    } else if let error {
                        NovaEmptyState(title: RDLocalization.string(
                                "localizable.nova.workspace.change.failed", table: .localizable,
                                fallback: "Değişiklikler yüklenemedi"), message: error)
                    } else if (rows ?? []).isEmpty {
                        NovaEmptyState(title: RDLocalization.string(
                                "localizable.nova.workspace.change.empty", table: .localizable,
                                fallback: "Henüz değişiklik yok"),
                            message: RDLocalization.string(
                                "localizable.nova.workspace.change.empty.detail", table: .localizable,
                                fallback: "Bu çalışma alanındaki kayıt hareketleri burada görünür."))
                    } else {
                        ForEach(rows ?? [], id: \.sequence) { row in
                            NovaCard(padding: 12) {
                                HStack(spacing: 10) {
                                    NovaIcon(symbol: "arrow.triangle.2.circlepath", size: 18)
                                    VStack(alignment: .leading, spacing: 3) {
                                        NovaText(text: IsgWorkspaceDisplayText.field(row.aggregateType),
                                                 style: .bodyStrong)
                                        NovaText(text: IsgWorkspaceDisplayText.event(row.eventType),
                                                 style: .metaQuiet)
                                    }
                                    Spacer(minLength: 0)
                                    NovaText(text: "#\(row.sequence)", style: .metaQuiet)
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
                    .novaAsyncContent(isLoading: loading)
            }
            .refreshable { revision = UUID() }
        }
        .task(id: revision) { await load() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) }
                catch { return }
                await load(showLoading: false)
            }
        }
    }

    @MainActor private func load(showLoading: Bool = true) async {
        if showLoading { loading = true }
        error = nil
        do { rows = try await store.changes(limit: 100).rows }
        catch {
            rows = nil
            self.error = RDLocalization.string("localizable.nova.workspace.connection.retry", table: .localizable,
                                               fallback: "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        if showLoading { loading = false }
    }
}
