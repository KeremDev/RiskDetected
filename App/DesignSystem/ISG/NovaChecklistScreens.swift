import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// module these closures.
struct NovaChecklistClient {
    let catalogue: (UUID?) async throws -> NovaChecklistCatalogue
    let templates: (UUID?) async throws -> [NovaChecklistTemplate]
    let board: (NovaChecklistQuery) async throws -> NovaChecklistBoard
    let companies: () async throws -> [NovaAnalysisCompanyOption]
    let detail: (UUID) async throws -> NovaChecklistRun
    let startRun: (UUID, UUID, String, String) async throws -> NovaChecklistRun?
    let answer: (UUID, NovaChecklistAnswerDraft) async throws -> NovaChecklistRun?
    let submit: (UUID, UUID) async throws -> NovaChecklistRun?
    let cancel: (UUID, UUID) async throws -> NovaChecklistRun?
    let draftTemplate: (UUID, String) async throws -> Void
    let setItem: (UUID, String, Int, String, String, Bool, Int) async throws -> Void
    let removeItem: (UUID, String, Int, String) async throws -> Void
    let publishTemplate: (UUID, String, Int, String) async throws -> Void
}

/// One counter, in the same shape the rest of the modules use.
struct NovaChecklistStatCard: View {
    let state: NovaChecklistRunState
    let value: Int
    var isSelected = false
    let onTap: () -> Void
    var body: some View {
        NovaListStat(title: state.title, symbol: state.symbol, value: value,
            isSelected: isSelected, onTap: onTap)
            .accessibilityIdentifier("nova.checklist.stat.\(state.rawValue)")
    }
}

/// One run as a row.
struct NovaChecklistRunCard: View {
    let run: NovaChecklistRun
    let onTap: () -> Void
    @Environment(\.colorScheme) private var scheme

    private var status: NovaStatus {
        switch run.state {
        case .open: return .info
        case .submitted: return run.nonconform > 0 ? .warning : .success
        case .cancelled: return .neutral
        }
    }

    var body: some View {
        Button(action: onTap) {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: run.templateTitle ?? run.templateCode, style: .cardTitle)
                            NovaText(text: [run.workplaceName, run.companyName]
                                .compactMap { $0 }.joined(separator: " · "), style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        NovaStatusPill(label: run.state.title, status: status)
                    }
                    NovaText(text: NovaChecklistWords.explain(run), style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                    HStack(spacing: 10) {
                        fact("calendar", RDLocalization.string("localizable.nova.checklist.row.started",
                            table: .localizable, fallback: "Başlangıç"), run.startedOn)
                        fact("number", RDLocalization.string("localizable.nova.checklist.row.version",
                            table: .localizable, fallback: "Liste sürümü"), "v\(run.templateVersion)")
                    }
                    if run.nonconformitiesOpened > 0 {
                        NovaAnalysisTag(symbol: "exclamationmark.triangle",
                            text: String(format: RDLocalization.string("localizable.nova.checklist.row.opened",
                                table: .localizable, fallback: "%d uygunsuzluk kaydı açıldı"),
                                run.nonconformitiesOpened), status: .warning)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("nova.checklist.row.\(run.id.uuidString)")
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

/// The Kontrol Listeleri surface: the runs, and the lists they are filled
/// against.
struct NovaChecklistScreen: View {
    let client: NovaChecklistClient
    let onBack: () -> Void
    var canWrite: Bool = true
    var initialCompany: UUID?
    var headingOverride: String?

    @State private var board: NovaChecklistBoard?
    @State private var catalogue: NovaChecklistCatalogue?
    @State private var templates: [NovaChecklistTemplate] = []
    @State private var companies: [NovaAnalysisCompanyOption] = []
    @State private var query = NovaChecklistQuery()
    @State private var tab = 0
    @State private var loading = true
    @State private var failure: String?
    @State private var openChooser: String?
    @State private var detail: NovaChecklistRun?
    @State private var showingTemplates = false
    @State private var showingStart = false
    @State private var startedRun: NovaChecklistRun?
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.checklist.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.checklist.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    NovaHelpHint(text: "Kontrol listesini seçin, soruları yanıtlayın ve sonucu kaydedin.")
                    NovaHelpHint(text: NovaChecklistWords.noProductList)
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
        .novaPopup(isPresented: $showingStart, onDismiss: {
            if let startedRun { detail = startedRun; self.startedRun = nil }
            Task { await load(reset: true) }
        }) {
            NovaCompanyCreateFlow(title: "Kontrol başlat", companies: client.companies,
                catalogue: client.catalogue, onSelect: { _ in }, fixedCompany: initialCompany) { catalogue, company in
                NovaChecklistStartForm(catalogue: catalogue) { workplace, template, day in
                    do {
                        guard let run = try await client.startRun(company, workplace, template, day) else {
                            return NovaChecklistFailure.unavailable.message
                        }
                        startedRun = (try? await client.detail(run.id)) ?? run
                        showingStart = false
                        return nil
                    } catch let error as NovaChecklistFailure { return error.message }
                    catch { return NovaChecklistFailure.unavailable.message }
                }
            }
        }
        .novaPopup(item: $detail) { run in
            NovaChecklistRunSheet(run: run, canWrite: canWrite,
                onAnswer: { draft in await answer(draft) },
                onSubmit: { await submit(run) },
                onCancel: { await cancel(run) },
                onClose: { detail = nil })
        }
        .novaPopup(isPresented: $showingTemplates, onDismiss: { Task { await load(reset: true) } }) {
            NovaCompanyCreateFlow(title: "Kontrol Listeleri", companies: client.companies,
                catalogue: client.catalogue, onSelect: { _ in }, fixedCompany: initialCompany) { _, company in
                NovaChecklistAuthoring(client: client, company: company, onClose: { showingTemplates = false })
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaListHeading(title: headingOverride ?? NovaDestination.checklists.title, onBack: onBack) {
                if canWrite {
                    NovaButton(label: "Listelerim", symbol: "list.bullet.rectangle", variant: .surface, compact: true) { showingTemplates = true }
                }
            }
            if canWrite {
                NovaButton(label: "Kontrol başlat", symbol: "play", compact: true) { showingStart = true }
                    .accessibilityIdentifier("nova.checklist.start")
            }
        }
    }

    @ViewBuilder private func counters(_ board: NovaChecklistBoard) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8),
                       GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(NovaChecklistRunState.allCases) { state in
                NovaChecklistStatCard(state: state, value: board.count(state),
                    isSelected: query.state == state.rawValue) {
                    query.state = query.state == state.rawValue ? nil : state.rawValue
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
                    label: RDLocalization.string("localizable.nova.checklist.filter.company", table: .localizable, fallback: "Firma"),
                    value: companies.first { $0.id == query.company }?.name ?? allCompanies,
                    isOpen: openChooser == "company",
                    identifier: "nova.checklist.chooser.company") {
                    openChooser = openChooser == "company" ? nil : "company"
                }
                NovaFileChooserButton(
                    label: RDLocalization.string("localizable.nova.checklist.filter.state", table: .localizable, fallback: "Durum"),
                    value: query.state.flatMap { NovaChecklistRunState(rawValue: $0)?.title } ?? allStates,
                    isOpen: openChooser == "state",
                    identifier: "nova.checklist.chooser.state") {
                    openChooser = openChooser == "state" ? nil : "state"
                }
            }
            if openChooser == "company" {
                NovaFileChooserPanel(options: companyOptions, selected: query.company?.uuidString,
                    identifier: "nova.checklist.panel.company") { value in
                    query.company = value.flatMap(UUID.init(uuidString:))
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            if openChooser == "state" {
                NovaFileChooserPanel(options: stateOptions, selected: query.state,
                    identifier: "nova.checklist.panel.state") { value in
                    query.state = value
                    openChooser = nil
                    Task { await load(reset: true) }
                }
            }
            NovaAnalysisSearchField(
                text: $query.search,
                placeholder: RDLocalization.string("localizable.nova.checklist.search", table: .localizable,
                    fallback: "Liste, işyeri veya firma ara"),
                identifier: "nova.checklist.search")
                .onSubmit { Task { await load(reset: true) } }
        }
    }

    private var companyOptions: [NovaFileChooserOption] {
        (initialCompany == nil ? [.init(id: nil, title: allCompanies)] : [])
            + companies.filter { initialCompany == nil || $0.id == initialCompany }.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaChecklistRunState.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
    }

    @ViewBuilder private func list(_ board: NovaChecklistBoard) -> some View {
        if board.rows.isEmpty {
            NovaEmptyState(title: RDLocalization.string("localizable.nova.checklist.empty.title",
                table: .localizable, fallback: "Henüz kontrol kaydı yok"),
                message: "Bir kontrol listesi seçerek işyeri denetimini başlatabilir ve sonuçları dijital ortamda saklayabilirsiniz.")
        } else {
            VStack(spacing: 10) {
                ForEach(board.rows) { run in
                    NovaChecklistRunCard(run: run) { Task { await openDetail(run) } }
                }
                NovaText(text: String(format: RDLocalization.string("localizable.nova.checklist.count",
                    table: .localizable, fallback: "%d / %d kayıt"), board.rows.count, board.total),
                    style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                if board.hasMore {
                    NovaButton(label: RDLocalization.string("localizable.nova.checklist.more", table: .localizable,
                        fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface) {
                        Task { await load(reset: false) }
                    }
                }
            }
        }
    }

    // MARK: work

    private func load(reset: Bool) async {
        if reset { query.offset = 0 } else { query.offset += query.limit }
        loading = true; failure = nil
        do {
            if companies.isEmpty { companies = try await client.companies() }
            if query.company == nil, let initialCompany { query.company = initialCompany }
            catalogue = try await client.catalogue(query.company)
            templates = try await client.templates(query.company)
            let answer = try await client.board(query)
            if reset || board == nil { board = answer }
            else if let existing = board {
                board = .init(rows: existing.rows + answer.rows, counts: answer.counts,
                              companies: answer.companies, total: answer.total,
                              hasMore: answer.hasMore, offset: answer.offset)
            }
        } catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        loading = false
    }

    private func openDetail(_ run: NovaChecklistRun) async {
        do { detail = try await client.detail(run.id) } catch { detail = run }
    }

    private func company(for run: NovaChecklistRun) -> UUID? { run.companyID ?? query.company }

    private func answer(_ draft: NovaChecklistAnswerDraft) async -> String? {
        guard let run = detail, let company = company(for: run) else { return NovaChecklistFailure.validation.message }
        do {
            if let updated = try await client.answer(company, draft) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func submit(_ run: NovaChecklistRun) async -> String? {
        guard let company = company(for: run) else { return NovaChecklistFailure.validation.message }
        do {
            if let updated = try await client.submit(company, run.id) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func cancel(_ run: NovaChecklistRun) async -> String? {
        guard let company = company(for: run) else { return NovaChecklistFailure.validation.message }
        do {
            if let updated = try await client.cancel(company, run.id) { detail = updated }
            await load(reset: true)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func draftTemplate(_ title: String) async -> String? {
        guard let company = query.company else { return NovaChecklistFailure.validation.message }
        do { try await client.draftTemplate(company, title); templates = try await client.templates(company); return nil }
        catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func setItem(_ code: String, _ version: Int, _ item: String, _ prompt: String,
                         _ allowsNA: Bool, _ position: Int) async -> String? {
        guard let company = query.company else { return NovaChecklistFailure.validation.message }
        do {
            try await client.setItem(company, code, version, item, prompt, allowsNA, position)
            templates = try await client.templates(company); return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func removeItem(_ code: String, _ version: Int, _ item: String) async -> String? {
        guard let company = query.company else { return NovaChecklistFailure.validation.message }
        do {
            try await client.removeItem(company, code, version, item)
            templates = try await client.templates(company); return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func publish(_ code: String, _ version: Int, _ note: String) async -> String? {
        guard let company = query.company else { return NovaChecklistFailure.validation.message }
        do {
            try await client.publishTemplate(company, code, version, note)
            templates = try await client.templates(company)
            catalogue = try await client.catalogue(company)
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }
}
