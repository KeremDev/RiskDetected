import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaAppointmentClient {
    let catalogue: (UUID?) async throws -> NovaAppointmentCatalogue
    let board: (NovaAppointmentQuery) async throws -> NovaAppointmentBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaAppointment
    let record: (UUID, NovaAppointmentDraft) async throws -> NovaAppointment?
    let end: (UUID, NovaAppointmentEndDraft) async throws -> NovaAppointment?
    let fileClient: NovaFileLibraryClient
}

/// One counter, in the same shape the rest of the modules use.
struct NovaAppointmentStatCard: View {
    let state: NovaAppointmentState
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    private var tone: NovaStatus {
        switch state {
        case .active: return .success
        case .upcoming: return .warning
        case .ended: return .neutral
        }
    }
    var body: some View {
        NovaListStat(title: state.title, symbol: state.symbol, value: value,
            status: tone, isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("nova.appointment.stat.\(state.rawValue)")
    }
}

/// One appointment as a row.
struct NovaAppointmentCard: View {
    let entry: NovaAppointment
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch entry.state {
        case .active: return .success
        case .upcoming: return .info
        case .ended: return .neutral
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: entry.employeeName ?? RDLocalization.string(
                                "localizable.nova.appointment.row.person", table: .localizable, fallback: "Personel"),
                                style: .cardTitle)
                            NovaText(text: [entry.kind.title, entry.workplaceName, entry.companyName]
                                .compactMap { $0 }.joined(separator: " · "), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: entry.state.title, status: status)
                    }
                    NovaText(text: NovaAppointmentWords.explain(entry), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    HStack(spacing: 10) {
                        fact("calendar", RDLocalization.string("localizable.nova.appointment.row.starts",
                            table: .localizable, fallback: "Başlangıç"), entry.startsOn)
                        if let ends = entry.endsBefore {
                            fact("calendar.badge.minus", RDLocalization.string("localizable.nova.appointment.row.ends",
                                table: .localizable, fallback: "Bitiş"), ends)
                        }
                    }
                    if let basis = entry.basis {
                        NovaAnalysisTag(symbol: basis.symbol, text: basis.title, status: .info)
                    }
                    if entry.employeeArchived {
                        NovaAnalysisTag(symbol: "person.badge.minus",
                            text: RDLocalization.string("localizable.nova.appointment.row.archived",
                                table: .localizable, fallback: "Personel kaydı arşivlendi"),
                            status: .neutral)
                    }
                }
            }
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.appointment.row.\(entry.id.uuidString)")
    }

    @ViewBuilder private func fact(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            VStack(alignment: .leading, spacing: 0) {
                NovaSizedText(text: label, size: 9, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                NovaSizedText(text: value, size: 11, weight: "Bold")
            }
        }
    }
}

/// The Atama ve Temsilciler surface.
struct NovaAppointmentScreen: View {
    let client: NovaAppointmentClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var initialRecordID: UUID?
    var headingOverride: String?
    /// Opened from the company page's own empty-state "Ekle" action.
    var startInAddMode = false
    var management: ((UUID, UUID) -> AnyView)?
    @State private var draftCompany: UUID?

    @State private var board: NovaAppointmentBoard?
    @State private var catalogue: NovaAppointmentCatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaAppointmentQuery()
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaAppointment?
    @State private var drafting: NovaAppointmentDraft?
    @State private var ending: NovaAppointmentEndDraft?
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.appointment.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.appointment.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }
    private var allRoles: String {
        RDLocalization.string("localizable.nova.appointment.filter.roles", table: .localizable, fallback: "Tüm görevler")
    }

    var body: some View {
        // Opened straight into "add": the create flow alone is the entire
        // cover, so it blurs the real company page instead of an empty
        // intermediate board screen. See NovaPopup's own doc comment.
        if startInAddMode {
            addFlow(.init(startsOn: NovaDayField.text(Date())))
        } else {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaListHint(text: RDLocalization.format("localizable.nova.appointment.screens.firmayi.ve.personeli.secerek.gorevlendirme.kaydi.6dbf8606", table: .localizable, fallback: "Firmayı ve personeli seçerek görevlendirme kaydı oluşturun; belgesini aynı kayda ekleyin. %1$@ %2$@", arguments: [String(describing: NovaAppointmentWords.noQualificationNote), String(describing: NovaAppointmentWords.noRequiredCountNote)]))
                    if let board { counters(board) }
                    filters
                    if loading && board == nil {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let failure {
                        NovaCard(padding: 16) {
                            NovaText(text: failure, style: .body,
                                color: NovaColorToken.statusDangerInk.color(in: scheme))
                        }
                    } else if let board {
                        list(board)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 12)
                .padding(.bottom, 24 + novaTabBarInset)
            }
        }
        .task { await load(reset: true) }
        .task(id: initialRecordID) {
            guard let initialRecordID else { return }
            detail = try? await client.detail(initialRecordID)
        }
        .novaPopup(item: $detail) { row in
            NovaAppointmentDetailSheet(entry: row, canWrite: canWrite, fileClient: client.fileClient,
                onEnd: {
                    detail = nil
                    ending = .init(appointmentID: row.id, employeeName: row.employeeName ?? "",
                                   startsOn: row.startsOn,
                                   endsBefore: row.endsBefore ?? NovaDayField.text(Date()),
                                   isCorrection: row.endsBefore != nil)
                },
                onClose: { detail = nil })
                .safeAreaInset(edge: .bottom) {
                    if canWrite, let company = row.companyID, let management {
                        NovaModuleManageAction(content: { management(company, row.id) }, onDone: {
                            detail = nil; Task { await load(reset: true) }
                        })
                    }
                }
        }
        .novaFullScreenCover(item: $drafting) { draft in addFlow(draft) }
        .novaPopup(item: $ending) { draft in
            NovaAppointmentEndSheet(draft: draft,
                onSave: { edited in await finish(edited) }, onClose: { ending = nil })
        }
        }
    }
    private func addFlow(_ draft: NovaAppointmentDraft) -> some View {
        NovaCompanyCreateFlow(title: RDLocalization.string("localizable.nova.appointment.screens.gorev.ver.48c63666", table: .localizable, fallback: "Görev ver"), companies: client.companies,
            catalogue: client.catalogue, onSelect: { draftCompany = $0 }, fixedCompany: initialCompany,
            fullScreenTask: true, onClose: { if startInAddMode { onBack() } else { drafting = nil } }) { selectedCatalogue, selectedCompany in
            NovaAppointmentSheet(draft: draft, catalogue: selectedCatalogue,
                fileClient: client.fileClient, fileCompany: selectedCompany,
                onSave: { edited in await save(edited) },
                onClose: { if startInAddMode { onBack() } else { drafting = nil } })
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? NovaDestination.appointments.title, onBack: onBack, actionBelow: true) {
            if canWrite {
                NovaListActionButton(title: RDLocalization.string("localizable.nova.appointment.screens.atama.ekle.684b4a9e", table: .localizable, fallback: "Atama Ekle"), symbol: "plus", tone: .primary) { startCreate() }
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaAppointmentBoard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                           GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(NovaAppointmentState.allCases) { state in
                    NovaAppointmentStatCard(state: state, value: board.count(state),
                        isSelected: query.state == state.rawValue) {
                        query.state = query.state == state.rawValue ? nil : state.rawValue
                        Task { await load(reset: true) }
                    }
                }
            }
        }
    }

    /// Side by side, and the list opens below what was tapped.
    @ViewBuilder private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.appointment.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.appointment.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.appointment.filter.role", table: .localizable, fallback: "Görev"),
                    value: query.role.flatMap { NovaAppointmentKind(rawValue: $0)?.title } ?? allRoles,
                    isOpen: openChooser == "role",
                    identifier: "nova.appointment.chooser.role") {
                    openChooser = openChooser == "role" ? nil : "role"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.appointment.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "role" {
                NovaFileChooserPanel(options: roleOptions, selected: query.role,
                    identifier: "nova.appointment.panel.role") { value in
                    query.role = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.appointment.search", table: .localizable,
                    fallback: "Kişi, işyeri veya firma ara"),
                identifier: "nova.appointment.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var companyOptions: [NovaFileChooserOption] {
        (initialCompany == nil ? [.init(id: nil, title: allCompanies)] : [])
            + companies.filter { initialCompany == nil || $0.id == initialCompany }.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    /// Only the roles the server accepts as a filter.
    private var roleOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allRoles)]
            + (catalogue?.roles ?? NovaAppointmentKind.allCases.map { .init(kind: $0, usualBasis: .appointed) })
                .map { .init(id: $0.kind.rawValue, title: $0.kind.title) }
    }

    @ViewBuilder private func list(_ board: NovaAppointmentBoard) -> some View {
        VStack(spacing: 10) {
            NovaListSectionHeading(title: headingOverride ?? NovaDestination.appointments.title,
                count: String(format: RDLocalization.string("localizable.nova.appointment.count",
                    table: .localizable, fallback: "%d / %d görev"), board.rows.count, board.total))
            if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.appointment.empty.title",
                table: .localizable, fallback: "Atama kaydı yok"),
                message: RDLocalization.string("localizable.nova.appointment.screens.firma.personelinden.temsilci.destek.elemani.veya.4a1c7448", table: .localizable, fallback: "Firma personelinden temsilci, destek elemanı veya ekip üyesi seçerek görev süresini takip edebilirsiniz."))
            } else {
                ForEach(board.rows) { row in
                    NovaAppointmentCard(entry: row) { Task { await openDetail(row) } }
                }
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.appointment.more", table: .localizable,
                        fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) {
                        Task { await load(reset: false) }
                    }
                }
            }
        }
    }

    // MARK: work

    private func startCreate() {
        draftCompany = nil
        drafting = .init(startsOn: NovaDayField.text(Date()))
    }

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true; failure = nil
        do {
            if companies.isEmpty { companies = try await client.companies() }
            if query.company == nil, let initialCompany { query.company = initialCompany }
            catalogue = try await client.catalogue(query.company)
            let answer = try await client.board(query)
            if reset || board == nil { board = answer }
            else if let existing = board {
                board = .init(rows: existing.rows + answer.rows, counts: answer.counts,
                              companies: answer.companies, total: answer.total,
                              hasMore: answer.hasMore, offset: answer.offset)
            }
        } catch let error as NovaAppointmentFailure { failure = error.message }
        catch { failure = NovaAppointmentFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ row: NovaAppointment) async {
        draftCompany = row.companyID
        do {
            catalogue = try await client.catalogue(row.companyID)
            detail = try await client.detail(row.id)
        } catch { failure = "Kayıt açılamadı. Yeniden deneyin." }
    }

    private func save(_ draft: NovaAppointmentDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaAppointmentFailure.validation.message }
        do {
            _ = try await client.record(company, draft)
            await load(reset: true)
            return nil
        } catch let error as NovaAppointmentFailure { return error.message }
        catch { return NovaAppointmentFailure.unavailable.message }
    }

    private func finish(_ draft: NovaAppointmentEndDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaAppointmentFailure.validation.message }
        do {
            _ = try await client.end(company, draft)
            ending = nil
            await load(reset: true)
            return nil
        } catch let error as NovaAppointmentFailure { return error.message }
        catch { return NovaAppointmentFailure.unavailable.message }
    }
}

extension NovaAppointmentDraft: Identifiable {
    var id: String { (employeeID?.uuidString ?? "new") + kind.rawValue }
}
extension NovaAppointmentEndDraft: Identifiable { var id: String { appointmentID?.uuidString ?? "new" } }
