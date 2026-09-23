import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaEmergencyClient {
    let catalogue: (UUID?) async throws -> NovaEmergencyCatalogue
    let board: (NovaEmergencyQuery) async throws -> NovaEmergencyBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaEmergencyPlan
    /// Publishing is the only write: a new plan, or the next version of one.
    let publish: (UUID, NovaEmergencyPlanDraft) async throws -> NovaEmergencyPlan?
    /// The same file archive Dosyalarım reads and writes. The plan attaches one
    /// of its own entries rather than keeping a second, separate upload path.
    let fileClient: NovaFileLibraryClient
    /// Active personnel belonging to the selected company. The chosen name is
    /// copied into the immutable plan-team snapshot when the plan is saved.
    var employees: (UUID, String, UUID?) async throws -> NovaEmployeePage = { _,_,_ in
        throw NovaPersonnelFailure.unavailable
    }
}

/// One counter, in the same shape the rest of the modules use.
struct NovaEmergencyStatCard: View {
    let group: NovaEmergencyGroup
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    var body: some View {
        NovaListStat(title: group.title, symbol: group.symbol, value: value,
            isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("nova.emergency.stat.\(group.rawValue)")
    }
}

/// One plan as a row.
struct NovaEmergencyPlanCard: View {
    let plan: NovaEmergencyPlan
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch plan.group {
        case .expired: return .danger
        case .untracked: return .warning
        case .dueSoon: return .info
        case .current: return .success
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: plan.scope, style: .cardTitle)
                            NovaText(text: [plan.workplaceName, plan.companyName]
                                .compactMap { $0 }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " · "), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: NovaEmergencyWords.state(plan.state), status: status)
                    }
                    HStack(spacing: 10) {
                        fact("calendar", RDLocalization.string("localizable.nova.emergency.row.prepared",
                            table: .localizable, fallback: "Hazırlanma"), plan.preparedOn)
                        if let until = plan.validUntil {
                            fact("calendar.badge.clock", RDLocalization.string("localizable.nova.emergency.row.until",
                                table: .localizable, fallback: "Geçerlilik"), until)
                        }
                        fact("person.2", RDLocalization.string("localizable.nova.emergency.row.team",
                            table: .localizable, fallback: "Ekip"), "\(plan.teamSize)")
                        fact("number", RDLocalization.string("localizable.nova.emergency.row.version",
                            table: .localizable, fallback: "Sürüm"), "v\(plan.version)")
                    }
                }
            }
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.emergency.row.\(plan.id.uuidString)")
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

/// The Acil Durum Planları surface.
struct NovaEmergencyPlanScreen: View {
    let client: NovaEmergencyClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var headingOverride: String?
    /// Opened from the company page's own empty-state "Ekle" action.
    var startInAddMode = false
    var management: ((UUID, UUID) -> AnyView)?
    @State private var draftCompany: UUID?

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var board: NovaEmergencyBoard?
    @State private var catalogue: NovaEmergencyCatalogue?
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var fileCategories: [NovaFileCategory] = []
    @State private var fileAccepts: [NovaFileAcceptance] = []
    @State private var fileAssurance = NovaFileAssurance()
    @State private var query = NovaEmergencyQuery()
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaEmergencyPlan?
    @State private var drafting: NovaEmergencyPlanDraft?
    @State private var savedDraft: NovaEmergencyPlanDraft?
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.emergency.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.emergency.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        // Opened straight into "add": the create flow alone is the entire
        // cover, so it blurs the real company page instead of an empty
        // intermediate board screen. See NovaPopup's own doc comment.
        if startInAddMode {
            addFlow(savedDraft ?? .init(preparedOn: NovaDayField.text(Date())))
        } else {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.emergency.plan.screens.firmanin.acil.durum.planini.ve.dosyasini.ekleyin.69acbe04", table: .localizable, fallback: "Firmanın acil durum planını ve dosyasını ekleyin; geçerlilik tarihini buradan takip edin."))
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
        .novaPopup(item: $detail) { plan in
            NovaEmergencyDetailSheet(plan: plan, canWrite: canWrite, fileClient: client.fileClient,
                onRenew: {
                    detail = nil
                    draftCompany = plan.companyID
                    drafting = .init(planID: plan.id, workplaceID: plan.workplaceID,
                                     scope: plan.scope, preparedOn: NovaDayField.text(Date()),
                                     team: plan.team, assetID: plan.assetID)
                },
                onClose: { detail = nil })
                .safeAreaInset(edge: .bottom) {
                    if canWrite, let company = plan.companyID, let management {
                        NovaModuleManageAction(content: { management(company, plan.id) }, onDone: {
                            detail = nil; Task { await load(reset: true) }
                        })
                    }
                }
        }
        .novaFullScreenCover(item: $drafting) { draft in
            if draft.planID != nil {
                NovaEmergencyPlanSheet(draft: draft, catalogue: catalogue,
                    fileClient: client.fileClient, fileCompany: draftCompany,
                    fileCategories: fileCategories, fileAccepts: fileAccepts, fileAssurance: fileAssurance,
                employees: client.employees,
                    onSave: { edited in await publish(edited) },
                    onSaveDraft: { value in savedDraft = value; drafting = nil },
                    onClose: { drafting = nil })
            } else {
                addFlow(draft)
            }
        }
        }
    }
    private func addFlow(_ draft: NovaEmergencyPlanDraft) -> some View {
        NovaCompanyCreateFlow(title: RDLocalization.string("localizable.nova.emergency.plan.screens.acil.durum.plani.ekle.6345682f", table: .localizable, fallback: "Acil durum planı ekle"), companies: client.companies,
            catalogue: client.catalogue, onSelect: { draftCompany = $0 }, fixedCompany: initialCompany,
            fullScreenTask: true, onClose: { if startInAddMode { onBack() } else { drafting = nil } }) { selectedCatalogue, selectedCompany in
            NovaEmergencyPlanSheet(draft: draft, catalogue: selectedCatalogue,
                fileClient: client.fileClient, fileCompany: selectedCompany,
                fileCategories: fileCategories, fileAccepts: fileAccepts, fileAssurance: fileAssurance,
                employees: client.employees,
                onSave: { edited in await publish(edited) },
                onSaveDraft: { value in savedDraft = value; drafting = nil },
                onClose: { if startInAddMode { onBack() } else { drafting = nil } })
        }
    }

    private var header: some View {
        NovaListHeading(title: headingOverride ?? NovaDestination.emergencyPlans.title, onBack: onBack) {
            if canWrite {
                NovaButton(label: RDLocalization.string("localizable.nova.emergency.plan.screens.plan.ekle.c35e3b6a", table: .localizable, fallback: "Plan Ekle"), symbol: "plus", compact: true) { startCreate() }
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaEmergencyBoard) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : 4)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaEmergencyGroup.allCases) { group in
                NovaEmergencyStatCard(group: group, value: board.count(group),
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
                    label: RDLocalization.string("localizable.nova.emergency.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.emergency.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.emergency.filter.state", table: .localizable, fallback: "Durum"),
                    value: stateTitle,
                    isOpen: openChooser == "state",
                    identifier: "nova.emergency.chooser.state") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.emergency.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "state" {
                NovaFileChooserPanel(options: stateOptions, selected: query.state,
                    identifier: "nova.emergency.panel.state") { value in
                    query.state = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.emergency.search", table: .localizable,
                    fallback: "Kapsam, işyeri veya firma ara"),
                identifier: "nova.emergency.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var stateTitle: String {
        guard let state = query.state else { return allStates }
        if let group = NovaEmergencyGroup(rawValue: state) { return group.title }
        if let value = NovaEmergencyState(rawValue: state) { return NovaEmergencyWords.state(value) }
        return allStates
    }
    private var companyOptions: [NovaFileChooserOption] {
        (initialCompany == nil ? [.init(id: nil, title: allCompanies)] : [])
            + companies.filter { initialCompany == nil || $0.id == initialCompany }.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaEmergencyGroup.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
            + NovaEmergencyState.allCases.filter { state in !NovaEmergencyGroup.allCases.contains { $0.rawValue == state.rawValue } }.map {
                .init(id: $0.rawValue, title: NovaEmergencyWords.state($0), count: board?.counts[$0.rawValue]) }
    }

    @ViewBuilder private func list(_ board: NovaEmergencyBoard) -> some View {
        if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.emergency.empty.title",
                table: .localizable, fallback: "Plan yok"),
                message: RDLocalization.string("localizable.nova.emergency.plan.screens.plan.ekleyerek.ekibi.dosyayi.ve.gecerlilik.tarih.58b42265", table: .localizable, fallback: "Plan ekleyerek ekibi, dosyayı ve geçerlilik tarihini dijital ortamda takip edebilirsiniz."))
        } else {
            VStack(spacing: 10) {
                ForEach(board.rows) { plan in
                    NovaEmergencyPlanCard(plan: plan) { Task { await openDetail(plan) } }
                }
                NovaText(text: String(format: RDLocalization.string("localizable.nova.emergency.count",
                    table: .localizable, fallback: "%d / %d plan"), board.rows.count, board.total),
                    style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.emergency.more", table: .localizable,
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
        drafting = savedDraft ?? .init(preparedOn: NovaDayField.text(Date()))
    }

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true; failure = nil
        do {
            if companies.isEmpty { companies = try await client.companies() }
            if fileCategories.isEmpty {
                let filing = try await client.fileClient.catalogue()
                fileCategories = filing.categories; fileAccepts = filing.accepts; fileAssurance = filing.assurance
            }
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
        } catch let error as NovaEmergencyFailure { failure = error.message }
        catch { failure = NovaEmergencyFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ plan: NovaEmergencyPlan) async {
        draftCompany = plan.companyID
        do {
            catalogue = try await client.catalogue(plan.companyID)
            detail = try await client.detail(plan.id)
        } catch { failure = "Kayıt açılamadı. Yeniden deneyin." }
    }

    private func publish(_ draft: NovaEmergencyPlanDraft) async -> String? {
        guard let company = draftCompany ?? query.company else { return NovaEmergencyFailure.validation.message }
        do {
            _ = try await client.publish(company, draft)
            savedDraft = nil
            drafting = nil
            await load(reset: true)
            return nil
        } catch let error as NovaEmergencyFailure { return error.message }
        catch { return NovaEmergencyFailure.unavailable.message }
    }
}

extension NovaEmergencyPlanDraft: Identifiable {
    var id: String { (planID?.uuidString ?? "new") + (workplaceID?.uuidString ?? "") }
}
