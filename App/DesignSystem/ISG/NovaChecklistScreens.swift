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
    @Environment(\.colorScheme) private var scheme

    private var tone: NovaColorToken {
        switch state {
        case .open: return .statusInfoInk
        case .submitted: return .statusSuccessInk
        case .cancelled: return .textMuted
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: state.symbol).font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tone.color(in: scheme))
                    NovaSizedText(text: "\(value)", size: 19, weight: "ExtraBold")
                }
                NovaSizedText(text: state.title, size: 10, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                    .lineLimit(2).minimumScaleFactor(0.82)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                NovaSizedText(text: state.footer, size: 9.5, weight: "Bold",
                    color: value > 0 ? tone.color(in: scheme) : NovaColorToken.textMuted.color(in: scheme))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10).padding(.horizontal, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NovaColorToken.surface.color(in: scheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isSelected ? tone.color(in: scheme)
                                : NovaColorToken.hairline.color(in: scheme),
                                lineWidth: isSelected ? 1.6 : 1))
            )
        }
        .buttonStyle(.plain)
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
    @State private var starting = false
    @State private var showingTemplates = false
    @Environment(\.colorScheme) private var scheme

    private var allCompanies: String {
        RDLocalization.string("localizable.nova.checklist.filter.companies", table: .localizable, fallback: "Tüm firmalar")
    }
    private var allStates: String {
        RDLocalization.string("localizable.nova.checklist.filter.states", table: .localizable, fallback: "Tüm durumlar")
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
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
                    if canWrite { starters }
                }
                .padding(.horizontal, 20).padding(.top, 12)
                .padding(.bottom, 24 + novaTabBarInset)
            }
        }
        .task { await load(reset: true) }
        .sheet(item: $detail) { run in
            NovaChecklistRunSheet(run: run, canWrite: canWrite,
                onAnswer: { draft in await answer(draft) },
                onSubmit: { await submit(run) },
                onCancel: { await cancel(run) },
                onClose: { detail = nil })
        }
        .sheet(isPresented: $showingTemplates) {
            NovaChecklistTemplateSheet(templates: templates, canWrite: canWrite,
                onDraft: { title in await draftTemplate(title) },
                onSetItem: { code, version, item, prompt, allowsNA, position in
                    await setItem(code, version, item, prompt, allowsNA, position)
                },
                onRemoveItem: { code, version, item in await removeItem(code, version, item) },
                onPublish: { code, version, note in await publish(code, version, note) },
                onClose: { showingTemplates = false })
        }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                NovaButton(label: RDLocalization.string("localizable.nova.checklist.back", table: .localizable, fallback: "Geri"),
                    symbol: "chevron.left", variant: .surface, action: onBack)
                Spacer(minLength: 0)
                if canWrite {
                    NovaButton(label: RDLocalization.string("localizable.nova.checklist.templates",
                        table: .localizable, fallback: "Listelerim"), symbol: "list.bullet.rectangle",
                        variant: .surface) { showingTemplates = true }
                }
            }
            NovaText(text: headingOverride ?? NovaDestination.checklists.title, style: .screenTitle)
            // Said once, at the top, rather than implied by an empty screen.
            NovaText(text: NovaChecklistWords.noProductList, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
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
        [.init(id: nil, title: allCompanies)]
            + companies.map { .init(id: $0.id.uuidString, title: $0.name) }
    }
    private var stateOptions: [NovaFileChooserOption] {
        [.init(id: nil, title: allStates)]
            + NovaChecklistRunState.allCases.map {
                .init(id: $0.rawValue, title: $0.title, count: board?.count($0), symbol: $0.symbol) }
    }

    @ViewBuilder private func list(_ board: NovaChecklistBoard) -> some View {
        if board.rows.isEmpty {
            NovaCard(padding: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.empty.title", table: .localizable,
                        fallback: "Kontrol kaydı yok"), style: .cardTitle)
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.empty.body", table: .localizable,
                        fallback: "Önce bir liste yazıp yayımlayın, sonra bir işyeri için kontrol başlatın."),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
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

    @ViewBuilder private var starters: some View {
        if let catalogue, query.company != nil {
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.checklist.start.title", table: .localizable,
                        fallback: "Kontrol başlat"), style: .cardTitle)
                    if catalogue.starters.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.start.none", table: .localizable,
                            fallback: "Yayımlanmış liste yok. Listelerim'den bir liste yazıp yayımlayın."),
                            style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    } else if catalogue.workplaces.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.checklist.start.noplace", table: .localizable,
                            fallback: "Bu firmada işyeri kaydı yok."),
                            style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    } else {
                        ForEach(catalogue.starters) { starter in
                            VStack(alignment: .leading, spacing: 6) {
                                NovaText(text: starter.title + " · v\(starter.version) · "
                                    + String(format: RDLocalization.string("localizable.nova.checklist.start.items",
                                        table: .localizable, fallback: "%d soru"), starter.items), style: .label)
                                ForEach(catalogue.workplaces) { workplace in
                                    NovaButton(label: workplace.name, symbol: "play.circle", variant: .surface) {
                                        Task { await start(starter.templateCode, workplace.id) }
                                    }
                                    .disabled(starting)
                                }
                            }
                        }
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

    private func start(_ template: String, _ workplace: UUID) async {
        guard let company = query.company else { return }
        starting = true; failure = nil
        do {
            _ = try await client.startRun(company, workplace, template, NovaDayField.text(Date()))
            await load(reset: true)
        } catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        starting = false
    }

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
