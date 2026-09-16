import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaDrillClient {
    let catalogue: (UUID?) async throws -> NovaDrillCatalogue
    let board: (NovaDrillQuery) async throws -> NovaDrillBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaDrill
    let plan: (UUID, NovaDrillPlanDraft) async throws -> NovaDrill?
    let record: (UUID, NovaDrillResultDraft) async throws -> NovaDrill?
    let cancel: (UUID, UUID, String) async throws -> NovaDrill?
}

/// One counter, in the same shape the rest of the modules use.
struct NovaDrillStatCard: View {
    let group: NovaDrillGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    var body: some View {
        NovaListStat(title: group.title, symbol: group.symbol, value: value,
            isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("nova.drill.stat.\(group.rawValue)")
    }
}

/// One drill as a row.
struct NovaDrillCard: View {
    let drill: NovaDrill
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch drill.state {
        case .overdue: return .danger
        case .dueSoon: return .info
        case .scheduled: return .warning
        case .performed: return .success
        case .cancelled: return .neutral
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: drill.planScope ?? RDLocalization.string(
                                "localizable.nova.drill.row.plan", table: .localizable, fallback: "Acil durum planı"),
                                style: .cardTitle)
                            NovaText(text: [drill.workplaceName, drill.companyName]
                                .compactMap { $0 }.joined(separator: " · "), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: NovaDrillWords.state(drill.state), status: status)
                    }
                    NovaText(text: NovaDrillWords.explain(drill), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    HStack(spacing: 10) {
                        fact("calendar", RDLocalization.string("localizable.nova.drill.row.planned",
                            table: .localizable, fallback: "Planlanan"), drill.plannedOn)
                        if let performed = drill.performedOn {
                            fact("checkmark.circle", RDLocalization.string("localizable.nova.drill.row.performed",
                                table: .localizable, fallback: "Yapılan"), performed)
                        }
                        fact("number", RDLocalization.string("localizable.nova.drill.row.version",
                            table: .localizable, fallback: "Plan sürümü"), "v\(drill.planVersion)")
                    }
                    if drill.planVersionSuperseded {
                        NovaAnalysisTag(symbol: "arrow.triangle.branch",
                            text: RDLocalization.string("localizable.nova.drill.row.superseded",
                                table: .localizable, fallback: "Prova edilen plan sürümü güncellendi"),
                            status: .info)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nova.drill.row.\(drill.id.uuidString)")
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

/// The Tatbikatlar surface.
struct NovaDrillScreen: View {
    let client: NovaDrillClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var headingOverride: String?
    var management: ((UUID, UUID) -> AnyView)?
    @State private var draftCompany: UUID?

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var board: NovaDrillBoard?
    @State private var catalogue: NovaDrillCatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaDrillQuery()
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaDrill?
    @State private var planning: NovaDrillPlanDraft?
    @State private var recording: NovaDrillResultDraft?
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.drill.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.drill.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaHelpHint(text: "Firmanın tatbikat kayıtlarını ve gerçekleşme sonuçlarını inceleyin.")
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
        .novaPopup(item: $detail) { drill in
            NovaDrillDetailSheet(drill: drill, canWrite: canWrite,
                onRecord: {
                    detail = nil
                    recording = .init(drillID: drill.id, planScope: drill.planScope ?? "",
                                      performedOn: NovaDayField.text(Date()))
                },
                onCancel: { reason in await cancel(drill, reason) },
                onClose: { detail = nil })
                .safeAreaInset(edge: .bottom) {
                    if canWrite, let company = drill.companyID, let management {
                        NovaModuleManageAction(content: { management(company, drill.id) }, onDone: {
                            detail = nil; Task { await load(reset: true) }
                        })
                    }
                }
        }
        .novaPopup(item: $planning) { draft in
            NovaCompanyCreateFlow(title: "Tatbikat planla", companies: client.companies,
                catalogue: client.catalogue, onSelect: { draftCompany = $0 }, fixedCompany: initialCompany) { selectedCatalogue, _ in
                NovaDrillPlanSheet(draft: draft, catalogue: selectedCatalogue,
                    onSave: { edited in await plan(edited) }, onClose: { planning = nil })
            }
        }
        .novaPopup(item: $recording) { draft in
            NovaDrillResultSheet(draft: draft, catalogue: catalogue,
                onSave: { edited in await record(edited) }, onClose: { recording = nil })
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? NovaDestination.drills.title, onBack: onBack) {
            if canWrite {
                NovaButton(label: "Tatbikat Ekle", symbol: "plus", compact: true) { startCreate() }
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaDrillBoard) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaDrillGroup.allCases) { group in
                NovaDrillStatCard(group: group, value: board.count(group),
                    isSelected: query.state == group.rawValue) {
                    query.state = query.state == group.rawValue ? nil : group.rawValue
                    Task { await load(reset: true) }
                }
            }
        }
    }

    /// Side by side, and the list opens below what was tapped.
    @ViewBuilder private var filters: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.drill.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.drill.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.drill.filter.state", table: .localizable, fallback: "Durum"),
                    value: stateTitle,
                    isOpen: openChooser == "state",
                    identifier: "nova.drill.chooser.state") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.drill.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "state" {
                NovaFileChooserPanel(options: stateOptions, selected: query.state,
                    identifier: "nova.drill.panel.state") { value in
                    query.state = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.drill.search", table: .localizable,
                    fallback: "Plan, işyeri veya firma ara"),
                identifier: "nova.drill.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var stateTitle: String {
        guard let state = query.state else { return allStates }
        if let group = NovaDrillGroup(rawValue: state) { return group.title }
        if let value = NovaDrillState(rawValue: state) { return NovaDrillWords.state(value) }
        return allStates
    }
    private var companyOptions: [NovaFileChooserOption] {
        (initialCompany == nil ? [.init(id: nil, title: allCompanies)] : [])
            + companies.filter { initialCompany == nil || $0.id == initialCompany }.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaDrillGroup.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
            + NovaDrillState.allCases.filter { state in !NovaDrillGroup.allCases.contains { $0.rawValue == state.rawValue } }.map {
                .init(id: $0.rawValue, title: NovaDrillWords.state($0), count: board?.counts[$0.rawValue]) }
    }

    @ViewBuilder private func list(_ board: NovaDrillBoard) -> some View {
        if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.drill.empty.title",
                table: .localizable, fallback: "Henüz tatbikat kaydı yok"),
                message: "Gerçekleşen tatbikatı fotoğraf, dosya, süre ve senaryo bilgileriyle kaydedip takip edebilirsiniz.")
        } else {
            VStack(spacing: 10) {
                ForEach(board.rows) { drill in
                    NovaDrillCard(drill: drill) { Task { await openDetail(drill) } }
                }
                NovaText(text: String(format: RDLocalization.string("localizable.nova.drill.count",
                    table: .localizable, fallback: "%d / %d tatbikat"), board.rows.count, board.total),
                    style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.drill.more", table: .localizable,
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
        planning = .init(plannedOn: NovaDayField.text(Date()))
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
                              hasMore: answer.hasMore, offset: answer.offset,
                              noticeDays: answer.noticeDays)
            }
        } catch let error as NovaDrillFailure { failure = error.message }
        catch { failure = NovaDrillFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ drill: NovaDrill) async {
        draftCompany = drill.companyID
        do {
            catalogue = try await client.catalogue(drill.companyID)
            detail = try await client.detail(drill.id)
        } catch { failure = "Kayıt açılamadı. Yeniden deneyin." }
    }

    private func plan(_ draft: NovaDrillPlanDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaDrillFailure.validation.message }
        do {
            _ = try await client.plan(company, draft)
            planning = nil
            await load(reset: true)
            return nil
        } catch let error as NovaDrillFailure { return error.message }
        catch { return NovaDrillFailure.unavailable.message }
    }

    private func record(_ draft: NovaDrillResultDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaDrillFailure.validation.message }
        do {
            _ = try await client.record(company, draft)
            recording = nil
            await load(reset: true)
            return nil
        } catch let error as NovaDrillFailure { return error.message }
        catch { return NovaDrillFailure.unavailable.message }
    }

    private func cancel(_ drill: NovaDrill, _ reason: String) async -> String? {
        guard let company = drill.companyID ?? query.company else { return NovaDrillFailure.validation.message }
        do {
            if let updated = try await client.cancel(company, drill.id, reason) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaDrillFailure { return error.message }
        catch { return NovaDrillFailure.unavailable.message }
    }
}

extension NovaDrillPlanDraft: Identifiable { var id: String { (planID?.uuidString ?? "new") + plannedOn } }
extension NovaDrillResultDraft: Identifiable { var id: String { drillID?.uuidString ?? "new" } }
